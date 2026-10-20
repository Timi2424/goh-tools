#!/usr/bin/perl
# kontekst.pl - gdzie wolno uzyc danej nazwy
#
#   perl test/kontekst.pl <nazwa> [<nazwa>...]
#   perl test/kontekst.pl --odswiez          przebuduj korpus z pakow i indeks
#
# PO CO TO ISTNIEJE
# Slownik z binarki (data/slownik/tablice.txt) mowi, CO silnik zna. Nie mowi,
# W JAKIM PLIKU wolno tego uzyc. "TravelAltitude" z tablicy podwozia airborne
# wygladal jak klucz .ext - wpisany do .ext dal crash i wywalil wczytywanie
# kampanii.
#
# Kolumna "kontekst" w slowniku zawezia liste kandydatow, ale jej nie
# rozstrzyga; dlatego czesc wpisow jest oznaczona "dane?" ze znakiem zapytania.
# JEDYNYM PEWNYM DOWODEM NA DOPUSZCZALNOSC JEST WYSTAPIENIE W PRAWDZIWYM PLIKU
# TEGO SAMEGO TYPU. Od tego jest ten skrypt.
#
# Odwrotny kierunek jest jeszcze mocniejszy: jesli nazwy nie ma ani w binarce,
# ani w zadnym pliku gry - nie istnieje. Tak rozstrzygnelismy spor o predykat
# "threating".
#
# Korpus, indeks i zasady "co jest dowodem" siedza w test/korpus.pm - tym
# samym, ktorego uzywa sprawdz-klucze.pl i preflight.pl.

use strict; use warnings;
use FindBin;
use lib $FindBin::Bin;
use korpus;

my $DICT = "$korpus::ROOT/data/slownik/tablice.txt";
my $ENUM = "$korpus::ROOT/data/slownik/enumy.txt";

if (@ARGV && $ARGV[0] eq '--odswiez') { korpus::buduj(); exit 0 }
my @szukane = @ARGV;
die "uzycie: perl test/kontekst.pl <nazwa> [...]\n       perl test/kontekst.pl --odswiez\n"
    unless @szukane;
korpus::buduj() unless korpus::jest_indeks();

if (my @stare = korpus::nieaktualne_paki()) {
    printf "UWAGA: %d pak(ow) nowszych niz korpus (%s...) - odpal --odswiez\n",
        scalar @stare, $stare[0];
}

my ($ix, $lc) = korpus::wczytaj_indeks(@szukane);

# ---------- slownik ----------
sub ze_slownika {
    my $nazwa = shift;
    my @hit;
    for my $plik ($DICT, $ENUM) {
        open my $h, '<', $plik or next;
        my $mod = '?';
        while (<$h>) {
            if (/^=== 0x\w+\s+(\S+)/) { $mod = $1; next }
            if ($plik eq $DICT) {
                next unless /^  (\S+)\s+(\S+)\s+(\S+)(.*)$/;
                my ($n, $kl, $kt, $par) = ($1, $2, $3, trim($4));
                if ($n eq $nazwa) {
                    push @hit, { modul => $mod, klasa => $kl, kontekst => $kt, par => $par };
                }
                # Nazwa bywa PARAMETREM akcji, a nie wpisem tablicy - tak jest
                # z "local_offset" przy spawnie. Bez tego skrypt mowilby
                # "nie ma w binarce" o czyms, co w niej jest.
                elsif (grep { $_ eq $nazwa } split /\s+/, $par) {
                    push @hit, { modul => $mod, klasa => "parametr akcji $n ($kl)",
                                 kontekst => $kt, par => '' };
                }
            } else {
                next unless /"\Q$nazwa\E"/;
                next unless /^(0x\w+)\s+(\S+)\s+(\S+)/;
                push @hit, { modul => $2, klasa => "enum $1", kontekst => $3, par => '' };
            }
        }
        close $h;
    }
    @hit;
}
sub trim { my $s = shift // ''; $s =~ s/^\s+|\s+$//g; $s }

# ---------- raport ----------
for my $nazwa (@szukane) {
    print "\n", "=" x 68, "\n  $nazwa\n", "=" x 68, "\n";

    my @d = ze_slownika($nazwa);
    print "\n-- slownik z binarki --\n";
    if (@d) {
        printf "  %-30s %-10s %s\n", 'klasa C++', 'kontekst', 'parametry';
        printf "  %-30s %-10s %s\n", $_->{klasa}, $_->{kontekst}, $_->{par} || '-' for @d;
    } else {
        print "  NIE MA W BINARCE. Jesli nie ma tez nizej - nazwa nie istnieje.\n";
    }

    print "\n-- wystapienia w prawdziwych plikach (bez komentarzy, bez naszych) --\n";
    my $po = $ix->{$nazwa} || {};
    unless (%$po) {
        if (@d) {
            print "  ZADNEGO. Silnik zna te nazwe, ale gra jej nigdzie nie uzywa -\n";
            print "  to KANDYDAT, nie potwierdzona skladnia. Sprawdz w laboratorium.\n";
        } else {
            print "  ZADNEGO. Ani w binarce, ani w plikach gry - NIE ISTNIEJE.\n";
            print "  (tak wygladal TravelAltitude przed crashem)\n";
        }
        if (my $inne = $lc->{lc $nazwa}) {
            my %u = map { $_->[0] => 1 } @$inne;
            print "  ALE inna wielkoscia liter wystepuje: ", join(', ', sort keys %u), "\n";
        }
        next;
    }

    my $suma = sub { my $x = shift; $x->{k} + $x->{b} + $x->{p} };
    printf "  %-10s %7s %7s %8s %9s   %s\n",
        'typ', 'plikow', '{nazwa', '{"nazwa', 'parametr', 'przyklad';
    for my $e (sort { $suma->($po->{$b}) <=> $suma->($po->{$a}) } keys %$po) {
        my $x = $po->{$e};
        printf "  .%-9s %7d %7d %8d %9d   %s\n", $e, @$x{qw(pliki k b p ex)};
    }

    print "\n-- werdykt --\n";
    for my $e (sort keys %$po) {
        my $x = $po->{$e};
        my @jak;
        push @jak, "klucz {$nazwa ...}"      if $x->{k};
        push @jak, "blok {\"$nazwa\" ...}"   if $x->{b};
        push @jak, "parametr w srodku bloku" if $x->{p};
        printf "  .%-9s %s\n", $e, join(', ', @jak);
    }
}
