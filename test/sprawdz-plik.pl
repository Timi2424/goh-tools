#!/usr/bin/perl
# sprawdz-plik.pl - kontrola pliku GEM2 przed wlozeniem go do gry
#
#   perl test/sprawdz-plik.pl <plik> [<plik>...]
#
# Nawiasy, glebokosc, sklejony wiersz }{"nazwa", znaki spoza ASCII.
# Komentarze (srednik do konca wiersza, poza stringami) sa wycinane przed
# kontrola.
#
# Kod zwrotu: 0 = czysto (moga byc uwagi), 1 = co najmniej jeden blad.
#
# To cienka nakladka na gem2::sprawdz_tekst - ta sama funkcja, ktorej uzywa
# preflight.pl. Skrypty powloki (zbuduj.sh, zainstaluj.sh) maja wolac ten
# plik zamiast trzymac wlasne kopie kontroli; trzy kopie juz raz sie rozjechaly.

use strict; use warnings;
use FindBin;
use lib $FindBin::Bin;
use gem2;

die "uzycie: perl test/sprawdz-plik.pl <plik> [...]\n" unless @ARGV;

my $bledy = 0;
for my $f (@ARGV) {
    open(my $h, '<:raw', $f) or do { print "BLAD $f: nie moge otworzyc ($!)\n"; $bledy++; next };
    local $/; my $txt = <$h>; close $h;
    # Ostatnie trzy czlony sciezki, nie sama nazwa: w grze jest kilka plikow
    # units_eng.set w roznych katalogach i sama nazwa nie mowi, ktory padl.
    my @cz = split m{[/\\]}, $f;
    my $n = join '/', @cz[($#cz > 2 ? $#cz - 2 : 0) .. $#cz];
    for my $p (gem2::sprawdz_tekst($txt)) {
        printf "%s %s%s: %s\n", ($p->{poziom} eq 'blad' ? 'BLAD ' : 'uwaga'),
            $n, ($p->{linia} ? ":$p->{linia}" : ''), $p->{opis};
        $bledy++ if $p->{poziom} eq 'blad';
    }
}
exit($bledy ? 1 : 0);
