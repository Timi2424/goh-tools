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
die "uzycie: skaluj-model.pl <pak> <mdl w paku> <skala> <katalog> <przedrostek>\n" unless $PRZED;
die "skala musi byc liczba > 0\n" unless $S =~ /^\d*\.?\d+$/ && $S > 0;

sub z_paka {
    my ($wpis) = @_;
    open my $h, '-|', 'unzip', '-p', $PAK, $wpis or die "unzip: $!";
    binmode $h; local $/; my $t = <$h>; close $h;
    die "brak $wpis w $PAK\n" unless defined $t && length $t;
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
