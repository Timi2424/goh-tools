#!/usr/bin/perl
# snapshot-upstream.pl - zrzuca do upstream/ te wersje plikow z pakow,
# na ktorych zbudowany jest nasz patch.
#
#   perl test/snapshot-upstream.pl
#
# Po co: nasze 19 plikow to zmienione kopie plikow Hortena i bazowej gry.
# Gdy on wyda update, trzeba wiedziec CO ZMIENILISMY MY, a co ON.
# Majac upstream/ robi sie to mechanicznie:
#
#   diff upstream/X  hf-patch/resource/X   = NASZA delta
#   diff upstream/X  <nowa wersja z paka>  = JEGO zmiany
#
# Bez tego trzeba zgadywac, a tak powstaly "nieaktualne nadpisania",
# ktore po cichu cofaly wrzesniowe poprawki Hortena.

use strict; use warnings;

my $MOD  = 'C:/Program Files (x86)/Steam/steamapps/workshop/content/400750/3359417100';
my $GAME = 'C:/Program Files (x86)/Steam/steamapps/common/Call to Arms - Gates of Hell';
my $REPO = 'C:/Users/PC/Documents/goh-tools';
my $PKG  = "$REPO/hf-patch/resource";
my $OUT  = "$REPO/upstream";

# gdzie szukac: [pak, prefiks do usuniecia ze sciezki wzglednej]
my @src = (
    [ "$MOD/resource/gamelogic.pak",        ''        ],
    [ "$MOD/resource/properties.pak",       ''        ],
    [ "$MOD/resource/map/multi.pak",        'map/'    ],
    [ "$MOD/resource/interface/interface.pak", 'interface/' ],
    [ "$GAME/resource/gamelogic.pak",       ''        ],
    [ "$GAME/resource/properties.pak",      ''        ],
    [ "$GAME/resource/map/multi.pak",       'map/'    ],
    [ "$GAME/resource/interface/interface.pak", 'interface/' ],
    [ "$GAME/resource/sound/sound.pak",     'sound/'  ],
);

my @rel; walk($PKG, '', \@rel);
printf "plikow patcha: %d\n\n", scalar @rel;

my ($got, $miss) = (0, 0);
for my $rel (sort @rel) {
    my $found;
    for my $s (@src) {
        my ($pak, $strip) = @$s;
        next unless -f $pak;
        my $ent = $rel;
        $ent =~ s/^\Q$strip\E// if $strip;
        my $data = qx{unzip -p "$pak" "$ent" 2>/dev/null};
        next unless length $data;
        my $dst = "$OUT/$rel";
        mkpath($dst);
        open(my $h, '>:raw', $dst) or die "$dst: $!";
        print $h $data; close $h;
        my $who = $pak =~ /workshop/ ? 'HORTEN' : 'GRA   ';
        printf "  %-6s %-56s %7d B\n", $who, $rel, length $data;
        $found = 1; $got++;
        last;
    }
    unless ($found) { printf "  BRAK   %-56s (plik tylko nasz)\n", $rel; $miss++ }
}

printf "\nzrzucono: %d, bez odpowiednika w pakach: %d\n", $got, $miss;
print "\nteraz nasza delta to po prostu:\n  diff -r upstream hf-patch/resource\n";

sub mkpath { my @p = split m{/}, shift; pop @p; my $d = '';
    for (@p) { $d .= "$_/"; mkdir $d unless -d $d } }
sub walk { my ($d, $pre, $out) = @_;
    opendir(my $h, $d) or return;
    for my $e (grep { !/^\.\.?$/ } readdir $h) {
        my $p = "$d/$e"; my $r = $pre ? "$pre/$e" : $e;
        if (-d $p) { walk($p, $r, $out) } else { push @$out, $r }
    }
    closedir $h;
}
