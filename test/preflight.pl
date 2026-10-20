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
# testing_ground* to katalogi Hortena - ale nasze misje laboratorium leza
# wlasnie tam (obok jego terenu), wiec hf_lab*.mi sa NASZE i musza przejsc
# kontrole. Wczesniej wypadaly razem z calym katalogiem.
my @mine = grep {
    m{/map/testing_ground[^/]*/hf_lab[^/]*\.mi$}i
    || !m{/(interface/splash|map/testing_ground|message\.txt)}
} @loose;
my @lab = grep { m{/hf_lab[^/]*\.mi$}i } @mine;

print "=== pliki luzne w modzie: ", scalar @loose, " (nasze: ", scalar @mine,
      (@lab ? ", w tym laboratorium: " . scalar @lab : ''), ") ===\n\n";

# ---------- 1. nawiasy i sklejone wiersze ----------
# Cala logika w gem2::sprawdz_tekst - ta sama, ktora wola test/sprawdz-plik.pl
# ze skryptow powloki. Komentarze (srednik do konca wiersza, poza stringami)
# sa wycinane przed kontrola; sklejka }{"nazwa" jest szukana osobno, bo
# bilansuje sie poprawnie i parser po cichu polyka caly blok.
print "--- nawiasy i sklejki ---\n";
my $n_bl = 0;
for my $f (@mine) {
    next unless $f =~ /\.(inc|set|reg|ext|pattern|def|mi)$/i;
    open(my $h,'<:raw',$f) or next; local $/; my $raw = <$h>; close $h;
    my $n = short($f);
    for my $p (gem2::sprawdz_tekst($raw)) {
        my $gdzie = $p->{linia} ? "$n:$p->{linia}" : $n;
        if ($p->{poziom} eq 'blad') { bad "$gdzie  $p->{opis}"; $n_bl++ }
        else                        { warn_ "$gdzie  $p->{opis}" }
    }
}
ok "wszystkie zbilansowane, brak sklejek" unless $n_bl;

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
    my %lab = map { $_ => 1 } @lab;
    for my $f (@mine) {
        next if $lab{$f};
        my $rel = $f; $rel =~ s{^\Q$MOD\E/resource/}{};
        push @extra, $rel unless $inpkg{$rel};
    }
    if (@extra) {
        warn_ "pliki poza paczka (eksperymenty): " . scalar @extra;
        print "          $_\n" for @extra;
    } else { ok "mod == paczka, zero eksperymentow" }
    # Misje laboratorium tez sa poza paczka, ale to nie wyciek: to osobne
    # misje edytora na mapie testowej, kolega ich nie dostaje, konkwista
    # ich nie wczytuje. Liczone osobno, zeby nie zagluszaly prawdziwych.
    ok "laboratorium: " . scalar(@lab) . " misja(e) - poza paczka, nie dotyka co-opa" if @lab;
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
