#!/usr/bin/perl
# kontekst.pl - gdzie wolno uzyc danej nazwy
#
#   perl test/kontekst.pl <nazwa> [<nazwa>...]
#   perl test/kontekst.pl --odswiez          przebuduj korpus z pakow
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

use strict; use warnings;
use File::Find;
use FindBin;

my $ROOT  = "$FindBin::Bin/..";
my $CACHE = "$ROOT/data/korpus";
my $DICT  = "$ROOT/data/slownik/tablice.txt";
my $ENUM  = "$ROOT/data/slownik/enumy.txt";

my $GAME = '/c/Program Files (x86)/Steam/steamapps/common/Call to Arms - Gates of Hell/resource';
my $HF   = '/c/Program Files (x86)/Steam/steamapps/workshop/content/400750/3359417100/resource';

# Tylko paki z tekstem. Reszta to tekstury, dzwiek i wideo - 90 GB, zero skladni.
my @PAKI = (
    [ 'gra-gamelogic'  => "$GAME/gamelogic.pak"        ],
    [ 'gra-properties' => "$GAME/properties.pak"       ],
    [ 'gra-multi'      => "$GAME/map/multi.pak"        ],
    [ 'gra-single'     => "$GAME/map/single.pak"       ],
    [ 'gra-vehicle'    => "$GAME/entity/-vehicle.pak"  ],
    [ 'gra-entity'     => "$GAME/entity/entity.pak"    ],
    [ 'gra-inventory'  => "$GAME/entity/inventory.pak" ],
    [ 'hf-gamelogic'   => "$HF/gamelogic.pak"          ],
    [ 'hf-properties'  => "$HF/properties.pak"         ],
    [ 'hf-multi'       => "$HF/map/multi.pak"          ],
    [ 'hf-vehicle'     => "$HF/entity/-vehicle.pak"    ],
    [ 'hf-entity'      => "$HF/entity/entity.pak"      ],
);
my $ROZSZ = qr/\.(def|ext|inc|set|mi|pattern|reg)$/i;

# ---------- budowa korpusu ----------
# unzip w tym Gicie NIE przepuszcza '*' przez '/', wiec wzorce typu '*.inc'
# nie dzialaja. Listujemy wiec katalog centralny (szybkie, nie czyta danych)
# i wyciagamy pliki po nazwie, partiami.
sub buduj {
    print "buduje korpus w $CACHE\n";
    mkdir "$ROOT/data" unless -d "$ROOT/data";
    mkdir $CACHE       unless -d $CACHE;

    for my $p (@PAKI) {
        my ($nazwa, $pak) = @$p;
        unless (-f $pak) { printf "  %-16s brak paka, pomijam\n", $nazwa; next }
        my $dir = "$CACHE/$nazwa";

        my @wpisy;
        open my $l, '-|', 'unzip', '-l', $pak or do { print "  $nazwa: unzip padl\n"; next };
        while (<$l>) {
            next unless /^\s*\d+\s+\S+\s+\S+\s+(\S.*)$/;
            my $n = $1; $n =~ s/\s+$//;
            next unless $n =~ $ROZSZ;
            # unzip traktuje wzorce jak globy, wiec nazwy z [ ] * ? trzeba
            # eskejpowac - inaczej "U.S. - [USN]/..." konczy sie na
            # "filename not matched" i plik cicho wypada z korpusu.
            $n =~ s/([][*?\\])/\\$1/g;
            push @wpisy, $n;
        }
        close $l;

        unless (@wpisy) { printf "  %-16s brak plikow tekstowych\n", $nazwa; next }
        for (my $i = 0; $i < @wpisy; $i += 200) {
            my $do = $i + 199; $do = $#wpisy if $do > $#wpisy;
            system('unzip', '-o', '-q', $pak, @wpisy[$i..$do], '-d', $dir);
        }
        printf "  %-16s %d plikow\n", $nazwa, scalar @wpisy;
    }

    # luzne pliki moda - te, ktore naprawde leza na dysku i wygrywaja z pakiem
    for my $zrodlo ([ 'hf-luzne' => $HF ], [ 'gra-luzne' => $GAME ]) {
        my ($nazwa, $dir) = @$zrodlo;
        next unless -d $dir;
        my $n = 0;
        find(sub { $n++ if -f && /$ROZSZ/ }, $dir);
        printf "  %-16s %d plikow (czytane w miejscu)\n", $nazwa, $n;
    }

    if (open(my $w, '>', "$CACHE/.gotowe")) { print $w scalar(localtime), "\n"; close $w }
    print "gotowe\n\n";
}

if (@ARGV && $ARGV[0] eq '--odswiez') { buduj(); exit 0 }
my @szukane = @ARGV;
die "uzycie: perl test/kontekst.pl <nazwa> [...]\n       perl test/kontekst.pl --odswiez\n"
    unless @szukane;
buduj() unless -f "$CACHE/.gotowe";

# Korpus jest migawka. Po update gry albo Hortena przestaje odpowiadac temu,
# co silnik naprawde wczytuje - mowimy to wprost zamiast cicho klamac.
{
    my $kiedy = (stat "$CACHE/.gotowe")[9] // 0;
    my @nowsze = grep { -f $_->[1] && (stat $_->[1])[9] > $kiedy } @PAKI;
    if (@nowsze) {
        printf "UWAGA: %d pak(ow) nowszych niz korpus (%s...) - odpal --odswiez\n",
            scalar @nowsze, $nowsze[0][0];
    }
}

# ---------- zbierz pliki ----------
# NASZE PLIKI NIE SA DOWODEM. Luzne nadpisania z paczki patcha i misje
# laboratorium leza w katalogu Hortena; liczenie ich jako "wystapienia w grze"
# to dowodzenie skladni wlasnym kodem - dokladnie to, przed czym ten skrypt
# ma chronic.
my $PATCH = '/c/Users/PC/Documents/goh-hf-patch/resource';
my %nasze;
if (-d $PATCH) {
    find(sub {
        return unless -f;
        (my $rel = $File::Find::name) =~ s{^\Q$PATCH\E/}{};
        $nasze{"$HF/$rel"} = 1;
    }, $PATCH);
}
my @pliki;
my $pominiete = 0;
for my $d ($CACHE, $HF, $GAME) {
    next unless -d $d;
    find(sub {
        return unless -f && /$ROZSZ/;
        my $p = $File::Find::name;
        if ($nasze{$p} || $p =~ m{/hf_lab[^/]*\.mi$}i || $p =~ m{/eksperymenty/}) {
            $pominiete++; return;
        }
        push @pliki, $p;
    }, $d);
}
printf "korpus: %d plikow (pominiete nasze: %d)\n", scalar @pliki, $pominiete;

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

# ---------- szukaj w korpusie ----------
for my $nazwa (@szukane) {
    print "\n", "=" x 68, "\n  $nazwa\n", "=" x 68, "\n";

    my @d = ze_slownika($nazwa);
    print "\n-- slownik z binarki --\n";
    if (@d) {
        printf "  %-30s %-10s %s\n", 'klasa C++', 'kontekst', 'parametry';
        for my $w (@d) {
            printf "  %-30s %-10s %s\n", $w->{klasa}, $w->{kontekst}, $w->{par} || '-';
        }
    } else {
        print "  NIE MA W BINARCE. Jesli nie ma tez nizej - nazwa nie istnieje.\n";
    }

    # rodzaj uzycia: {nazwa ...} klucz, {"nazwa" ...} blok, albo wartosc
    my (%po_rozsz, %przyklad, $razem);
    for my $f (@pliki) {
        open my $h, '<:raw', $f or next;
        local $/; my $t = <$h>; close $h;
        next unless defined $t && index($t, $nazwa) >= 0;
        my ($ext) = $f =~ /\.(\w+)$/; $ext = lc($ext // '?');
        my $n_klucz = () = $t =~ /\{\s*\Q$nazwa\E[\s}]/g;
        my $n_blok  = () = $t =~ /\{\s*"\Q$nazwa\E"/g;
        # Trzecia postac: nazwa jako PARAMETR w srodku bloku, np.
        # {spawn "x" "bone" random_orientation offset 25 0 0}. Bez tego
        # "local_offset" i "no_position" wygladalyby na nieuzywane.
        my $n_wszedzie = () = $t =~ /(?<![\w.])\Q$nazwa\E(?![\w.])/g;
        my $n_par = $n_wszedzie - $n_klucz - $n_blok;
        $n_par = 0 if $n_par < 0;
        next unless $n_klucz || $n_blok || $n_par;
        $po_rozsz{$ext}{klucz} += $n_klucz;
        $po_rozsz{$ext}{blok}  += $n_blok;
        $po_rozsz{$ext}{par}   += $n_par;
        $po_rozsz{$ext}{pliki}++;
        $razem += $n_klucz + $n_blok + $n_par;
        $przyklad{$ext} //= krotko($f);
    }

    print "\n-- wystapienia w prawdziwych plikach --\n";
    if (!$razem) {
        if (@d) {
            print "  ZADNEGO. Silnik zna te nazwe, ale gra jej nigdzie nie uzywa -\n";
            print "  to KANDYDAT, nie potwierdzona skladnia. Sprawdz w laboratorium.\n";
        } else {
            print "  ZADNEGO. Ani w binarce, ani w plikach gry - NIE ISTNIEJE.\n";
            print "  (tak wygladal TravelAltitude przed crashem)\n";
        }
        next;
    }
    my $suma = sub { my $h = shift; ($h->{klucz}//0) + ($h->{blok}//0) + ($h->{par}//0) };
    printf "  %-10s %7s %7s %8s %9s   %s\n",
        'typ', 'plikow', '{nazwa', '{"nazwa', 'parametr', 'przyklad';
    for my $e (sort { $suma->($po_rozsz{$b}) <=> $suma->($po_rozsz{$a}) } keys %po_rozsz) {
        printf "  .%-9s %7d %7d %8d %9d   %s\n", $e, $po_rozsz{$e}{pliki},
            $po_rozsz{$e}{klucz}, $po_rozsz{$e}{blok}, $po_rozsz{$e}{par}, $przyklad{$e};
    }

    print "\n-- werdykt --\n";
    for my $e (sort keys %po_rozsz) {
        my ($k, $b, $p) = @{$po_rozsz{$e}}{qw(klucz blok par)};
        my @jak;
        push @jak, "klucz {$nazwa ...}"   if $k;
        push @jak, "blok {\"$nazwa\" ...}" if $b;
        push @jak, "parametr w srodku bloku" if $p;
        printf "  .%-9s %s\n", $e, join(', ', @jak);
    }
}

sub krotko {
    my $p = shift;
    $p =~ s{^\Q$CACHE\E/}{};
    $p =~ s{^\Q$HF\E/}{HF:};
    $p =~ s{^\Q$GAME\E/}{GRA:};
    $p =~ s{.*/([^/]+/[^/]+)$}{$1} if length($p) > 48;
    $p;
}
