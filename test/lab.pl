#!/usr/bin/perl
# lab.pl - petla laboratorium: edytor misji zamiast konkwisty
#
#   perl test/lab.pl start [--mody <lista>] [-- <opcje edytora>]
#                                                 kontrola + instalacja + mody + znacznik + uruchomienie
#   perl test/lab.pl mody <lista>                 samo ustawienie aktywnych modow (gra zamknieta!)
#   perl test/lab.pl przeladuj                    kontrola + instalacja + nowy znacznik
#   perl test/lab.pl wynik                        co sie stalo od ostatniego znacznika
#   perl test/lab.pl stan                         czy edytor chodzi, kiedy byl znacznik
#   perl test/lab.pl stop                         zamknij edytor (grzecznie, jak krzyzykiem)
#
# LISTA MODOW: nazwy po przecinku, dokladnie takie, jakie widac w game.log
# przy "Mod: activate". Workshop to "mod_<id>", mod lokalny to nazwa katalogu
# w mods/.
#   --mody mod_3359417100             sam Horten
#   --mody mod_3359417100,lab_vfs     Horten + mod lokalny
#   --mody ""                         wszystkie wylaczone
#
# Lista siedzi w profiles/<id>/options.set, w bloku {mods}. Gra zapisuje ten
# plik przy WYJSCIU, wiec ruszamy go tylko przy zamknietej grze - inaczej
# nadpisze nam zmiane swoim stanem. Dlatego "mody" i "start" odmawiaja pracy,
# gdy cokolwiek chodzi.
#
# PODZIAL PRACY
# Asystent poprawia misje i czyta wyniki; czlowiek klika w edytorze. Narzedzie
# nie steruje gra - w tej sesji nie ma czym klikac w okna, a zrzut ekranu
# z PowerShella zablokowal Windows Defender (i dobrze, ze nie obchodzimy go).
#
# Jeden przebieg:
#   asystent: poprawka, potem  lab.pl przeladuj
#   czlowiek: w edytorze  tytul misji -> Reload -> Start;  PrintScreen w ciekawym momencie
#   asystent: lab.pl wynik  -> sondy z logu, crash, zrzuty ekranu od znacznika
#
# Zrzuty robi sama gra (PrintScreen -> screenshots/). Obraz z DirectX zawsze
# wychodzi poprawnie, a moment wybiera ten, kto patrzy.
#
# ZNACZNIK: przeladuj zapisuje rozmiar game.log i czas. wynik czyta tylko to,
# co doszlo potem - inaczej kazdy wynik mieszalby przebiegi. Gdy log jest
# krotszy niz w znaczniku, edytor zostal uruchomiony od nowa i czytamy calosc.

use strict; use warnings;
use FindBin;
use lib $FindBin::Bin;
use sondy;
use POSIX qw(strftime);

my $ROOT   = "$FindBin::Bin/..";
my $STAN   = "$ROOT/data/lab";
my $ZNACZ  = "$STAN/znacznik.txt";
my $WYNIK  = "$STAN/wynik.txt";

my $GRA    = '/c/Program Files (x86)/Steam/steamapps/common/Call to Arms - Gates of Hell';
my $EXE_ED = "$GRA/binaries/x64/call_to_arms_ed.exe";
my $MOJE   = "$ENV{USERPROFILE}/Documents/My Games/gates of hell";
$MOJE =~ s{\\}{/}g; $MOJE =~ s{^([A-Za-z]):}{'/' . lc $1}e;
my $LOG    = "$MOJE/log/game.log";
my $DUMPS  = "$MOJE/log/minidumps";
my $ZRZUTY = "$MOJE/screenshots";

my $PATCH  = '/c/Users/PC/Documents/goh-hf-patch';
my $LABSRC = "$PATCH/eksperymenty/lab";

my ($cmd, @arg) = @ARGV;
$cmd //= 'stan';
mkdir "$ROOT/data" unless -d "$ROOT/data";
mkdir $STAN unless -d $STAN;

# ---------- pomocnicze ----------
sub win { my $p = shift; $p =~ s{^/([a-z])/}{\U$1:\\}; $p =~ s{/}{\\}g; $p }

sub dziala {
    my $obraz = shift;
    # Git Bash zamienia argumenty zaczynajace sie od "/" na sciezki: "/FI" robi
    # sie "C:/Program Files/Git/FI" i tasklist zwraca puste - wszystko wygladalo
    # na wylaczone, nawet dzialajacy Steam. Wylaczamy te konwersje.
    local $ENV{MSYS2_ARG_CONV_EXCL} = '*';
    my $out = `tasklist /FI "IMAGENAME eq $obraz" /NH 2>/dev/null`;
    $out =~ /\Q$obraz\E/i;
}

sub czytaj_znacznik {
    open my $h, '<', $ZNACZ or return;
    my %z = map { chomp; split /=/, $_, 2 } grep { /=/ } <$h>;
    close $h; \%z;
}

sub plik_opcji {
    my $kat = "$MOJE/profiles";
    opendir my $d, $kat or return;
    my @p = grep { -f "$kat/$_/options.set" } grep { !/^\./ } readdir $d;
    closedir $d;
    return unless @p;
    # gdyby profili bylo kilka, bierzemy ostatnio ruszany
    my @s = sort { -M "$kat/$a/options.set" <=> -M "$kat/$b/options.set" } @p;
    "$kat/$s[0]/options.set";
}

# Przepisuje blok {mods} w options.set. Pusta lista = wszystko wylaczone.
sub ustaw_mody {
    my @chciane = @_;
    my $plik = plik_opcji();
    unless ($plik) { print "  mody: nie znalazlem options.set - pomijam\n"; return 1 }

    open my $h, '<:raw', $plik or do { print "  mody: $plik: $!\n"; return 0 };
    my $tresc = do { local $/; <$h> };
    close $h;

    my $eol = $tresc =~ /\r\n/ ? "\r\n" : "\n";
    my ($wciecie) = $tresc =~ /^([ \t]*)\{mods\b/m;
    $wciecie = "\t" unless defined $wciecie;

    my $wpisy = join '', map { "$wciecie\t\"$_:0\"$eol" } @chciane;
    my $blok  = "$wciecie\{mods$eol$wpisy$wciecie\}";

    if ($tresc =~ /^[ \t]*\{mods\b.*?^[ \t]*\}/ms) {
        $tresc =~ s/^[ \t]*\{mods\b.*?^[ \t]*\}/$blok/ms;
    } else {
        # brak bloku - dokladamy przed ostatnia klamra pliku
        $tresc =~ s/(\}\s*)\z/$blok$eol$1/s;
    }

    open my $w, '>:raw', $plik or do { print "  mody: $plik: $!\n"; return 0 };
    print $w $tresc;
    close $w;
    print "  mody: ", (@chciane ? join(', ', @chciane) : 'wszystkie wylaczone'), "\n";
    1;
}

sub kontrola_i_instalacja {
    print "--- kontrola i instalacja misji laboratorium ---\n";
    # zainstaluj.sh wola wspolna kontrole (sprawdz-plik.pl) i nie kopiuje
    # niczego, jesli jest blad
    my $rc = system('bash', "$LABSRC/zainstaluj.sh");
    return 0 if $rc;
    # Nazwy akcji i termow wzgledem slownika - ta sama kontrola co preflight.
    # Misja z nieznana nazwa akcji to w najlepszym razie cisza, w najgorszym crash.
    my $out = `perl "$FindBin::Bin/sprawdz-slownik.pl" "$ROOT/data/slownik/tablice.txt" "$LABSRC" 2>&1`;
    my ($wynik) = $out =~ /^(WYNIK:.*)$/m;
    print "  slownik: ", ($wynik // 'brak wyniku'), "\n";
    if ($?) { print $out; return 0 }
    1;
}

sub postaw_znacznik {
    my $rozm = -f $LOG ? -s $LOG : 0;
    open my $w, '>', $ZNACZ or die "$ZNACZ: $!";
    print $w "czas=", time, "\nlog=$rozm\n";
    close $w;
    printf "--- znacznik: %s, game.log %d B ---\n", strftime('%H:%M:%S', localtime), $rozm;
}

# ---------- komendy ----------
# --mody wyjmujemy z @arg, zanim reszta pojdzie do edytora jako jego opcje
my ($mody_podane, @mody) = (0);
{
    my @reszta;
    while (@arg) {
        my $a = shift @arg;
        if ($a eq '--mody') {
            $mody_podane = 1;
            my $v = shift @arg;
            @mody = grep { length } split /[,\s]+/, (defined $v ? $v : '');
        } else {
            push @reszta, $a;
        }
    }
    @arg = @reszta;
}

if ($cmd eq 'mody') {
    for my $exe ('call_to_arms.exe', 'call_to_arms_ed.exe') {
        next unless dziala($exe);
        print "BLAD: chodzi $exe - zapisze options.set przy wyjsciu i nadpisze zmiane.\n";
        exit 1;
    }
    ustaw_mody($mody_podane ? @mody : grep { length } split /[,\s]+/, join(',', @arg)) or exit 1;
    print ">>> mody ustawione, mozesz uruchamiac\n";
    exit 0;
}

if ($cmd eq 'start') {
    if (dziala('call_to_arms.exe')) {
        print "BLAD: chodzi gra (call_to_arms.exe). Zamknij ja - mody montuja sie przy starcie.\n";
        exit 1;
    }
    if (dziala('call_to_arms_ed.exe')) {
        print "edytor juz chodzi - robie tylko przeladowanie\n";
        $cmd = 'przeladuj';
    } else {
        print "UWAGA: Steam nie dziala - edytor moze nie wystartowac\n" unless dziala('steam.exe');
        kontrola_i_instalacja() or do { print "\n>>> NIE URUCHAMIAM, popraw bledy\n"; exit 1 };
        if ($mody_podane) {
            ustaw_mody(@mody) or do { print "\n>>> NIE URUCHAMIAM, nie udalo sie ustawic modow\n"; exit 1 };
        }
        postaw_znacznik();
        shift @arg if @arg && $arg[0] eq '--';
        my @ps = ('-FilePath', "'" . win($EXE_ED) . "'",
                  '-WorkingDirectory', "'" . win("$GRA/binaries/x64") . "'");
        push @ps, '-ArgumentList', "'" . join(' ', @arg) . "'" if @arg;
        system('powershell.exe', '-NoProfile', '-Command', "Start-Process @ps");
        print "\n>>> edytor uruchomiony", (@arg ? " z opcjami: @arg" : ''), "\n";
        print "  1. opcje modow: Horten wlaczony (i patch, jesli testujesz)",
              ($mody_podane ? " - ustawione przez --mody\n" : "\n");
        print "  2. mapa testing_ground_800x800\n";
        print "  3. tytul misji (gorna linia) -> Load other mission -> hf_lab\n";
        print "  4. Start (prawy dolny rog)\n";
        print "  PrintScreen w ciekawym momencie - zrzut trafi do wyniku\n";
        exit 0;
    }
}

if ($cmd eq 'przeladuj') {
    kontrola_i_instalacja() or do { print "\n>>> NIE PRZELADOWUJ, popraw bledy\n"; exit 1 };
    postaw_znacznik();
    # Po Stop edytor wraca do WLASNEJ kopii misji (editor_last_mission.scn) -
    # bez Reload zmiany z dysku nie wchodza. Reload czyta plik (sprawdzone:
    # "Reloading mission ..." i potem wpisy z /map/.../hf_lab.mi).
    print "\n>>> w edytorze: Stop (jesli chodzi) -> F3 -> tytul misji -> Reload -> START\n";
    print "    START to zielony przycisk w lewym gornym rogu\n";
    print "    (pierwszy raz w sesji: zamiast Reload - Load other mission -> hf_lab)\n";
    exit 0;
}

if ($cmd eq 'wynik') {
    my $z = czytaj_znacznik() or do { print "brak znacznika - najpierw: lab.pl przeladuj\n"; exit 1 };
    my @out;
    my $p = sub { push @out, @_ };
    $p->(sprintf "WYNIK od znacznika %s (%d s temu)\n",
         strftime('%H:%M:%S', localtime $z->{czas}), time - $z->{czas});
    $p->(sprintf "edytor: %s\n", dziala('call_to_arms_ed.exe') ? 'chodzi' : 'NIE CHODZI');

    # --- game.log od znacznika ---
    my @nowe;
    if (-f $LOG) {
        my $rozm = -s $LOG;
        my $od = $z->{log} // 0;
        my $restart = $rozm < $od;
        $od = 0 if $restart;
        open my $h, '<:raw', $LOG or die;
        seek $h, $od, 0; local $/ = "\n"; @nowe = <$h>; close $h;
        $p->(sprintf "\ngame.log: %d nowych wierszy%s, zmieniony %s\n", scalar @nowe,
             ($restart ? ' (log krotszy niz w znaczniku - edytor uruchomiony od nowa, czytam calosc)' : ''),
             strftime('%H:%M:%S', localtime((stat $LOG)[9])));
        $p->("  UWAGA: log nie zmienil sie od znacznika - czy Start na pewno zostal klikniety?\n")
            if (stat $LOG)[9] < $z->{czas};
        my @crash = grep { /\*{5} Exception/ } @nowe;
        $p->("  CRASH w game.log: " . scalar(@crash) . "\n") if @crash;

        # Etapy przebiegu. Pierwszy przebieg pokazal, ze "misja wczytana" i "misja
        # uruchomiona" to dwie rozne rzeczy: Load dawal "ok", a Start nie zostal
        # klikniety - i bez tego rozroznienia wynik wygladal jak cisza sond.
        my ($wczyt) = map { /Loading mission '([^']+)'/ ? $1 : /Reloading mission/ ? 'Reload' : () } @nowe;
        my $start   = grep { /Enter game mode/ } @nowe;
        $p->("  misja wczytana : " . ($wczyt // 'NIE') . "\n");
        $p->("  misja ruszyla  : " . ($start ? 'tak' : 'NIE - kliknij START (zielony, lewy gorny rog)') . "\n");
        # "Local string not found" przy tytule zegara leci przy WCZYTANIU misji,
        # dla wszystkich zegarow naraz (takze z galezi switch, ktore nie moga
        # wykonac sie jednoczesnie). Dowodzi, ze plik dotarl do silnika - nie
        # ze trigger sie wykonal.
        my $tyt = grep { /Local string not found - "hf_/ } @nowe;
        $p->("  tytuly zegarow wczytane: $tyt (to parsowanie, nie wykonanie)\n") if $tyt;

        # Skad edytor wzial misje. Drugi przebieg pokazal pulapke: po Stop edytor
        # przywraca WLASNA kopie (profiles/<id>/editor_last_mission.scn, zapisana
        # przy Start), a nie plik z dysku. Nasze zmiany wtedy w ogole nie wchodza,
        # a wynik wyglada na poprawny - sondy trafiaja, tylko ze starej wersji.
        # Liczy sie OSTATNIE wczytanie w oknie: w jednym przebiegu bywa i kopia
        # (po Stop), i plik (po Reload). Trzeci przebieg pokazal, ze Reload czyta
        # plik z dysku - alarm dla calego okna byl falszywy.
        # I liczy sie wczytanie PRZED ostatnim Startem: po Stop edytor znow
        # przywraca kopie i dopisuje to do logu, wiec "ostatnie w logu" mowi,
        # co jest wczytane teraz, a nie co naprawde chodzilo.
        my ($ost_start) = grep { $nowe[$_] =~ /Enter game mode/ } reverse 0 .. $#nowe;
        my @przed = defined $ost_start ? @nowe[0 .. $ost_start] : @nowe;
        my ($zrodlo) = map { m{\(@/profiles/[^)]*editor_last_mission\.scn} ? 'kopia'
                           : m{\(/map/[^)]*\.mi,}                         ? 'plik' : () } reverse @przed;
        if (($zrodlo // '') eq 'kopia') {
            $p->("  !!! MISJA Z KOPII EDYTORA (editor_last_mission.scn), NIE Z PLIKU\n");
            $p->("      Zmiany NIE weszly. W edytorze: Stop -> F3 -> tytul -> Reload -> START\n");
        } elsif (($zrodlo // '') eq 'plik') {
            $p->("  misja z pliku - zmiany weszly\n");
        }
    } else { $p->("\nbrak game.log\n") }

    # --- crash od znacznika ---
    my @crashlog;
    if (opendir(my $dh, $DUMPS)) {
        my @f = grep { /\.crash\.mdmp\.log$/ && (stat "$DUMPS/$_")[9] >= $z->{czas} } readdir $dh;
        closedir $dh;
        for my $f (sort @f) {
            $p->("\nCRASH od znacznika: " . win("$DUMPS/$f") . "\n");
            open my $h, '<', "$DUMPS/$f" or next; push @crashlog, <$h>; close $h;
        }
    }

    # --- sondy ---
    $p->("\n--- sondy ---\n");
    my $traf = 0;
    for my $zr (['game.log', \@nowe], ['crash', \@crashlog]) {
        my ($skad, $w) = @$zr;
        next unless @$w;
        for my $t (sondy::szukaj($w)) {
            $traf += $t->{ile};
            $p->(sprintf "  [%s] %d x w %s - %s\n", $t->{nazwa}, $t->{ile}, $skad, $t->{znaczy});
            $p->("      $_\n") for @{$t->{kontekst}};
        }
    }
    $p->("  zadna - sondy z HUD (zegar) widac tylko na zrzucie\n") unless $traf;

    # Odczyt liczby przez numer waypointa: 9xxxxx. Zegar okazal sie zlym
    # wyswietlaczem (odlicza w dol, "11" znika po 11 s). Konwencja z hf_lab.mi:
    # 900000+N = gracz N, 909999 = selektor nie zlapal nikogo.
    # Konwencja kodow (pierwsze dwie cyfry = co mierzymy, cztery ostatnie = wartosc):
    #   90NNNN  wlasciciel: gracz N (909999 = selektor nie zlapal nikogo)  - hf_lab.mi
    #   91NNNN  samolot A: N skoczkow na spadochronach                    - hf_lab_zrzut.mi
    #   92NNNN  samolot B: N skoczkow na spadochronach                    - hf_lab_zrzut.mi
    # 999999 to sonda B, nie odczyt - stad jawna lista prefiksow, nie "9xxxxx".
    #   93/94   A/B: ilu ludzi z tagiem po 60 s (kontrolne, bez filtra)
    #   95/96   A/B: ilu ludzi z tagiem po 25 s (w powietrzu)
    my %CO = ('90' => 'wlasciciel: gracz',
              '91' => 'A, 60 s, ze spadochronem (eject_null):',  '92' => 'B, 60 s, ze spadochronem (eject_null):',
              '93' => 'A, 60 s, wszyscy z tagiem:',               '94' => 'B, 60 s, wszyscy z tagiem:',
              '95' => 'A, 25 s, wszyscy z tagiem (w powietrzu):', '96' => 'B, 25 s, wszyscy z tagiem (w powietrzu):');
    # Konkwista (goh-hf-patch/eksperymenty/generuj-wlasciciel.pl):
    #   81 wlasciciel znacznika, 82 id_1st_player$, 83/84 wlasciciel skoczkow przed/po
    %CO = (%CO, '81' => 'znacznik zrzutu nalezy do gracza', '82' => 'id_1st_player$ =',
                '83' => 'skoczkowie PRZED ustawieniem: gracz', '84' => 'skoczkowie PO set+autoassign: gracz');
    # 71-74: samoloty zrzutu 3 s po starcie (sama rezerwa orderow), 75-78: nad celem
    %CO = (%CO, '71' => 'start: samolotow zrzutu wszystkich', '72' => 'start: z nich hidden',
                '73' => 'start: z nich inactive', '74' => 'start: z nich moveable',
                '75' => 'nad celem: samolotow zrzutu wszystkich', '76' => 'nad celem: z nich hidden',
                '77' => 'nad celem: z nich inactive', '78' => 'nad celem: z nich moveable');
    my %kody;
    for (@nowe) { $kody{"$1$2"}++ if /Waypoint (9[0-6]|8[1-4]|7[1-8])(\d{4}) not found/ }
    for my $k (sort keys %kody) {
        my ($pre, $n) = (substr($k, 0, 2), substr($k, 2) + 0);
        my $opis = $n != 9999        ? "$CO{$pre} $n"
                 : $pre eq '82'      ? "$CO{$pre} poza zakresem 0..16"
                 :                     "$CO{$pre} ZADEN - selektor z {player \"N\"} nie zlapal nikogo";
        $p->(sprintf "  ODCZYT: %s  (%d x)\n", $opis, $kody{$k});
    }

    # --- zrzuty ekranu od znacznika ---
    $p->("\n--- zrzuty ekranu (PrintScreen) od znacznika ---\n");
    my @zr;
    if (opendir(my $dh, $ZRZUTY)) {
        @zr = sort grep { /\.(jpg|png|bmp)$/i && (stat "$ZRZUTY/$_")[9] >= $z->{czas} } readdir $dh;
        closedir $dh;
    }
    $p->(@zr ? map { '  ' . win("$ZRZUTY/$_") . "\n" } @zr : "  brak\n");

    print @out;
    if (open my $w, '>', $WYNIK) { print $w @out; close $w }
    exit 0;
}

if ($cmd eq 'stan') {
    my $z = czytaj_znacznik();
    printf "edytor : %s\n", dziala('call_to_arms_ed.exe') ? 'chodzi' : 'nie chodzi';
    printf "gra    : %s\n", dziala('call_to_arms.exe') ? 'CHODZI' : 'nie chodzi';
    printf "steam  : %s\n", dziala('steam.exe') ? 'chodzi' : 'NIE CHODZI';
    printf "znacznik: %s\n", $z ? strftime('%Y-%m-%d %H:%M:%S', localtime $z->{czas}) : 'brak';
    exit 0;
}

if ($cmd eq 'stop') {
    unless (dziala('call_to_arms_ed.exe')) { print "edytor nie chodzi\n"; exit 0 }
    # CloseMainWindow = jak klikniecie krzyzyka: edytor moze zapytac o zapis.
    # Bez zabijania procesu - niezapisana misja przepadlaby bez pytania.
    system('powershell.exe', '-NoProfile', '-Command',
           'Get-Process call_to_arms_ed -ErrorAction SilentlyContinue | ForEach-Object { [void]$_.CloseMainWindow() }');
    print "wyslane zamkniecie okna edytora - jesli pyta o zapis, odpowiedz w oknie\n";
    exit 0;
}

die "nieznana komenda '$cmd'. Komendy: start, przeladuj, wynik, stan, stop\n";
