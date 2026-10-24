#!/usr/bin/perl
# skaluj-model.pl - rowno przeskalowana kopia modelu GEM2 (.mdl + jego .ply), np. wiekszy wykop.
#
#   perl narzedzia/skaluj-model.pl <pak> <sciezka .mdl w paku> <skala> <katalog wyjscia> <przedrostek>
#
# Przyklad (dol mozdzierza x1.15, kopia obok oryginalu, zeby tekstury z .mtl sie znalazly):
#   perl narzedzia/skaluj-model.pl ".../resource/entity/landscape.pak" \
#        landscape/cut_entity/trenches/dirt/trench_dirt_mortar_engineer/trench_dirt_mortar_engineer.mdl \
#        1.15 <repo>/eksperymenty/resource/entity/landscape/cut_entity/trenches/dirt/trench_dirt_mortar_engineer hf_x115
#
# Wynik: <przedrostek>.mdl + <przedrostek>_<plik>.ply w katalogu wyjscia. Kopie kladz OBOK oryginalu
# (ten sam katalog wirtualny) - materialy w .ply/.mtl maja nazwy bez sciezki i sa szukane w katalogu
# modelu (2026-10-23: kopia modelu w innym katalogu = szachownica "1M" zamiast tekstur).
#
# .mdl (tekst): skalowane sa przesuniecia, nie obroty: {Position x y z}, ostatni wiersz {matrix34},
# {center}/{extent} przeszkod, {vertex} obszarow (obrys wykopu), {radius}, {box}. .vol (bryly
# wielosciennne) NIE sa obslugiwane - skrypt przerywa, jesli model je ma.
# .ply (EPLY, opis w docs/tipy.md): BNDS (6 floatow) i pozycja kazdego wierzcholka (pierwsze 12 B
# rekordu VERT) razy skala; normalne, uv i reszta bez zmian (przy rownym skalowaniu kierunki zostaja).

use strict;
use warnings;
use File::Path qw(make_path);

my ($PAK, $MDL, $S, $OUT, $PRZED) = @ARGV;
die "uzycie: skaluj-model.pl <pak> <mdl w paku> <skala|sx,sy,sz> <katalog> <przedrostek>\n" unless $PRZED;
if ($S =~ /,/) {    # skala osobno na osie - tryb z drzewem modelu (nizej, po funkcjach)
    my @s = split /,/, $S;
    die "skala per os: trzy liczby > 0 (sx,sy,sz)\n" unless @s == 3 && !grep { !/^\d*\.?\d+$/ || $_ <= 0 } @s;
    skaluj_osie(@s);
    exit 0;
}
die "skala musi byc liczba > 0\n" unless $S =~ /^\d*\.?\d+$/ && $S > 0;

use FindBin; use lib $FindBin::Bin; use Pak;   # odczyt z paka w Perlu (bez procesu unzip na plik)
sub z_paka {
    my ($wpis) = @_;
    my $t = Pak::czytaj($PAK, $wpis);
    die "brak $wpis w $PAK\n" unless length $t;
    return $t;
}
sub l { my $v = $_[0] * $S; my $t = sprintf '%.4f', $v; $t =~ s/\.?0+$//; $t eq '-0' ? '0' : $t }
my $NUM = qr/-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?/;

my ($kat) = $MDL =~ m{^(.*)/[^/]+$} or die "zla sciezka mdl\n";
my $m = z_paka($MDL);
die "model ma bryly .vol - nieobslugiwane\n" if $m =~ /"[^"]+\.vol"/;

my %n;
$n{position} = ($m =~ s/\{Position\s+($NUM)\s+($NUM)\s+($NUM)\s*\}/'{Position ' . join(' ', map { l($_) } $1, $2, $3) . '}'/gie);
$n{matrix34} = ($m =~ s/(\{matrix34\s+(?:$NUM\s+){9})($NUM)(\s+)($NUM)(\s+)($NUM)/$1 . l($2) . $3 . l($4) . $5 . l($6)/ge);
for my $k (qw(center extent vertex)) {
    $n{$k} = ($m =~ s/\{$k\s+($NUM)\s+($NUM)\s*\}/"{$k " . l($1) . ' ' . l($2) . '}'/ge);
}
$n{radius} = ($m =~ s/\{radius\s+($NUM)\s*\}/'{radius ' . l($1) . '}'/ge);
$n{box} = ($m =~ s/\{box\s+($NUM)\s+($NUM)\s+($NUM)\s*\}/'{box ' . join(' ', map { l($_) } $1, $2, $3) . '}'/ge);

my %ply;
$m =~ s/\{VolumeView\s+"([^"\/]+\.ply)"/$ply{$1} = "${PRZED}_$1"; qq({VolumeView "$ply{$1}")/ge;
die "model nie ma VolumeView *.ply\n" unless %ply;
$m = "; skaluj-model.pl: $MDL x$S\r\n" . $m;

make_path($OUT);
open my $o, '>:raw', "$OUT/$PRZED.mdl" or die "$OUT/$PRZED.mdl: $!"; print $o $m; close $o;
print "  $PRZED.mdl: ", join(', ', map { "$_ $n{$_}" } grep { $n{$_} } sort keys %n), "\n";

for my $p (sort keys %ply) {
    my $d = z_paka("$kat/$p");
    die "$p: to nie EPLY\n" unless substr($d, 0, 4) eq 'EPLY';
    my $poz = 4; my $wierz = 0;
    while ($poz < length $d) {
        my $tag = substr($d, $poz, 4); $poz += 4;
        if ($tag eq 'BNDS') {
            substr($d, $poz, 24) = pack 'f<6', map { $_ * $S } unpack 'f<6', substr($d, $poz, 24);
            $poz += 24;
        } elsif ($tag eq 'SKIN') {
            my $n = unpack 'V', substr($d, $poz, 4); $poz += 4;
            for (1 .. $n) { my $dl = ord substr($d, $poz, 1); $poz += 1 + $dl }
        } elsif ($tag eq 'MESH') {
            my ($fl, $ff, $fc, $x) = unpack 'V4', substr($d, $poz, 16); $poz += 16;
            $poz += 4 if $x & 0x200;
            my $dl = ord substr($d, $poz, 1); $poz += 1 + $dl;
            if ($d =~ /^.{4}BNDS.{24}SKIN/s) { my $k = ord substr($d, $poz, 1); $poz += 1 + $k }
        } elsif ($tag eq 'VERT') {
            my ($n, $krok) = unpack 'Vv', substr($d, $poz, 6); $poz += 8;
            for my $i (0 .. $n - 1) {
                my $q = $poz + $i * $krok;
                substr($d, $q, 12) = pack 'f<3', map { $_ * $S } unpack 'f<3', substr($d, $q, 12);
            }
            $poz += $n * $krok; $wierz += $n;
        } elsif ($tag eq 'INDX') {
            my $n = unpack 'V', substr($d, $poz, 4); $poz += 4 + 2 * $n;
            last;    # dalej MROR/ADJA/drugi EPLY - bez geometrii do skalowania (jak w podglad.pl)
        } else {
            die "$p: nieznany blok '$tag' przed INDX (pozycja " . ($poz - 4) . ")\n";
        }
    }
    die "$p: brak wierzcholkow\n" unless $wierz;
    open my $w, '>:raw', "$OUT/$ply{$p}" or die "$OUT/$ply{$p}: $!"; print $w $d; close $w;
    printf "  %s: %d wierzcholkow x%s\n", $ply{$p}, $wierz, $S;
}

# ---------------------------------------------------------------------------------------------
# Skala osobno na osie (sx,sy,sz w ukladzie encji), np. dluzszy okop: tylko dlugosc, szerokosc
# i glebokosc bez zmian. Model czytany jako drzewo {...}, bo kosci obrocone wokol z mieszaja x i y:
# dla kosci o obrocie swiatowym W (wiersze = osie lokalne, p_swiat = p_lok*W) punkt lokalny
# przechodzi przez L = W*S*W^T. Obroty kosci zostaja, przesuniecia ida przez L rodzica.
# Bryly: {box} - wymiar wzdluz osi lokalnej i razy |os_i*S| (pudlo nie ma scinania);
# {polyhedron "x.vol"} - wierzcholki .vol przez L bryly (kopia .vol z przedrostkiem).
# .vol (EVLM): VERT n + n*3 float, INDX, SIDE (numery scian) - geometria tylko w VERT.
# Przeszkody obb2 i obszary sa w ukladzie encji: srodek/wierzcholki razy (sx,sy), os = kierunek
# os*S, polowki razy dlugosc przeskalowanej osi i prostopadlej. Normalne w .ply bez zmian.
sub skaluj_osie {
    my @S = @_;
    my $N = qr/-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?/;
    my ($kat) = $MDL =~ m{^(.*)/[^/]+$} or die "zla sciezka mdl\n";
    my $tekst = z_paka($MDL);
    my $crlf = $tekst =~ /\r\n/;

    # drzewo: wezel = [elementy], element = napis albo wezel
    my @tok = $tekst =~ /(;[^\n]*|\{|\}|"[^"]*"|[^\s{}"]+)/g;
    my $korzen = []; my @stos = ($korzen);
    for my $t (@tok) {
        next if $t =~ /^;/;
        if ($t eq '{') { my $w = []; push @{ $stos[-1] }, $w; push @stos, $w }
        elsif ($t eq '}') { pop @stos; die "nawiasy\n" unless @stos }
        else { push @{ $stos[-1] }, $t }
    }
    die "niezamkniete nawiasy\n" if @stos != 1;
    my $nazwa = sub { lc($_[0][0] // '') };
    my $dz = sub { my ($w, $n) = @_; grep { ref && lc($_->[0]) eq $n } @$w };
    my $liczby = sub { [ grep { /^$N$/ } @{ $_[0] }[1 .. $#{ $_[0] }] ] };
    my $f = sub { my $t = sprintf '%.4f', $_[0]; $t =~ s/\.?0+$//; $t eq '-0' ? '0' : $t };

    # macierze 3x3 (wiersze), wektory wierszowe
    my $mm = sub { my ($a, $b) = @_; [ map { my $i = $_; [ map { my $j = $_; $a->[$i][0] * $b->[0][$j] + $a->[$i][1] * $b->[1][$j] + $a->[$i][2] * $b->[2][$j] } 0 .. 2 ] } 0 .. 2 ] };
    my $tr = sub { my $a = shift; [ map { my $i = $_; [ map { $a->[$_][$i] } 0 .. 2 ] } 0 .. 2 ] };
    my $vm = sub { my ($v, $a) = @_; [ map { my $j = $_; $v->[0] * $a->[0][$j] + $v->[1] * $a->[1][$j] + $v->[2] * $a->[2][$j] } 0 .. 2 ] };
    my $Sm = [[$S[0], 0, 0], [0, $S[1], 0], [0, 0, $S[2]]];
    my $L = sub { my $W = shift; $mm->($mm->($W, $Sm), $tr->($W)) };
    my $I = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
    my $dl = sub { my $v = $vm->($_[0], $Sm); sqrt($v->[0]**2 + $v->[1]**2 + $v->[2]**2) };

    # obrot i przesuniecie z wezla (orientation / matrix34 / Position); zwraca [R, ref-do-liczb przesuniecia]
    my $rt = sub {
        my $w = shift; my $R = $I; my $t;
        for my $c (grep { ref } @$w) {
            my $n = $nazwa->($c); my @l = @{ $liczby->($c) };
            if ($n eq 'orientation' && @l == 9) { $R = [[@l[0..2]], [@l[3..5]], [@l[6..8]]] }
            elsif ($n eq 'matrix34' && @l == 12) { $R = [[@l[0..2]], [@l[3..5]], [@l[6..8]]]; $t = $c }
            elsif ($n eq 'position' && @l == 3) { $t = $c }
        }
        return ($R, $t);
    };
    my $przesun = sub {   # ostatnie 3 liczby wezla t (matrix34/Position) razy macierz
        my ($t, $M) = @_; return unless $t;
        my @ix = grep { $t->[$_] =~ /^$N$/ } 1 .. $#$t; my @o = @ix[-3 .. -1];
        my $v = $vm->([ map { $t->[$_] } @o ], $M);
        $t->[$o[$_]] = $f->($v->[$_]) for 0 .. 2;
    };

    my (%Lkosci, %Wkosci, %ply);
    my $kosc; $kosc = sub {
        my ($w, $Wr) = @_;
        my ($R, $t) = $rt->($w);
        $przesun->($t, $L->($Wr));
        my $W = $mm->($R, $Wr);
        my $nm = ($w->[1] // '') =~ s/"//gr;
        $Wkosci{$nm} = $W; $Lkosci{$nm} = $L->($W);
        for my $vv ($dz->($w, 'volumeview')) {
            my ($p) = grep { !ref && /\.ply"$/i } @$vv or next;
            (my $plik = $p) =~ s/"//g;
            die "VolumeView ze sciezka nieobslugiwany: $plik\n" if $plik =~ m{/};
            $ply{$plik} = $Lkosci{$nm};
            $vv->[ (grep { $vv->[$_] eq $p } 0 .. $#$vv)[0] ] = qq{"${PRZED}_$plik"};
        }
        $kosc->($_, $W) for $dz->($w, 'bone');
    };
    for my $sk ($dz->($korzen, 'skeleton')) { $kosc->($_, $I) for $dz->($sk, 'bone') }
    die "model bez kosci z .ply\n" unless %ply;

    my %vol;
    for my $v ($dz->($korzen, 'volume')) {
        my ($b) = $dz->($v, 'bone'); my $bn = ($b ? $b->[1] : '') =~ s/"//gr;
        my $Wb = $Wkosci{$bn} // $I; my $Lb = $Lkosci{$bn} // $Sm;
        my ($R, $t) = $rt->($v);
        $przesun->($t, $Lb);
        my $Wv = $mm->($R, $Wb);
        if (my ($box) = $dz->($v, 'box')) {
            my @ix = grep { $box->[$_] =~ /^$N$/ } 1 .. $#$box;
            $box->[$ix[$_]] = $f->($box->[$ix[$_]] * $dl->($Wv->[$_])) for 0 .. 2;
        }
        if (my ($ph) = $dz->($v, 'polyhedron')) {
            (my $plik = $ph->[1]) =~ s/"//g;
            $vol{$plik} = $L->($Wv); $ph->[1] = qq{"${PRZED}_$plik"};
        }
    }
    for my $o ($dz->($korzen, 'obstacle')) {
        for my $b ($dz->($o, 'obb2')) {
            my ($c) = $dz->($b, 'center'); my ($e) = $dz->($b, 'extent'); my ($a) = $dz->($b, 'axis');
            my @a = @{ $liczby->($a) }; my @e = @{ $liczby->($e) };
            my $la = sqrt(($a[0] * $S[0])**2 + ($a[1] * $S[1])**2); my $lp = sqrt(($a[1] * $S[0])**2 + ($a[0] * $S[1])**2);
            my $na = sqrt($a[0]**2 + $a[1]**2) || 1; $la /= $na; $lp /= $na;
            @$c[1, 2] = ($f->($c->[1] * $S[0]), $f->($c->[2] * $S[1]));
            @$e[1, 2] = ($f->($e[0] * $la), $f->($e[1] * $lp));
            @$a[1, 2] = map { $f->($_ / ($la * $na)) } ($a[0] * $S[0], $a[1] * $S[1]);
        }
    }
    for my $ar ($dz->($korzen, 'area')) {
        for my $p (grep { ref } @$ar) {
            for my $v ($dz->($p, 'vertex')) { @$v[1, 2] = ($f->($v->[1] * $S[0]), $f->($v->[2] * $S[1])) }
            for my $r ($dz->($p, 'radius')) { $r->[1] = $f->($r->[1] * ($S[0] > $S[1] ? $S[0] : $S[1])) }
        }
    }

    # zapis drzewa
    my $eol = $crlf ? "\r\n" : "\n";
    my $pisz; $pisz = sub {
        my ($w, $wc) = @_;
        my @slowa = grep { !ref } @$w; my @dz = grep { ref } @$w;
        my $s = "\t" x $wc . '{' . join(' ', @slowa);
        return "$s}$eol" unless @dz;
        return $s . $eol . join('', map { $pisz->($_, $wc + 1) } @dz) . "\t" x $wc . "}$eol";
    };
    make_path($OUT);
    my $wyj = "; skaluj-model.pl: $MDL x$S[0],$S[1],$S[2]$eol" . join('', map { ref ? $pisz->($_, 0) : () } @$korzen);
    open my $o, '>:raw', "$OUT/$PRZED.mdl" or die "$OUT/$PRZED.mdl: $!"; print $o $wyj; close $o;
    print "  $PRZED.mdl: ", scalar(keys %ply), " .ply, ", scalar(keys %vol), " .vol\n";

    for my $p (sort keys %ply) {
        my $d = z_paka("$kat/$p"); my $M = $ply{$p};
        die "$p: to nie EPLY\n" unless substr($d, 0, 4) eq 'EPLY';
        my ($poz, $wierz, $bnds, @min, @max) = (4, 0);
        while ($poz < length $d) {
            my $tag = substr($d, $poz, 4); $poz += 4;
            if ($tag eq 'BNDS') { $bnds = $poz; $poz += 24 }
            elsif ($tag eq 'SKIN') { my $n = unpack 'V', substr($d, $poz, 4); $poz += 4; for (1 .. $n) { my $k = ord substr($d, $poz, 1); $poz += 1 + $k } }
            elsif ($tag eq 'MESH') {
                my ($fl, $ff, $fc, $x) = unpack 'V4', substr($d, $poz, 16); $poz += 16;
                $poz += 4 if $x & 0x200;
                my $k = ord substr($d, $poz, 1); $poz += 1 + $k;
                if ($d =~ /^.{4}BNDS.{24}SKIN/s) { my $k2 = ord substr($d, $poz, 1); $poz += 1 + $k2 }
            } elsif ($tag eq 'VERT') {
                my ($n, $krok) = unpack 'Vv', substr($d, $poz, 6); $poz += 8;
                for my $i (0 .. $n - 1) {
                    my $q = $poz + $i * $krok;
                    my $v = $vm->([ unpack 'f<3', substr($d, $q, 12) ], $M);
                    substr($d, $q, 12) = pack 'f<3', @$v;
                    for (0 .. 2) { $min[$_] = $v->[$_] if !defined $min[$_] || $v->[$_] < $min[$_]; $max[$_] = $v->[$_] if !defined $max[$_] || $v->[$_] > $max[$_] }
                }
                $poz += $n * $krok; $wierz += $n;
            } elsif ($tag eq 'INDX') { last }
            else { die "$p: nieznany blok '$tag' przed INDX\n" }
        }
        die "$p: brak wierzcholkow\n" unless $wierz;
        substr($d, $bnds, 24) = pack 'f<6', @min, @max if defined $bnds;
        open my $w, '>:raw', "$OUT/${PRZED}_$p" or die; print $w $d; close $w;
        printf "  %s: %d wierzcholkow\n", "${PRZED}_$p", $wierz;
    }
    for my $p (sort keys %vol) {
        my $d = z_paka("$kat/$p"); my $M = $vol{$p};
        die "$p: to nie EVLM/VERT\n" unless substr($d, 0, 8) eq 'EVLMVERT';
        my $n = unpack 'V', substr($d, 8, 4);
        for my $i (0 .. $n - 1) {
            my $q = 12 + 12 * $i;
            substr($d, $q, 12) = pack 'f<3', @{ $vm->([ unpack 'f<3', substr($d, $q, 12) ], $M) };
        }
        die "$p: po wierzcholkach brak INDX\n" unless substr($d, 12 + 12 * $n, 4) eq 'INDX';
        open my $w, '>:raw', "$OUT/${PRZED}_$p" or die; print $w $d; close $w;
        printf "  %s: %d wierzcholkow\n", "${PRZED}_$p", $n;
    }
}
