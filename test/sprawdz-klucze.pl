#!/usr/bin/perl
# sprawdz-klucze.pl - czy klucze w .ext / .def wystepuja w prawdziwych plikach gry
#
#   perl test/sprawdz-klucze.pl <plik> [<plik>...]
#
# Klasa bledu TravelAltitude: nazwa wzieta z binarki, wpisana jako klucz .ext,
# crash przy wczytywaniu kampanii. Slownik tego nie lapie - tablice w .rdata
# mieszaja API skryptowe z kluczami plikow danych. Ten skrypt porownuje kazdy
# klucz {nazwa ...} z indeksem korpusu gry (test/korpus.pm).
#
# Dziala na DOWOLNYM pliku, nie tylko na tym, co lezy w modzie - bo
# TravelAltitude urodzil sie w eksperymencie, zanim cokolwiek trafilo do paczki.
#
# Kod zwrotu: 1, gdy jakis klucz nie wystepuje NIGDZIE w grze. Pozostale
# przypadki (inny typ pliku, inna wielkosc liter) to podpowiedzi - kod 0.

use strict; use warnings;
use FindBin;
use lib $FindBin::Bin;
use korpus;

die "uzycie: perl test/sprawdz-klucze.pl <plik.ext|plik.def> [...]\n" unless @ARGV;
unless (korpus::jest_indeks()) {
    print "brak indeksu korpusu - buduje (jednorazowo, ok. 3 min)\n";
    korpus::buduj();
}
if (my @stare = korpus::nieaktualne_paki()) {
    printf "UWAGA: %d pak(ow) nowszych niz korpus - wynik moze byc nieaktualny (kontekst.pl --odswiez)\n",
        scalar @stare;
}

my %ETYKIETA = (brak => 'BRAK ', gdzie_indziej => 'inny ', wielkosc => 'Aa   ');
my ($brak, $spr) = (0, 0);
for my $f (@ARGV) {
    my ($ext) = $f =~ /\.(\w+)$/;
    unless ($ext && $korpus::RODZINA{lc $ext}) { print "pomijam $f - tylko .ext i .def\n"; next }
    open(my $h, '<:raw', $f) or do { print "nie moge otworzyc $f: $!\n"; next };
    local $/; my $txt = <$h>; close $h;
    $spr++;
    (my $n = $f) =~ s{.*[/\\]}{};
    for my $p (korpus::sprawdz_klucze($txt, $ext)) {
        printf "%s %s:%d  {%s}  %s\n", $ETYKIETA{$p->{poziom}}, $n, $p->{linia}, $p->{nazwa}, $p->{opis};
        $brak++ if $p->{poziom} eq 'brak';
    }
}
print "sprawdzonych plikow: $spr, kluczy nieistniejacych w grze: $brak\n";
exit($brak ? 1 : 0);
