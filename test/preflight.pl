#!/usr/bin/perl
# preflight.pl - kontrola plikow moda PRZED odpaleniem gry
#
#   perl test/preflight.pl
#
# Lapie bledy, ktore inaczej konczyly sie crashem albo stracona bitwa:
#   - niezbilansowane nawiasy
#   - niepodstawione parametry makr  (%crew8 -> crash 19.10)
#   - {spawn "X"} bez istniejacej encji X  (-> crash, can't spawn -> null)
#   - zla liczba crewN wzgledem squad_vehicleN
#   - zmieniony rodzaj koncow linii wzgledem oryginalu z paka
#   - pliki w modzie, ktorych nie ma w paczce produkcyjnej
#   - nazwa akcji albo termu, ktorej silnik nie zna (-> cisza albo crash)

use strict; use warnings;
use FindBin;
use lib $FindBin::Bin;
use gem2;

my $MOD  = 'C:/Program Files (x86)/Steam/steamapps/workshop/content/400750/3359417100';
my $GAME = 'C:/Program Files (x86)/Steam/steamapps/common/Call to Arms - Gates of Hell';
my $PKG  = 'C:/Users/PC/Documents/HF_PATCH_PODMIANA/resource';
my $DICT = "$FindBin::Bin/../data/slownik/tablice.txt";

my ($err, $warn) = (0, 0);
sub bad  { print "  BLAD  $_[0]\n";  $err++ }
sub warn_{ print "  uwaga $_[0]\n"; $warn++ }
sub ok   { print "  ok    $_[0]\n" }

# ---------- zbierz luzne pliki moda ----------
my @loose;
sub walk { my $d = shift;
    opendir(my $h, $d) or return;
    for my $e (grep { !/^\.\.?$/ } readdir $h) {
        my $p = "$d/$e";
        if (-d $p) { walk($p) } elsif ($p !~ /\.pak$/i) { push @loose, $p }
    }
    closedir $h;
}
walk("$MOD/resource");
my @mine = grep { !m{/(interface/splash|map/testing_ground|message\.txt)} } @loose;

print "=== pliki luzne w modzie: ", scalar @loose, " (nasze: ", scalar @mine, ") ===\n\n";

# ---------- 1. nawiasy i sklejone wiersze ----------
# Komentarze wycinamy PRZED liczeniem: pliki GEM2 zawieraja wiersze w rodzaju
# ";//{state", czyli komentarz z niesparowanym nawiasem. Silnik je pomija,
# wiec liczenie surowego tekstu dawaloby falszywy alarm.
print "--- nawiasy ---\n";
my $sklejki = 0;
for my $f (@mine) {
    next unless $f =~ /\.(inc|set|reg|ext|pattern|def|mi)$/i;
    open(my $h,'<:raw',$f) or next; local $/; my $raw = <$h>; close $h;
    my $c = $raw;
    $c =~ s{;/\*.*?\*/}{}gs;      # komentarz blokowy
    $c =~ s{;//[^\n]*}{}g;        # komentarz do konca wiersza
    my $o = ($c =~ tr/{//); my $z = ($c =~ tr/}//);
    my $p = ($c =~ tr/(//); my $q = ($c =~ tr/)//);
    my $n = short($f);
    if ($o != $z) { bad "$n  klamry $o/$z" }
    elsif ($p != $q) { bad "$n  nawiasy okragle $p/$q" }

    # Sklejka }{"nazwa" BILANSUJE SIE POPRAWNIE i domyka do zera, wiec zadna
    # kontrola glebokosci jej nie zlapie - a parser po cichu polyka caly blok.
    # Zero bledow w logu, zero efektu w grze. Kosztowalo piec przebiegow.
    my $ln = 0;
    for my $line (split /\n/, $c) {
        $ln++;
        next unless $line =~ /\}[ \t]*\{"/;
        bad "$n:$ln  sklejony wiersz }{\"nazwa\" - parser polknie ten blok";
        $sklejki++;
    }
}
ok "wszystkie zbilansowane, brak sklejek" unless $err;

# ---------- 2. niepodstawione makra ----------
print "\n--- niepodstawione parametry makr ---\n";
my $m = 0;
for my $f (@mine) {
    next unless $f =~ /units.*\.set$/i;
    open(my $h,'<',$f) or next;
    while (my $l = <$h>) {
        next unless $l =~ /\{content|crew\d|%\w+/;
        while ($l =~ /(%(?:crew|side|period|vehicle|min_stage|max_stage|cw|cp)\d*)/g) {
            bad short($f) . "  niepodstawione $1"; $m++;
        }
    }
    close $h;
}
ok "brak" unless $m;

# ---------- 3. arnosc makr squad_vehicleN ----------
print "\n--- liczba crewN vs squad_vehicleN ---\n";
my $a = 0;
for my $f (@mine) {
    next unless $f =~ /units.*\.set$/i;
    open(my $h,'<',$f) or next;
    while (my $l = <$h>) {
        next unless $l =~ /"squad_vehicle(\d+)"/;
        my $need = $1;
        my $have = () = $l =~ /crew\d+\(/g;
        if ($have < $need) { bad short($f) . "  squad_vehicle$need ma tylko $have zalog (wymaga $need) - niepodstawiony %crew = CRASH"; $a++ }
    }
    close $h;
}
ok "zgodne" unless $a;

# ---------- 4. {spawn "X"} -> czy encja X istnieje ----------
print "\n--- encje wolane przez spawn ---\n";
my %known;
my @paks;
 for my $dir ("$GAME/resource/entity", "$MOD/resource/entity") {
   opendir(my $dh, $dir) or next;
   push @paks, map { "$dir/$_" } grep { /.pak$/ } readdir $dh;
   closedir $dh;
 }
 for my $pak (@paks) {
    next unless -f $pak;
    for (`unzip -l "$pak" 2>/dev/null`) {
        $known{$1} = 1 if m{([A-Za-z0-9_]+)\.def\s*$};
        $known{$1} = 1 if m{/([A-Za-z0-9_]+)/\s*$};
    }
}
for my $d (glob "$MOD/resource/entity/service/damage/artillery_barrage/*.def") {
    $known{$1} = 1 if $d =~ m{([A-Za-z0-9_]+)\.def$};
}
my $s = 0;
for my $f (@mine) {
    next unless $f =~ /\.inc$/i;
    open(my $h,'<',$f) or next;
    while (my $l = <$h>) {
        while ($l =~ /\{spawn\s+"([^"]+)"/g) {
            my $e = $1;
            next if $e =~ m{^mp/};                       # breedy - osobna sprawa
            next if $e =~ /^%/;                          # parametr makra
            next if $known{$e};
            warn_ short($f) . "  spawn \"$e\" - nie widze encji .def (indeks moze byc niepelny - SPRAWDZ RECZNIE, brak encji = crash)"; $s++;
        }
    }
    close $h;
}
ok "wszystkie maja encje" unless $s;

# ---------- 5. nazwy akcji i termow vs slownik z binarki ----------
# Silnik nie sprawdza, czy nazwa akcji albo termu istnieje: literowka konczy sie
# cisza, wpisem w logu albo dereferencja nulla. Slownik z pe/slownik.pl to jedyne
# miejsce, gdzie te nazwy sa wypisane - konfrontacja z nim lapie to przed bitwa.
#
# Kazda gramatyka idzie przeciw swojemu rejestrowi, nie przeciw calemu plikowi.
# Plaski zbior przepuszczal nieistniejacy term "1.time", bo tablice Lua w
# tym samym zrzucie maja os.time - szczegoly w gem2::%REJESTRY.
print "\n--- nazwy akcji i termow vs slownik z binarki ---\n";
my $mod_of = gem2::wczytaj_slownik($DICT);
if (!$mod_of) {
    warn_ "brak slownika (zbuduj: perl pe/slownik.pl) - pomijam kontrole nazw";
} else {
    my %zest = map { $_ => gem2::zestaw($mod_of, $_) } keys %gem2::REJESTRY;
    my $z = 0;
    for my $f (@mine) {
        next unless $f =~ /\.(mi|inc|set)$/i;
        open(my $h,'<:raw',$f) or next;
        my $txt = do { local $/; <$h> };
        close $h;
        my $u = gem2::uzycia($txt);
        my $nl;
        for my $uz (@{$u->{uzycia}}) {
            next if $zest{$uz->{rodzaj}}{$uz->{nazwa}};
            # indeks linii budujemy dopiero przy pierwszym trafieniu - na czystym
            # pliku nie ma za co placic
            $nl ||= gem2::indeks_linii($txt);
            my $co = $uz->{rodzaj} eq 'term_mi' ? 'term warunku' : 'akcja';
            bad short($f) . ':' . gem2::linia($nl, $uz->{off})
                . "  $co \"$uz->{nazwa}\" - silnik nie zna takiej nazwy";
            $z++;
        }
    }
    ok sprintf("wszystkie nazwy sa w rejestrach silnika (%d znanych)",
               scalar keys %{ gem2::zestaw_gem2($mod_of) }) unless $z;
}

# ---------- 6. konce linii vs oryginal z paka ----------
print "\n--- konce linii vs wersja z paka ---\n";
my $c = 0;
for my $f (@mine) {
    my $rel = $f; $rel =~ s{^\Q$MOD\E/resource/}{};
    next unless $rel =~ /\.(inc|set)$/i;
    my $ent = $rel; $ent =~ s{^map/}{};
    my $orig = `unzip -p "$MOD/resource/gamelogic.pak" "$rel" 2>/dev/null` ||
               `unzip -p "$MOD/resource/map/multi.pak" "$ent" 2>/dev/null`;
    next unless length $orig;
    my $o_crlf = $orig =~ /\r\n/ ? 1 : 0;
    open(my $h,'<:raw',$f) or next; local $/; my $cur = <$h>; close $h;
    my $c_crlf = $cur =~ /\r\n/ ? 1 : 0;
    if ($o_crlf != $c_crlf) {
        warn_ short($f) . "  moze rozne konce linii (porownanie przez shell bywa zawodne - sprawdz: file <plik>)"; $c++;
    }
}
ok "zgodne" unless $c;

# ---------- 7. mod vs paczka produkcyjna ----------
print "\n--- mod vs paczka produkcyjna ---\n";
if (-d $PKG) {
    my @pkg; walk_pkg($PKG, '', \@pkg);
    my %inpkg = map { $_ => 1 } @pkg;
    my @extra;
    for my $f (@mine) {
        my $rel = $f; $rel =~ s{^\Q$MOD\E/resource/}{};
        push @extra, $rel unless $inpkg{$rel};
    }
    if (@extra) {
        warn_ "pliki poza paczka (eksperymenty): " . scalar @extra;
        print "          $_\n" for @extra;
    } else { ok "mod == paczka, zero eksperymentow" }
    for my $rel (@pkg) {
        my $a = "$PKG/$rel"; my $b = "$MOD/resource/$rel";
        if (!-f $b) {
            # Pliki pod map/ nie dzialaja luzno - wpis dolaczany z wnetrza paka
            # jest szukany w tym samym paku. Takie trzymamy we wlasnym zz_*.pak.
            if ($rel =~ m{^map/} && in_own_pak($rel)) {
                ok short($rel) . "  w zz_multi.pak (luzno nie dziala pod map/)";
            } else { bad "brak w modzie: $rel" }
        }
        elsif (slurp($a) ne slurp($b)) { warn_ "rozni sie od paczki: $rel" }
    }
} else { warn_ "nie znalazlem paczki $PKG" }

# Czy sciezka siedzi w ktoryms z naszych wlasnych pakow w resource/map/.
# Nasze to te, ktorych nie ma w oryginalnym modzie - u nas prefiks zz_.
sub in_own_pak {
    my $rel = shift;
    (my $inner = $rel) =~ s{^map/}{};
    for my $p (glob "'$MOD/resource/map/zz_*.pak'") {
        my @e = `unzip -Z1 "$p" 2>/dev/null`;
        chomp @e;
        return 1 if grep { $_ eq $inner } @e;
    }
    return 0;
}

# ---------- 8. czy gra chodzi ----------
print "\n--- proces gry ---\n";
my $run = `tasklist /FI "IMAGENAME eq call_to_arms.exe" 2>/dev/null`;
if ($run =~ /call_to_arms\.exe/) { warn_ "GRA CHODZI - zmiany nie zostana wczytane, mody montuja sie na starcie" }
else { ok "gra zamknieta, mozna odpalac" }

print "\n", "=" x 52, "\n";
printf "bledy: %d    uwagi: %d\n", $err, $warn;
print $err ? ">>> NIE ODPALAJ, popraw bledy\n" : ">>> mozesz testowac\n";
exit($err ? 1 : 0);

sub short { my $p = shift; $p =~ s{^\Q$MOD\E/resource/}{}; $p }
sub slurp { open(my $h,'<:raw',$_[0]) or return ''; local $/; my $c=<$h>; close $h; $c }
sub walk_pkg { my ($d,$pre,$out) = @_;
    opendir(my $h,$d) or return;
    for my $e (grep { !/^\.\.?$/ } readdir $h) {
        my $p = "$d/$e"; my $r = $pre ? "$pre/$e" : $e;
        if (-d $p) { walk_pkg($p,$r,$out) } else { push @$out, $r }
    }
    closedir $h;
}
