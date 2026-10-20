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
# Kazda sekcja idzie przeciw swojemu rejestrowi. Plaski zbior wszystkich nazw
# z tablice.txt przepuszczal nieistniejacy term "1.time", bo w tym samym
# zrzucie siedza tablice Lua z os.time - patrz gem2::%REJESTRY.
my $mod_of = gem2::wczytaj_slownik($dict);
die "$dict: $!\n" unless $mod_of;
my $gem2 = gem2::zestaw_gem2($mod_of);
my %zest = map { $_ => gem2::zestaw($mod_of, $_) } keys %gem2::REJESTRY;
printf "slownik : %d nazw (%s), w tym %d w rejestrach GEM2\n",
    scalar keys %$mod_of, $dict, scalar keys %$gem2;

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
    my ($title, $rodzaj, $used, %o) = @_;
    my @miss = sort grep { !$zest{$rodzaj}{$_} } keys %$used;
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

report('AKCJE TRIGGEROW (.mi)', 'akcja_mi', \%act_mi);
report('TERMY WARUNKOW (.mi)',  'term_mi',  \%term_mi);
report('AKCJE SKRYPTOW ENCJI (.inc/.set)', 'akcja_encji', \%act_ent);

my %used = (%act_mi, %term_mi, %act_ent);
my @conf = sort grep { $used{$_} } keys %$gem2;
printf "## potwierdzone w plikach gry: %d z %d nazw w rejestrach GEM2\n\n",
    scalar @conf, scalar keys %$gem2;

printf "WYNIK: %s\n", $gaps ? "$gaps nazw uzytych poza slownikiem - ekstrakcja ma dziure"
                            : 'slownik pokrywa kazda nazwe uzyta w korpusie';
exit($gaps ? 1 : 0);
