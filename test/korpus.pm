package korpus;
# korpus.pm - pliki tekstowe gry wyciagniete z pakow i indeks nazw w nich.
#
# Odpowiada na pytanie, ktorego slownik z binarki nie rozstrzyga: czy nazwa
# wystepuje w PRAWDZIWYM pliku gry, w jakim typie pliku i w jakiej postaci.
# Jedynym pewnym dowodem na dopuszczalnosc jest wystapienie w pliku tego
# samego typu.
#
# Wspolne dla kontekst.pl, sprawdz-klucze.pl i preflight.pl - zeby nie
# powtorzyc historii z trzema kopiami kontroli nawiasow (#16).
#
# CO JEST DOWODEM, A CO NIE
#   - pliki z pakow gry i Hortena - tak
#   - mapy testowe Hortena (map/testing_ground*) - tak, poza naszymi hf_lab*
#   - KAZDY INNY luzny plik w katalogu moda - NIE. Tam laduja nasze
#     nadpisania z paczki i eksperymenty kopiowane do gry. Plik z
#     TravelAltitude lezal wlasnie tak - zaindeksowany, sam by siebie
#     "potwierdzil".
#   - tresc komentarzy - NIE. ";{TravelAltitude 1}" to nie uzycie.

use strict; use warnings;
use File::Find;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname(abs_path(__FILE__));
use gem2;

our $ROOT   = abs_path(dirname(abs_path(__FILE__)) . '/..');
our $CACHE  = "$ROOT/data/korpus";
our $INDEKS = "$CACHE/indeks.tsv";

our $GAME = '/c/Program Files (x86)/Steam/steamapps/common/Call to Arms - Gates of Hell/resource';
our $HF   = '/c/Program Files (x86)/Steam/steamapps/workshop/content/400750/3359417100/resource';

# Tylko paki z tekstem. Reszta to tekstury, dzwiek i wideo - 90 GB, zero skladni.
our @PAKI = (
    [ 'gra-gamelogic'  => "$GAME/gamelogic.pak"        ],
    [ 'gra-properties' => "$GAME/properties.pak"       ],
    [ 'gra-multi'      => "$GAME/map/multi.pak"        ],
    [ 'gra-single'     => "$GAME/map/single.pak"       ],
    [ 'gra-vehicle'    => "$GAME/entity/-vehicle.pak"  ],
    [ 'gra-entity'     => "$GAME/entity/entity.pak"    ],
    [ 'gra-inventory'  => "$GAME/entity/inventory.pak" ],
    # DLC maja wlasna skladnie: 241 plikow tekstowych lacznie (#18).
    [ 'gra-dlc1'       => "$GAME/dlc1.pak"             ],
    [ 'gra-dlc2'       => "$GAME/dlc2.pak"             ],
    [ 'gra-dlc3'       => "$GAME/dlc3.pak"             ],
    [ 'gra-dlc4'       => "$GAME/dlc4.pak"             ],
    [ 'gra-dlc5'       => "$GAME/dlc5.pak"             ],
    [ 'gra-dlc7'       => "$GAME/_dlc7.pak"            ],
    [ 'hf-gamelogic'   => "$HF/gamelogic.pak"          ],
    [ 'hf-properties'  => "$HF/properties.pak"         ],
    [ 'hf-multi'       => "$HF/map/multi.pak"          ],
    [ 'hf-vehicle'     => "$HF/entity/-vehicle.pak"    ],
    [ 'hf-entity'      => "$HF/entity/entity.pak"      ],
);
our $ROZSZ = qr/\.(def|ext|inc|set|mi|pattern|reg)$/i;

# ---------- tokeny ----------
# Kazda nazwa w pliku w jednej z trzech postaci:
#   k  klucz      {nazwa ...}
#   b  blok       {"nazwa" ...}
#   p  parametr   golego slowa w srodku bloku: {spawn "x" "kosc" random_orientation}
# Napisy, ktore nie otwieraja bloku ("mp/ger/pilot"), to wartosci - pomijane.
# Komentarze wyciete wczesniej, numery wierszy zachowane.
sub tokeny {
    my $t = gem2::bez_komentarzy(shift);
    my @out;
    my ($po_klamrze, $ln) = (0, 1);
    while ($t =~ /\G(?:(\s+)|(\{)|(\})|"([^"\n]*)"|([^\s{}"]+)|(.))/gcs) {
        # Kopia PRZED kolejnym dopasowaniem: regex w warunku nizej nadpisalby
        # $4 i $5, zanim trafia do tablicy.
        my ($ws, $ot, $za, $nap, $slowo) = ($1, $2, $3, $4, $5);
        if    (defined $ws) { $ln += ($ws =~ tr/\n//); next }
        elsif (defined $ot) { $po_klamrze = 1; next }
        elsif (defined $za) { $po_klamrze = 0; next }
        elsif (defined $nap) {
            push @out, [ $nap, 'b', $ln ] if $po_klamrze && $nap =~ m{^[A-Za-z_][\w.\-/]*$};
        }
        elsif (defined $slowo) {
            push @out, [ $slowo, ($po_klamrze ? 'k' : 'p'), $ln ] if $slowo =~ /^[A-Za-z_][\w.]*$/;
        }
        $po_klamrze = 0;
    }
    @out;
}

# ---------- ktore pliki sa dowodem ----------
sub pliki_dowodowe {
    my @p;
    find(sub { push @p, $File::Find::name if -f && /$ROZSZ/ }, $CACHE) if -d $CACHE;
    for my $tg (glob "'$HF/map/testing_ground*'") {
        next unless -d $tg;
        find(sub {
            return unless -f && /$ROZSZ/;
            return if /^hf_lab/i;           # nasze misje laboratorium
            push @p, $File::Find::name;
        }, $tg);
    }
    @p;
}

# ---------- budowa ----------
# unzip w tym Gicie NIE przepuszcza '*' przez '/', wiec wzorce typu '*.inc'
# nie dzialaja. Listujemy katalog centralny (szybkie, nie czyta danych)
# i wyciagamy pliki po nazwie, partiami.
sub buduj {
    print "buduje korpus w $CACHE\n";
    mkdir "$ROOT/data" unless -d "$ROOT/data";
    mkdir $CACHE       unless -d $CACHE;
    my $poprz = (stat "$CACHE/.gotowe")[9] // 0;
    my $zmiany = 0;

    for my $p (@PAKI) {
        my ($nazwa, $pak) = @$p;
        unless (-f $pak) { printf "  %-16s brak paka, pomijam\n", $nazwa; next }
        my $dir = "$CACHE/$nazwa";

        # Przyrostowo: pak niezmieniony od ostatniej budowy i juz rozpakowany
        # = nic do roboty. Pelna budowa trwa ~2 min, glownie przez -vehicle.pak.
        if (-d $dir && $poprz && (stat $pak)[9] <= $poprz) {
            printf "  %-16s bez zmian\n", $nazwa; next;
        }
        if (-d $dir) {      # pak sie zmienil - stare pliki mogly zniknac
            require File::Path;
            File::Path::remove_tree($dir);
        }
        $zmiany++;

        my @wpisy;
        open my $l, '-|', 'unzip', '-l', $pak or do { print "  $nazwa: unzip padl\n"; next };
        while (<$l>) {
            next unless /^\s*\d+\s+\S+\s+\S+\s+(\S.*)$/;
            my $n = $1; $n =~ s/\s+$//;
            next unless $n =~ $ROZSZ;
            # unzip traktuje wzorce jak globy - nazwy z [ ] * ? trzeba eskejpowac,
            # inaczej "U.S. - [USN]/..." cicho wypada z korpusu.
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

    if ($zmiany || !-f $INDEKS) { buduj_indeks() }
    else                        { print "  indeks           bez zmian\n" }

    if (open(my $w, '>', "$CACHE/.gotowe")) { print $w scalar(localtime), "\n"; close $w }
    print "gotowe\n\n";
}

# Indeks: nazwa -> rozszerzenie -> liczniki k/b/p, liczba plikow, przyklad.
# Bez niego kazde zapytanie skanowalo ~25 tys. plikow (~15 s), a preflight
# nie moglby sprawdzac kluczy przy kazdym uruchomieniu.
sub buduj_indeks {
    my @pliki = pliki_dowodowe();
    printf "  indeks           %d plikow...", scalar @pliki;
    my %ix;
    for my $f (@pliki) {
        open my $h, '<:raw', $f or next;
        local $/; my $txt = <$h>; close $h;
        next unless defined $txt;
        my ($ext) = $f =~ /\.(\w+)$/; $ext = lc $ext;
        my %w_pliku;
        for my $tk (tokeny($txt)) {
            my ($n, $r) = @$tk;
            my $e = $ix{$n}{$ext} //= { k => 0, b => 0, p => 0, pliki => 0, ex => krotko($f) };
            $e->{$r}++;
            $w_pliku{$n} = 1;
        }
        $ix{$_}{$ext}{pliki}++ for keys %w_pliku;
    }
    open my $w, '>', "$INDEKS.tmp" or die "$INDEKS: $!";
    print $w "# nazwa\trozsz\tklucz\tblok\tparametr\tplikow\tprzyklad\n";
    for my $n (sort keys %ix) {
        for my $e (sort keys %{$ix{$n}}) {
            my $x = $ix{$n}{$e};
            print $w join("\t", $n, $e, @$x{qw(k b p pliki ex)}), "\n";
        }
    }
    close $w;
    rename "$INDEKS.tmp", $INDEKS or die "rename $INDEKS: $!";
    printf " %d nazw\n", scalar keys %ix;
}

# Wczytuje z indeksu tylko podane nazwy (albo wszystkie, gdy lista pusta).
# Zwraca { nazwa => { rozsz => {k,b,p,pliki,ex} } }.
sub wczytaj_indeks {
    my %chce = map { $_ => 1 } @_;
    my %lc_chce = map { lc($_) => 1 } @_;
    my (%ix, %lc);
    # Wywolujacy czesto robi "local $/" (caly plik naraz) i to przecieka tutaj:
    # indeks czytal sie wtedy jako JEDEN wiersz, a kazdy klucz wychodzil jako
    # "nigdzie w grze". Funkcja modulu nie moze zalezec od globali wywolujacego.
    local $/ = "\n";
    open my $h, '<', $INDEKS or return;
    while (my $l = <$h>) {
        next if $l =~ /^#/;
        my $tab = index($l, "\t");
        my $n = substr($l, 0, $tab);
        my $dokladnie = !%chce || $chce{$n};
        my $wielkosc  = %chce && !$chce{$n} && $lc_chce{lc $n};
        next unless $dokladnie || $wielkosc;
        chomp $l;
        my (undef, $e, $k, $b, $p, $pl, $ex) = split /\t/, $l;
        my $rek = { k => $k, b => $b, p => $p, pliki => $pl, ex => $ex };
        if ($dokladnie) { $ix{$n}{$e} = $rek }
        else            { push @{$lc{lc $n}}, [ $n, $e, $rek ] }
    }
    close $h;
    # Druga wartosc: te same nazwy inna wielkoscia liter. Nie wiemy, czy silnik
    # rozroznia wielkosc liter w kluczach - wiec to podpowiedz, nie dowod.
    wantarray ? (\%ix, \%lc) : \%ix;
}

sub jest_indeks { -f $INDEKS }

# ---------- klucze plikow danych ----------
# Klasa bledu TravelAltitude: klucz {nazwa ...} w .ext / .def, ktorego gra
# nigdzie nie uzywa jako klucza pliku danych. Slownik tego nie lapie, bo
# tablice w .rdata mieszaja API skryptowe z kluczami plikow (#19).
#
# .ext i .def traktujemy jak jedna rodzine: .def dolacza .ext przez include,
# a ten sam blok {Chassis ...} stoi w obu.
our %RODZINA = (ext => [qw(ext def)], def => [qw(def ext)]);

# Zwraca liste problemow dla jednego pliku:
#   { linia, nazwa, poziom => 'brak'|'gdzie_indziej'|'wielkosc', opis }
#   brak          - nazwy nie ma NIGDZIE w grze. Tak wygladal TravelAltitude.
#   gdzie_indziej - jest w grze, ale nie jako klucz pliku tego typu
#   wielkosc      - jest jako klucz, tylko inna wielkoscia liter
sub sprawdz_klucze {
    my ($txt, $ext) = @_;
    my $rodz = $RODZINA{lc $ext} or return;
    my @kl = grep { $_->[1] eq 'k' } tokeny($txt);
    return unless @kl;
    my %nazwy = map { $_->[0] => 1 } @kl;
    my ($ix, $lc) = wczytaj_indeks(keys %nazwy);

    my (@p, %bylo);
    for my $tk (@kl) {
        my ($n, undef, $ln) = @$tk;
        next if $bylo{$n}++;                    # kazda nazwa raz, z pierwszym wierszem
        my $po = $ix->{$n} || {};
        next if grep { $po->{$_} && $po->{$_}{k} } @$rodz;   # OK: klucz w .ext/.def

        if (my $inne = $lc->{lc $n}) {
            # ta sama nazwa inna wielkoscia liter, stojaca jako klucz w .ext/.def
            my %rodz = map { $_ => 1 } @$rodz;
            my %kl_inne;
            for my $w (@$inne) {
                my ($nazwa_gry, $e, $rek) = @$w;
                $kl_inne{$nazwa_gry} = 1 if $rodz{$e} && $rek->{k};
            }
            my @kl_inne = sort keys %kl_inne;
            if (@kl_inne) {
                push @p, { linia => $ln, nazwa => $n, poziom => 'wielkosc',
                           opis => 'w grze jako klucz tylko inna wielkoscia liter: ' . join(', ', @kl_inne) };
                next;
            }
        }
        if (%$po) {
            my @gdzie = map {
                my $x = $po->{$_};
                my @j; push @j, 'klucz' if $x->{k}; push @j, 'blok' if $x->{b}; push @j, 'parametr' if $x->{p};
                ".$_ (" . join('/', @j) . ")";
            } sort keys %$po;
            push @p, { linia => $ln, nazwa => $n, poziom => 'gdzie_indziej',
                       opis => 'nie jako klucz .ext/.def - w grze tylko: ' . join(', ', @gdzie) };
        } else {
            push @p, { linia => $ln, nazwa => $n, poziom => 'brak',
                       opis => 'NIGDZIE w plikach gry - tak wygladal TravelAltitude przed crashem' };
        }
    }
    @p;
}

# Paki nowsze niz korpus - korpus jest migawka i po update przestaje
# odpowiadac temu, co silnik naprawde wczytuje.
sub nieaktualne_paki {
    my $kiedy = (stat "$CACHE/.gotowe")[9] // 0;
    map { $_->[0] } grep { -f $_->[1] && (stat $_->[1])[9] > $kiedy } @PAKI;
}

sub krotko {
    my $p = shift;
    $p =~ s{^\Q$CACHE\E/}{};
    $p =~ s{^\Q$HF\E/}{HF:};
    $p =~ s{^\Q$GAME\E/}{GRA:};
    $p =~ s{.*/([^/]+/[^/]+)$}{$1} if length($p) > 48;
    $p;
}

1;
