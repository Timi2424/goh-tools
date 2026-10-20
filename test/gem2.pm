package gem2;
# gem2.pm - parser formatu GEM2 i wyluskiwanie nazw akcji oraz termow.
#
# Wydzielone z sprawdz-slownik.pl, bo preflight.pl potrzebuje dokladnie tej
# samej roboty. Dwie kopie parsera rozjechalyby sie przy pierwszej poprawce,
# a wtedy jedno narzedzie milczy tam, gdzie drugie krzyczy.
#
# Regexem tego sie nie da: {"nazwa"} w .mi to raz akcja triggera, a raz nazwa
# jednostki w rejestrze DLC. Trzeba sparsowac drzewo {} i patrzec na sciezke.
#
# Dwie gramatyki:
#
#   skrypt misji (.mi)         {triggers {"nazwa_triggera"
#                                  {condition {terms {"1.event" ...}}}
#                                  {"fade" {time 3}}          <- akcja, w cudzyslowie
#                                  {trigger_on_next "..."}    <- wlasciwosc, goly token
#                              }}
#
#   skrypt encji (.inc/.set)   {"nazwa_bloku"
#                                  {on spawn
#                                      {link_sound "fall" "..."}   <- akcja, goly token
#                                  }
#                              }

use strict; use warnings;

# ---------- parser ----------
# Komentarz: ';' do konca linii. Token: {, }, "napis", goly ciag.
#
# Komentarze wycinamy bez zjadania '\n', wiec liczba nowych linii przed danym
# offsetem w tekscie obcietym jest ta sama co w oryginale - numery linii zgadzaja
# sie mimo przesunietych offsetow.
#
# Srednik w stringu NIE jest komentarzem - w plikach gry wystepuje " ;".
# Bez tego wyjatku obciety string zostawial niesparowany cudzyslow i tokenizer
# czytal reszte wiersza jak smieci.
sub bez_komentarzy {
    my $t = shift;
    $t =~ s/("(?:[^"\\\n]|\\.)*")|;[^\n]*/defined $1 ? $1 : ''/ge;
    $t;
}

# ---------- kontrola pliku ----------
# JEDYNA kopia tej kontroli. Wczesniej byly trzy (preflight.pl, zbuduj.sh,
# zainstaluj.sh) i rozjechaly sie: blad z tabulatorem zyl w jednej, wycinanie
# komentarzy w dwoch. Skrypty powloki wolaja test/sprawdz-plik.pl.
#
# Zwraca liste problemow: { poziom => 'blad'|'uwaga', linia => N, opis => ... }
# (linia 0 = caly plik).
sub sprawdz_tekst {
    my $raw = shift;
    my @p;
    my $t = bez_komentarzy($raw);

    # Do liczenia nawiasow wycinamy tez TRESC stringow - "{" w napisie to nie blok.
    (my $bez_nap = $t) =~ s/"(?:[^"\\\n]|\\.)*"/""/g;

    my $o = ($bez_nap =~ tr/{//);  my $z = ($bez_nap =~ tr/}//);
    my $po = ($bez_nap =~ tr/(//); my $pz = ($bez_nap =~ tr/)//);
    push @p, { poziom => 'blad', linia => 0, opis => "klamry $o otwierajacych, $z zamykajacych" }
        if $o != $z;
    # Okragle to UWAGA, nie blad - zmierzone, nie zgadniete. Na 16 tys.
    # plikow gry i Hortena klamry nie rozjezdzaja sie ani razu, a okragle
    # w jednym: stockowy set/multiplayer/units/early/units_eng.set ma
    # literowke deweloperow "t()))" w czterech wierszach (2975 "(" na 2980 ")")
    # i gra wczytuje go bez problemu. Twardy blad blokowalby plik, ktory
    # silnik przyjmuje - a nasze zmiany ekonomii dotykaja wlasnie units_*.set.
    push @p, { poziom => 'uwaga', linia => 0,
               opis => "nawiasy okragle $po/$pz (gra toleruje, ale sprawdz, czy to Twoja zmiana)" }
        if $po != $pz;

    # Glebokosc ponizej zera: zamkniecie bez otwarcia. Bilans moze sie zgadzac
    # w sumie, a plik i tak byc zly - stad osobny przebieg po wierszach.
    my ($gl, $ln, $ujemna) = (0, 0, 0);
    for my $w (split /\n/, $bez_nap, -1) {
        $ln++;
        for my $ch ($w =~ /[{}]/g) {
            $gl += $ch eq '{' ? 1 : -1;
            if ($gl < 0 && !$ujemna) {
                push @p, { poziom => 'blad', linia => $ln, opis => 'zamkniecie } bez otwarcia' };
                $ujemna = 1;
            }
        }
    }

    # Sklejka }{"nazwa" bilansuje sie poprawnie i domyka do zera - zadna kontrola
    # glebokosci jej nie zlapie, a parser po cichu polyka caly blok. Szukamy
    # w tekscie bez komentarzy, wiec przyklad w komentarzu nie alarmuje.
    # Perl, nie grep -E: w Git Bash "[ \t]" nie lapie tabulatora.
    $ln = 0;
    for my $w (split /\n/, $t, -1) {
        $ln++;
        push @p, { poziom => 'blad', linia => $ln,
                   opis => 'sklejony wiersz }{"nazwa" - parser polknie ten blok' }
            if $w =~ /\}[ \t]*\{"/;
    }

    # Znaki spoza ASCII poza komentarzami. Polskie litery wyciekly nam juz raz
    # do pliku GEM2. Uwaga, nie blad - nie mamy dowodu, ze psuja parsowanie.
    $ln = 0;
    for my $w (split /\n/, $t, -1) {
        $ln++;
        next unless $w =~ /[^\x00-\x7f]/;
        push @p, { poziom => 'uwaga', linia => $ln, opis => 'znaki spoza ASCII poza komentarzem' };
        last;
    }
    @p;
}

sub parse {
    my $txt = bez_komentarzy(shift);
    my @stack = ({ head => '', q => 0, kids => [] });
    my $root = $stack[0];
    while ($txt =~ /\G(?:\s+|(\{)|(\})|"([^"]*)"|([^\s{}"]+))/gc) {
        if (defined $1) {
            my $n = { head => undef, q => 0, kids => [] };
            push @{$stack[-1]{kids}}, $n;
            push @stack, $n;
        }
        elsif (defined $2) { pop @stack if @stack > 1 }
        else {
            my ($v,$q,$off) = defined $3 ? ($3,1,$-[3]) : ($4,0,$-[4]);
            my $n = $stack[-1];
            if (!defined $n->{head}) { $n->{head} = $v; $n->{q} = $q; $n->{off} = $off }
            else { push @{$n->{kids}}, { head => $v, q => $q, off => $off, kids => [], leaf => 1 } }
        }
    }
    $root;
}

sub kids_named {
    my ($n,$name) = @_;
    grep { !$_->{leaf} && defined $_->{head} && !$_->{q} && $_->{head} eq $name } @{$n->{kids}};
}

sub walk {                      # walk($node, sub { ... })
    my ($n,$cb) = @_;
    $cb->($n);
    walk($_,$cb) for grep { !$_->{leaf} } @{$n->{kids}};
}

sub ident { my $v = shift; defined $v && $v =~ /^[a-z_][a-z0-9_]*$/ }

# Tylko bezposrednie dzieci {on ...} i akcji sterujacych sa akcjami. Glebiej
# siedza juz parametry danej akcji - {health_damage_pierce {effects ...}} to
# parametr, nie akcja, i wrzucanie go do porownania zasmieca wynik.
sub is_container { my $v = shift; $v =~ /^(?:on|if|else|elif|with_\w+|for_each_\w+)$/ }

# ---------- wyluskiwanie nazw ----------
# zwraca { mi => 0/1, ent => 0/1, uzycia => [ {nazwa, rodzaj, off}, ... ] }
# rodzaj: 'akcja_mi' | 'term_mi' | 'akcja_encji'
sub uzycia {
    my $txt = shift;
    my %out = (mi => 0, ent => 0, uzycia => []);
    return \%out unless $txt =~ /\{/;
    my $root = parse($txt);
    my $add = sub { push @{$out{uzycia}}, { nazwa => $_[0], rodzaj => $_[1], off => $_[2] } };

    walk($root, sub {
        my $n = shift;
        for my $trg (kids_named($n,'triggers')) {
            $out{mi} = 1;
            for my $t (@{$trg->{kids}}) {
                next if $t->{leaf};
                for my $acts (kids_named($t,'actions')) {
                    for my $c (@{$acts->{kids}}) {
                        next if $c->{leaf} || !defined $c->{head};
                        my ($nm,$q,$off) = ($c->{head}, $c->{q}, $c->{off});
                        # edytor wylacza akcje, wstawiajac '##' przed nazwa
                        if (!$q && $nm eq '##' && @{$c->{kids}} && $c->{kids}[0]{q}) {
                            ($nm,$q,$off) = ($c->{kids}[0]{head}, 1, $c->{kids}[0]{off});
                        }
                        $add->($nm,'akcja_mi',$off) if $q && ident($nm);
                    }
                }
                # termy warunku
                for my $cond (kids_named($t,'condition')) {
                    for my $terms (kids_named($cond,'terms')) {
                        for my $tm (@{$terms->{kids}}) {
                            next if $tm->{leaf} || !defined $tm->{head};
                            $add->($1,'term_mi',$tm->{off})
                                if $tm->{head} =~ /^\d+\.([a-z_][a-z0-9_]*)$/;
                        }
                    }
                }
            }
        }
    });

    # skrypt encji: {"blok" {on ... {akcja ...}}}
    my $zbierz;
    $zbierz = sub {
        my $n = shift;
        for my $k (@{$n->{kids}}) {
            next if $k->{leaf} || $k->{q} || !ident($k->{head});
            $add->($k->{head},'akcja_encji',$k->{off});
            $zbierz->($k) if is_container($k->{head});
        }
    };
    for my $blk (@{$root->{kids}}) {
        next if $blk->{leaf} || !$blk->{q};
        for my $on (kids_named($blk,'on')) {
            $out{ent} = 1;
            $zbierz->($on);
        }
    }
    \%out;
}

# Offset -> numer linii. Tablica nowych linii liczona raz na plik, bo liczenie
# od poczatku przy kazdym trafieniu zabija przebieg po calym korpusie.
sub indeks_linii {
    # offsety z parse() licza sie w tekscie po wycieciu komentarzy, wiec indeks
    # musi powstac z tego samego tekstu - inaczej numery linii uciekaja
    my $txt = bez_komentarzy(shift);
    my @nl;
    while ($txt =~ /\n/g) { push @nl, $-[0] }
    \@nl;
}
sub linia {
    my ($nl,$off) = @_;
    return 0 unless defined $off;
    my ($lo,$hi) = (0, scalar @$nl);
    while ($lo < $hi) {
        my $mid = int(($lo+$hi)/2);
        if ($nl->[$mid] < $off) { $lo = $mid+1 } else { $hi = $mid }
    }
    $lo + 1;
}

# ---------- slownik z binarki ----------
# Plaski zbior wszystkich nazw z tablice.txt klamie: 18 tablic ma w naglowku '?'
# i to nie jest GEM2, tylko biblioteka standardowa Lua (0x0115xxxx - io, os,
# string, bit32) i parser XML Xerces (0x014aexxx). Przykryly nieistniejacy term
# "1.time" nazwa os.time i kontrola go przepuszczala.
#
# Dlatego kazda gramatyka dostaje swoj rejestr. One naprawde sa rozlaczne, wiec
# zawezenie lapie nie tylko nazwy z obcych bibliotek, ale i akcje wpisana w
# miejsce termu.
#
# Rejestr rozpoznajemy po dwoch sygnalach: klasie C++ i module. Klasa jest tym,
# co silnik naprawde instancjonuje, a tablica moze stac w dowolnym module. Tak
# wchodza rail_switch i rail_break: siedza w eEntityRailway.cpp, ale sa
# Interaction::eSwitchRail / eBreakRail, czyli tym samym rodzajem akcji co cale
# eIA_*, i stoja w stockowym railway.inc. Z tej samej tablicy NIE wchodzi
# railway (DDA::eServer) - i o to chodzi.
#
# Liczy sie suma obu kryteriow, nie samo ostrzejsze. Sama klasa wycielaby
# 'if', 'actor_state' i pare rozkazow, ktore stoja w tablicach helperow z klasa
# spoza rodziny albo bez rozpoznanej klasy ('-') - a to sa prawdziwe akcje
# triggerow. Falszywy alarm na poprawnym pliku kosztuje wiecej niz przepuszczona
# nazwa: wylaczona kontrola nie lapie juz niczego.
our %REJESTRY = (
    term_mi => {
        klasa => qr/^Helper::eTerm_/,
        modul => qr/^(?:eHelperConditionTerm\.cpp|eHelperWaypointSelector\.h)$/,
    },
    akcja_mi => {
        klasa => qr/^Helper::(?!eTerm_)/,
        modul => qr/^(?:eHelperCommand\w*\.cpp|eHelperThreadStatement\.cpp)$/,
    },
    akcja_encji => {
        klasa => qr/^Interaction::/,
        modul => qr/^eIA_\w+\.cpp$/,
    },
);

# format: '=== 0x... <modul.cpp> wpisow: N', potem wpisy wciete dwiema spacjami:
# nazwa, klasa C++ (albo '-'), reszta to przyjmowane parametry
sub wczytaj_slownik {
    my $plik = shift;
    open my $d, '<', $plik or return undef;
    my %wpisy;                          # nazwa => [ {modul, klasa}, ... ]
    my $mod = '?';
    while (<$d>) {
        if (/^=== 0x\w+\s+(\S+)/) { $mod = $1; next }
        # klasa bywa nierozpoznana ('-'); wpis bez drugiej kolumny tez ma wejsc,
        # bo pominiety wpis to falszywy alarm na poprawnej nazwie
        next unless /^  (\S+)(?:\s+(\S+))?/;
        push @{$wpisy{$1}}, { modul => $mod, klasa => defined $2 ? $2 : '-' };
    }
    close $d;
    \%wpisy;
}

# Nazwy dopuszczalne dla danej gramatyki. Nazwa stoi w kilku tablicach naraz,
# wiec wystarczy, ze jedno wystapienie pasuje do rejestru.
sub zestaw {
    my ($wpisy, $rodzaj) = @_;
    my $r = $REJESTRY{$rodzaj} or die "gem2: nieznany rodzaj '$rodzaj'\n";
    my %ok;
    for my $nazwa (keys %$wpisy) {
        for my $w (@{$wpisy->{$nazwa}}) {
            next unless $w->{klasa} =~ $r->{klasa} || $w->{modul} =~ $r->{modul};
            $ok{$nazwa} = 1;
            last;
        }
    }
    \%ok;
}

# Wszystkie trzy rejestry naraz - do licznikow i komunikatow.
sub zestaw_gem2 {
    my $wpisy = shift;
    my %ok;
    for my $r (keys %REJESTRY) {
        my $z = zestaw($wpisy, $r);
        $ok{$_} = 1 for keys %$z;
    }
    \%ok;
}

1;
