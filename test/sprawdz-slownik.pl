#!/usr/bin/perl
# sprawdz-slownik.pl - konfrontuje slownik wyciagniety z binarki z tym, co
# naprawde stoi w plikach gry.
#
#   perl test/sprawdz-slownik.pl data/slownik/tablice.txt <katalog> [<katalog>...]
#
# Parser i reguly wyluskiwania nazw siedza w test/gem2.pm - ten sam kod uzywa
# preflight.pl, zeby oba narzedzia widzialy dokladnie to samo.
#
# Kierunek, ktory naprawde cos mowi: UZYTE, A NIE MA W SLOWNIKU. Taka nazwa
# znaczy, ze ekstrakcja ma dziure i slownikowi nie wolno ufac. Odwrotny kierunek
# (w slowniku, nieuzyte) nie jest bledem - silnik zna wiecej, niz kampania wola.

use strict; use warnings;
use File::Find;
use FindBin;
use lib $FindBin::Bin;
use gem2;

my ($dict, @dirs) = @ARGV;
die "uzycie: perl test/sprawdz-slownik.pl <tablice.txt> <katalog> [...]\n"
    unless $dict && @dirs;

# ---------- slownik ----------
my ($known) = gem2::wczytaj_slownik($dict);
die "$dict: $!\n" unless $known;
printf "slownik : %d nazw (%s)\n", scalar keys %$known, $dict;

# ---------- korpus ----------
my @files;
for my $dir (@dirs) { find(sub { push @files, $File::Find::name if -f }, $dir) }

my (%act_mi, %term_mi, %act_ent);
my %bucket = (akcja_mi => \%act_mi, term_mi => \%term_mi, akcja_encji => \%act_ent);
my ($n_mi, $n_ent, $bytes) = (0,0,0);
for my $f (@files) {
    next unless $f =~ /\.(mi|inc|set)$/i;
    open my $h, '<:raw', $f or next;
    my $txt = do { local $/; <$h> }; close $h;
    next unless $txt =~ /\{/;
    $bytes += length $txt;

    my $u = gem2::uzycia($txt);
    $bucket{$_->{rodzaj}}{$_->{nazwa}}{$f} = 1 for @{$u->{uzycia}};
    $n_mi++  if $u->{mi};
    $n_ent++ if $u->{ent};
}
printf "korpus  : %.1f MB, %d plikow misji, %d plikow interakcji\n\n",
    $bytes/1048576, $n_mi, $n_ent;

# ---------- raport ----------
my $gaps = 0;
sub report {
    my ($title, $used, %o) = @_;
    my @miss = sort grep { !$known->{$_} } keys %$used;
    printf "## %s - uzyte: %d, w tym spoza slownika: %d\n", $title, scalar keys %$used, scalar @miss;
    for my $n (@miss) {
        my @f = sort keys %{$used->{$n}};
        printf "   %-26s %3d plik(ow)  np. %s\n", $n, scalar @f, short($f[0]);
    }
    print "\n";
    $gaps += @miss unless $o{soft};
    return @miss;
}
sub short { my $p = shift; $p =~ s{.*[/\\]([^/\\]+[/\\][^/\\]+)$}{$1}; $p }

report('AKCJE TRIGGEROW (.mi)', \%act_mi);
report('TERMY WARUNKOW (.mi)',  \%term_mi);
report('AKCJE SKRYPTOW ENCJI (.inc/.set)', \%act_ent);

my %used = (%act_mi, %term_mi, %act_ent);
my @conf = sort grep { $used{$_} } keys %$known;
printf "## potwierdzone w plikach gry: %d z %d nazw slownika\n\n", scalar @conf, scalar keys %$known;

printf "WYNIK: %s\n", $gaps ? "$gaps nazw uzytych poza slownikiem - ekstrakcja ma dziure"
                            : 'slownik pokrywa kazda nazwe uzyta w korpusie';
exit($gaps ? 1 : 0);
