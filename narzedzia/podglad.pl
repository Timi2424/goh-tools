#!/usr/bin/perl
# podglad.pl - podglad modeli GEM2 (Gates of Hell) jako PNG, bez wchodzenia do gry.
#
#   perl podglad.pl <encja> [-o plik.png] [opcje]       jedna encja
#   perl podglad.pl --zlozenie plik.txt [-o plik.png]   kilka encji z pozycja/obrotem/skala
#   perl podglad.pl --info <encja>                      tylko opis tekstowy (kosci, przeszkody, BNDS)
#   perl podglad.pl --szukaj <regex>                    sciezki w pakach
#   perl podglad.pl --pokaz <sciezka>                   wypisz plik tekstowy z paka (.mdl/.def/.mtl)
#
# <encja>: sciezka w paku (landscape/.../trench_modular.mdl albo .def), krotka nazwa
#          (trench_modular - szuka <nazwa>.def / .mdl we wszystkich pakach) albo plik na dysku
#          (.def/.mdl/.ply; pliki, ktorych nie ma obok, szukane w pakach po czesci po resource/entity/).
# Zrodla (pierwsze wygrywa): --zrodlo <pak|katalog> (mozna kilka), luzne pliki i paki Hortena
#          (workshop 3359417100, wylacz --bez-hortena), paki gry resource/entity/*.pak.
#
# Opcje: -o plik.png  --szer 1600  --ss 2 (nadprobkowanie)  --siatka N (krok kratki)
#        --bez <regex> (ukryj siatki, ktorych plik/kosc pasuje)  --kosci 0|1|<regex nazw>  --bryly 0|1
#        --przeszkody 0|1  --tytul "..."  --bez-placer (nie dorysowuj encji z {placer} w .def)
#        --elewacja +y|-y|+x|-x (skad patrzymy w elewacji, domyslnie +y)
#        --przekroj V  (elewacja: ukryj trojkaty lezace w calosci przed plaszczyzna os=V,
#                       np. --elewacja +y --przekroj -12: sciana strzelnicy pillboxa od srodka)
#
# Plik zlozenia (# komentarz; wiersz = encja + liczby x y z obr skala albo klucz=wartosc):
#   tytul Stanowisko plot v1
#   siatka 10
#   trench_modular   x=0   y=0   obr=0
#   trench_modular   108 0 0 90
#   trench_modular   x=-29 y=-59 kotwica=body     (x,y to miejsce srodka przeszkody "body")
#   netting_square   x=54 y=54 z=-6 skala=1.6 nazwa=siatka
#   trench_modular   na=1:land obr=180          (pozycja wzgledem kosci instancji nr 1)
# obr = stopnie wokol z; dodatni obraca +x w strone +y (na widoku z gory, gdzie +y jest w dol,
# to zgodnie z ruchem wskazowek zegara). Klucze: x y z obr skala (s albo sx,sy,sz) na nazwa
# kotwica=<przeszkoda|kosc|x,y[,z]> (punkt encji, ktory ma trafic w x y z) kosci=0|1 bryly=0|1
# przeszkody=0|1 bez=<regex>. Dyrektywy: tytul, siatka, kosci, bryly, przeszkody, bez,
# elewacja, przekroj.
#
# Uklad wspolrzednych: jednostki modelu, z w gore. Kosci eksportu z 3ds Max odwracaja y
# (orientation 1 0 0 / 0 -1 0 / 0 0 1), wiec silnik jest lewoskretny: widok z gory rysuje +x
# w prawo i +y W DOL - wtedy obraz nie jest lustrzanym odbiciem tego, co w grze.
# Macierze kosci: wiersze = osie lokalne w ukladzie rodzica (p' = p*R + t), jak w DirectX.
# Format EPLY i reszta: docs/tipy.md, sekcja "Podglad modeli".

use strict;
use warnings;
use utf8;
use POSIX qw(floor ceil);
use Compress::Zlib ();
use Compress::Raw::Zlib ();
use File::Basename qw(dirname basename);
use List::Util qw(sum0);
use Time::HiRes qw(time);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
@ARGV = map { utf8::is_utf8($_) ? $_ : do { my $s = $_; utf8::decode($s); $s } } @ARGV;

my $T0 = time;
my $GRA = $ENV{GOH_GRA} // '/c/Program Files (x86)/Steam/steamapps/common/Call to Arms - Gates of Hell';
my $HORTEN = $ENV{GOH_HORTEN} // '/c/Program Files (x86)/Steam/steamapps/workshop/content/400750/3359417100';

# ------------------------------------------------------------------ opcje
my %O = (szer => 1600, ss => 2, kosci => undef, bryly => undef, przeszkody => undef, horten => 1);
my (@zrodla, @args, @bez);
while (@ARGV) {
    my $a = shift @ARGV;
    if    ($a eq '-o')               { $O{o} = shift @ARGV }
    elsif ($a eq '--zlozenie')       { $O{zlozenie} = shift @ARGV }
    elsif ($a eq '--info')           { $O{info} = 1 }
    elsif ($a eq '--szukaj')         { $O{szukaj} = shift @ARGV }
    elsif ($a eq '--pokaz')          { $O{pokaz} = shift @ARGV }
    elsif ($a eq '--zrodlo')         { push @zrodla, shift @ARGV }
    elsif ($a eq '--bez-hortena')    { $O{horten} = 0 }
    elsif ($a eq q{--bez-placer})     { $O{bez_placer} = 1 }
    elsif ($a eq '--bez')            { push @bez, shift @ARGV }
    elsif ($a =~ /^--(szer|ss|siatka|kosci|bryly|przeszkody|tytul|elewacja|przekroj)$/) { $O{$1} = shift @ARGV }
    elsif ($a =~ /^-/)               { die "nieznana opcja $a\n" }
    else                             { push @args, $a }
}

# ------------------------------------------------------------------ ZIP (paki .pak)
sub zip_open {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "nie moge otworzyc $path: $!\n";
    my $size = -s $fh;
    my $tail = $size < 70000 ? $size : 70000;
    seek $fh, $size - $tail, 0;
    my $buf; read $fh, $buf, $tail;
    my $i = rindex $buf, "PK\x05\x06";
    die "$path: brak katalogu ZIP\n" if $i < 0;
    my (undef, undef, undef, undef, $n, $cd_size, $cd_off) = unpack 'VvvvvVV', substr($buf, $i, 20);
    my $l64 = rindex $buf, "PK\x06\x07", $i;    # ZIP64 (paki gry): prawdziwe liczby w EOCD64
    if ($l64 >= 0 && ($cd_off == 0xFFFFFFFF || $n == 0xFFFF || $cd_size == 0xFFFFFFFF)) {
        my $off64 = unpack 'Q<', substr($buf, $l64 + 8, 8);
        seek $fh, $off64, 0;
        my $e64;
        read $fh, $e64, 56;
        die "$path: zly EOCD64\n" unless substr($e64, 0, 4) eq "PK\x06\x06";
        ($n, $cd_size, $cd_off) = unpack 'Q<Q<Q<', substr($e64, 32, 24);
    }
    seek $fh, $cd_off, 0;
    my $cd; read $fh, $cd, $cd_size;
    my %e;
    my $p = 0;
    for (1 .. $n) {
        my @h = unpack 'VvvvvvvVVVvvvvvVV', substr($cd, $p, 46);
        last unless $h[0] == 0x02014b50;
        my ($meth, $cs, $us, $nl, $xl, $cl, $lo) = @h[4, 8, 9, 10, 11, 12, 16];
        my $name = substr($cd, $p + 46, $nl);
        if ($us == 0xFFFFFFFF || $cs == 0xFFFFFFFF || $lo == 0xFFFFFFFF) {    # pole extra 0x0001
            my $x = substr($cd, $p + 46 + $nl, $xl);
            while (length $x >= 4) {
                my ($id, $sz) = unpack 'vv', $x;
                if ($id == 1) {
                    my @q = unpack 'Q<*', substr($x, 4, $sz);
                    $us = shift @q if $us == 0xFFFFFFFF;
                    $cs = shift @q if $cs == 0xFFFFFFFF;
                    $lo = shift @q if $lo == 0xFFFFFFFF;
                    last;
                }
                $x = substr($x, 4 + $sz);
            }
        }
        $p += 46 + $nl + $xl + $cl;
        next if $name =~ m{/$};
        $name =~ tr{\\}{/};
        $e{lc $name} = [$lo, $cs, $us, $meth, $name];
    }
    return { path => $path, fh => $fh, e => \%e };
}

sub zip_read {
    my ($z, $key) = @_;
    my ($lo, $cs, $us, $meth) = @{ $z->{e}{$key} };
    my $fh = $z->{fh};
    seek $fh, $lo, 0;
    my $h; read $fh, $h, 30;
    my ($nl, $xl) = unpack 'vv', substr($h, 26, 4);
    seek $fh, $lo + 30 + $nl + $xl, 0;
    my $data; read $fh, $data, $cs;
    return $data if $meth == 0;
    die "$z->{path}: $key - metoda kompresji $meth\n" unless $meth == 8;
    my ($inf, $st) = Compress::Raw::Zlib::Inflate->new(-WindowBits => -Compress::Raw::Zlib::MAX_WBITS(),
                                                        -Bufsize => $us || 4096);
    my $out = '';
    $st = $inf->inflate($data, $out);
    die "$z->{path}: $key - blad inflate $st\n" unless $st == Compress::Raw::Zlib::Z_STREAM_END() || $st == 0;
    return $out;
}

# ------------------------------------------------------------------ zrodla i indeks plikow
my (@SRC, %IDX);    # %IDX: lc sciezka w paku -> [zrodlo, klucz]

sub dodaj_zrodlo {
    my ($p) = @_;
    if (-d $p) {
        my $root = -d "$p/resource/entity" ? "$p/resource/entity" : $p;
        my $s = { typ => 'dir', root => $root, nazwa => "$root (luzne)" };
        push @SRC, $s;
        my @stos = ($root);
        while (my $d = shift @stos) {
            opendir my $dh, $d or next;
            for my $f (readdir $dh) {
                next if $f eq '.' || $f eq '..' || $f =~ /\.pak$/i;
                my $full = "$d/$f";
                if (-d $full) { push @stos, $full; next }
                my $rel = substr($full, length($root) + 1);
                $IDX{lc $rel} //= [$s, $full];
            }
        }
    } elsif ($p =~ /\.pak$/i && -f $p) {
        my $z = zip_open($p);
        my $s = { typ => 'zip', z => $z, nazwa => $p };
        push @SRC, $s;
        $IDX{$_} //= [$s, $_] for keys %{ $z->{e} };
    } else {
        warn "pomijam zrodlo $p (nie ma katalogu ani paka)\n";
    }
}

sub paki_w { my ($d) = @_; opendir my $dh, $d or return (); return map { "$d/$_" } sort grep { /\.pak$/i } readdir $dh }

sub laduj_zrodla {
    return if @SRC;
    dodaj_zrodlo($_) for @zrodla;
    for my $r ($O{horten} ? ($HORTEN) : (), $GRA) {    # luzne pliki wygrywaja z pakami tego samego moda
        my $e = "$r/resource/entity";
        my @kat;
        if (opendir my $dh, $e) { @kat = grep { !/^\./ && -d "$e/$_" } readdir $dh }
        dodaj_zrodlo($e) if @kat;
        dodaj_zrodlo($_) for paki_w($e);
    }
    die "brak zrodel (paki gry w $GRA?)\n" unless @SRC;
}

sub norm_sciezka {
    my ($p) = @_;
    $p =~ tr{\\}{/};
    $p =~ s{^/+}{};
    $p =~ s{^(?:resource/)?entity/}{}i;
    my @o;
    for (split m{/+}, $p) { next if $_ eq '.'; if ($_ eq '..') { pop @o } else { push @o, $_ } }
    return join '/', @o;
}

# vpath: "pak:<sciezka>" albo "plik:<sciezka na dysku>"
sub czytaj {
    my ($vp) = @_;
    if ($vp =~ /^plik:(.*)$/s) {
        open my $fh, '<:raw', $1 or return undef;
        local $/;
        my $d = <$fh>;
        return $d;
    }
    my ($p) = $vp =~ /^pak:(.*)$/s;
    my $hit = $IDX{lc $p} or return undef;
    my ($s, $k) = @$hit;
    if ($s->{typ} eq 'dir') { return czytaj("plik:$k") }
    return zip_read($s->{z}, $k);
}

sub skad { my ($vp) = @_; return $vp =~ /^plik:/ ? 'dysk' : do { my ($p) = $vp =~ /^pak:(.*)/; my $h = $IDX{lc $p}; $h ? basename($h->[0]{nazwa}) : '?' } }

# plik wskazany wzgledem innego (VolumeView, extension, .mtl)
sub obok {
    my ($vp, $rel) = @_;
    $rel =~ tr{\\}{/};
    if ($vp =~ /^plik:(.*)$/s) {
        my $full = $1;
        my $dir = dirname($full);
        my $cand = $rel =~ m{^/} ? undef : "$dir/$rel";
        return "plik:$cand" if defined $cand && -f $cand;
        if ($full =~ m{resource/entity/(.*)$}i) {
            my $pd = dirname($1);
            my $p = $rel =~ m{^/} ? norm_sciezka($rel) : norm_sciezka("$pd/$rel");
            return "pak:$p" if $IDX{lc $p};
        }
        return defined $cand ? "plik:$cand" : "pak:" . norm_sciezka($rel);
    }
    my ($p) = $vp =~ /^pak:(.*)$/s;
    return 'pak:' . ($rel =~ m{^/} ? norm_sciezka($rel) : norm_sciezka(dirname($p) . "/$rel"));
}

sub znajdz_encje {
    my ($arg) = @_;
    return "plik:$arg" if -f $arg;
    laduj_zrodla();
    my $p = norm_sciezka($arg);
    return "pak:$p" if $IDX{lc $p};
    die "nie ma w pakach: $arg\n" if $p =~ m{/};
    my $n = lc $p;
    $n =~ s/\.(def|mdl)$//;
    my @hit = sort { ($a =~ /\.mdl$/) <=> ($b =~ /\.mdl$/) || length($a) <=> length($b) }
              grep { m{(?:^|/)\Q$n\E\.(?:def|mdl)$} } keys %IDX;
    die "nie znaleziono encji '$arg' (szukam $n.def / $n.mdl)\n" unless @hit;
    my %kat;
    my @kat = grep { !$kat{ dirname($_) }++ } @hit;
    if (@kat > 1) { warn "uwaga: '$arg' jest w kilku miejscach, biore pierwsze:\n" . join('', map { "   $_\n" } @kat[0 .. ($#kat > 5 ? 5 : $#kat)]) }
    return 'pak:' . $IDX{ $hit[0] }[1] =~ s{^.*?(?=\Q@{[ (split m{/}, $hit[0])[0] ]}\E)}{}ir if 0;
    my $h = $IDX{ $hit[0] };
    return 'pak:' . ($h->[0]{typ} eq 'zip' ? $h->[1] : $hit[0]);
}

# ------------------------------------------------------------------ SDL (.mdl/.def/.mtl)
# wezel = [nazwa, atomy i wezly-dzieci...]; ( ... ) tez jest wezlem
sub sdl {
    my ($txt) = @_;
    my @stos = (['']);
    while ($txt =~ /\G(?:\s+|;[^\n]*|([{}()])|"((?:[^"\\]|\\.)*)"|([^\s{}()";]+))/gc) {
        if (defined $1) {
            if ($1 eq '{' || $1 eq '(') { my $n = []; push @{ $stos[-1] }, $n; push @stos, $n }
            elsif (@stos > 1) { my $n = pop @stos; unshift @$n, '' if !@$n || ref $n->[0] }    # [0] zawsze nazwa
        }
        elsif (defined $2) { push @{ $stos[-1] }, $2 }
        elsif (defined $3) { push @{ $stos[-1] }, $3 }
    }
    my $r = $stos[0];
    $_->[0] //= '' for grep { ref } @$r;
    return $r;
}
sub dzieci { my ($n, $k) = @_; return grep { ref $_ && defined $_->[0] && !ref $_->[0] && lc $_->[0] eq lc $k } @$n[1 .. $#$n] }
sub dziecko { my @d = dzieci(@_); return $d[0] }
sub liczby {
    my ($n) = @_;
    my @r;
    for my $x (@$n[1 .. $#$n]) {
        if (ref $x) { push @r, liczby($x) }
        elsif ($x =~ /^[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?$/i) { push @r, $x + 0 }
        else { for (split ' ', $x) { push @r, $_ + 0 if /^[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?$/i } }
    }
    return @r;
}
sub napis { my ($n) = @_; return undef unless $n; for (@$n[1 .. $#$n]) { return $_ unless ref } return undef }
sub szukaj_wezla {    # pierwszy wezel o nazwie gdziekolwiek w drzewie
    my ($n, $k) = @_;
    for my $c (grep { ref } @$n[1 .. $#$n]) {
        return $c if !ref $c->[0] && lc $c->[0] eq lc $k;
        my $r = szukaj_wezla($c, $k);
        return $r if $r;
    }
    return undef;
}

# ------------------------------------------------------------------ macierze: [R(3 wiersze), t]
sub ident { return [[[1, 0, 0], [0, 1, 0], [0, 0, 1]], [0, 0, 0]] }
sub mm3 {
    my ($a, $b) = @_;
    my @r;
    for my $i (0 .. 2) { for my $j (0 .. 2) { $r[$i][$j] = $a->[$i][0] * $b->[0][$j] + $a->[$i][1] * $b->[1][$j] + $a->[$i][2] * $b->[2][$j] } }
    return \@r;
}
sub vm3 { my ($v, $m) = @_; return [map { $v->[0] * $m->[0][$_] + $v->[1] * $m->[1][$_] + $v->[2] * $m->[2][$_] } 0 .. 2] }
sub zloz {    # najpierw $l (lokalna), potem $p (rodzic)
    my ($l, $p) = @_;
    my $t = vm3($l->[1], $p->[0]);
    return [mm3($l->[0], $p->[0]), [map { $t->[$_] + $p->[1][$_] } 0 .. 2]];
}
sub odwrotna {    # [R, t] -> [R^-1, -t*R^-1]
    my ($m) = @_;
    my $a = $m->[0];
    my @c = ([$a->[1][1] * $a->[2][2] - $a->[1][2] * $a->[2][1], $a->[0][2] * $a->[2][1] - $a->[0][1] * $a->[2][2], $a->[0][1] * $a->[1][2] - $a->[0][2] * $a->[1][1]],
             [$a->[1][2] * $a->[2][0] - $a->[1][0] * $a->[2][2], $a->[0][0] * $a->[2][2] - $a->[0][2] * $a->[2][0], $a->[0][2] * $a->[1][0] - $a->[0][0] * $a->[1][2]],
             [$a->[1][0] * $a->[2][1] - $a->[1][1] * $a->[2][0], $a->[0][1] * $a->[2][0] - $a->[0][0] * $a->[2][1], $a->[0][0] * $a->[1][1] - $a->[0][1] * $a->[1][0]]);
    my $det = $a->[0][0] * $c[0][0] + $a->[0][1] * $c[1][0] + $a->[0][2] * $c[2][0] || 1;
    my $ri = [map { my $r = $_; [map { $_ / $det } @$r] } @c];
    my $t = vm3($m->[1], $ri);
    return [$ri, [map { -$_ } @$t]];
}
sub tp { my ($m, $v) = @_; my $r = vm3($v, $m->[0]); return [map { $r->[$_] + $m->[1][$_] } 0 .. 2] }
sub transform_z_wezla {
    my ($n) = @_;
    my $m = ident();
    for my $c (grep { ref } @$n[1 .. $#$n]) {
        next if ref $c->[0];
        my $k = lc $c->[0];
        my @v = liczby($c);
        if ($k eq 'orientation' && @v >= 9)  { $m->[0] = [[@v[0 .. 2]], [@v[3 .. 5]], [@v[6 .. 8]]] }
        elsif ($k eq 'position' && @v >= 3)  { $m->[1] = [@v[0 .. 2]] }
        elsif ($k eq 'matrix34' && @v >= 12) { $m = [[[@v[0 .. 2]], [@v[3 .. 5]], [@v[6 .. 8]]], [@v[9 .. 11]]] }
    }
    return $m;
}

# ------------------------------------------------------------------ EPLY
# EPLY | BNDS 6f | [SKIN] | MESH* (u32 flagi, u32 1. trojkat, u32 ile trojkatow, u32 x, [u32 kolor gdy x&0x200],
# u8 dl + nazwa .mtl, [przy SKIN: u8 n + n indeksow kosci]) | VERT (u32 ile, u16 krok, u16 flagi, dane: 3f pozycja, 3f normalna, 2f uv, ...)
# | INDX (u32 ile, u16 indeksy)
my %PLY;
sub czytaj_ply {
    my ($vp) = @_;
    return $PLY{$vp} if exists $PLY{$vp};
    my $d = czytaj($vp);
    unless (defined $d) { warn "brak pliku $vp\n"; return $PLY{$vp} = undef }
    unless (substr($d, 0, 4) eq 'EPLY') { warn "$vp: to nie EPLY\n"; return $PLY{$vp} = undef }
    my %m = (vp => $vp, mesh => [], v => [], i => []);
    my $p = 4;
    my $L = length $d;
    while ($p + 4 <= $L) {
        my $tag = substr($d, $p, 4);
        $p += 4;
        if ($tag eq 'BNDS') { $m{bnds} = [unpack 'f<6', substr($d, $p, 24)]; $p += 24 }
        elsif ($tag eq 'SKIN') {    # u32 ile kosci, (u8 dl + nazwa)*; wierzcholek: 3f pozycja, wagi, indeksy...
            my $n = unpack 'V', substr($d, $p, 4);
            $p += 4;
            $m{skin} = [];    # takze przy n = 0: MESH i tak ma liste kosci
            for (1 .. $n) { my $l = ord substr($d, $p, 1); push @{ $m{skin} }, substr($d, $p + 1, $l); $p += 1 + $l }
        }
        elsif ($tag eq 'MESH') {
            my ($fl, $ff, $fc, $x) = unpack 'V4', substr($d, $p, 16);
            $p += 16;
            $p += 4 if $x & 0x200;
            my $l = ord substr($d, $p, 1);
            my $nm = substr($d, $p + 1, $l);
            unless ($nm =~ /^[\x20-\x7e]+$/) {    # nieznany uklad - szukaj nazwy .mtl w poblizu
                my $q = substr($d, $p - 4, 48);
                if ($q =~ /([\x01-\x40])([\x20-\x7e]+?\.mtl)/ && ord($1) == length $2) { $nm = $2; $p = $p - 4 + $-[0]; $l = length $nm }
                else { warn "$vp: nie rozumiem bloku MESH (flagi $fl/$x)\n"; last }
            }
            $p += 1 + $l;
            $p += 1 + ord substr($d, $p, 1) if $m{skin};    # przy SKIN: u8 ile + indeksy kosci siatki
            push @{ $m{mesh} }, { flagi => $fl, x => $x, ff => $ff, fc => $fc, mtl => $nm };
        }
        elsif ($tag eq 'VERT') {
            my ($n, $s, $fl) = unpack 'Vvv', substr($d, $p, 8);
            $p += 8;
            my @v;
            for my $k (0 .. $n - 1) { push @v, unpack 'f<3', substr($d, $p + $k * $s, 12) }
            $m{v} = \@v;
            $m{krok} = $s;
            $m{vflagi} = $fl;
            $p += $n * $s;
        }
        elsif ($tag eq 'INDX') {
            my $n = unpack 'V', substr($d, $p, 4);
            $p += 4;
            $m{i} = [unpack "v$n", substr($d, $p, 2 * $n)];
            $p += 2 * $n;
        }
        else {    # po INDX bywaja MROR, ADJA, doklejony drugi EPLY - geometria juz jest
            $m{nieznane} = $tag;
            warn "$vp: nieznany blok '$tag' (pomijam reszte)\n" unless @{ $m{i} };
            last;
        }
    }
    $m{mesh} = [{ ff => 0, fc => int(@{ $m{i} } / 3), mtl => '' }] unless @{ $m{mesh} };
    return $PLY{$vp} = \%m;
}

my %MTL;
sub material {
    my ($plyvp, $mtl) = @_;
    my $vp = obok($plyvp, $mtl);
    return $MTL{$vp} //= do {
        my $t = czytaj($vp);
        my %r = (nazwa => $mtl, diffuse => '', blend => 'none');
        if (defined $t) {
            my $s = sdl($t);
            my $mat = dziecko($s, 'material') || $s;
            $r{diffuse} = napis(dziecko($mat, 'diffuse')) // '';
            $r{blend} = lc(napis(dziecko($mat, 'blend')) // 'none');
        }
        \%r;
    };
}

# kolor po nazwie tekstury/materialu
sub kolor_materialu {
    my ($m) = @_;
    my $s = lc "$m->{diffuse} $m->{nazwa}";
    return [96, 120, 62]  if $s =~ /net|camo|maskir/;
    return [176, 156, 112] if $s =~ /sandbag|bag|mesh_bag/;
    return [150, 106, 66] if $s =~ /log|wood|plank|board|bark|timber|beam|derev|brus/;
    return [152, 152, 146] if $s =~ /concrete|beton|stone|brick|cement/;
    return [118, 124, 132] if $s =~ /metal|steel|iron|wire/;
    return [138, 116, 80] if $s =~ /land|ground|earth|ridge|dirt|soil|sand|mud|trench|clay|grass/;
    my $h = 0;
    $h = ($h * 31 + ord) % 360 for split //, $s;
    return hsv($h, 0.35, 0.75);
}
sub hsv {
    my ($h, $s, $v) = @_;
    my $c = $v * $s;
    my $x = $c * (1 - abs((($h / 60) % 2) + ($h / 60 - int($h / 60)) - 1));
    my @r = $h < 60 ? ($c, $x, 0) : $h < 120 ? ($x, $c, 0) : $h < 180 ? (0, $c, $x) : $h < 240 ? (0, $x, $c) : $h < 300 ? ($x, 0, $c) : ($c, 0, $x);
    return [map { int(255 * ($_ + $v - $c)) } @r];
}

# ------------------------------------------------------------------ model (.def/.mdl)
my %MODEL;
sub laduj_model {
    my ($vp) = @_;
    return $MODEL{$vp} if $MODEL{$vp};
    my %M = (vp => $vp, kosci => [], przeszkody => [], obszary => [], bryly => []);
    if ($vp =~ /\.ply$/i) {
        push @{ $M{kosci} }, { nazwa => basename($vp, '.ply'), W => ident(), siatki => [{ vp => $vp, plik => basename($vp) }] };
        return $MODEL{$vp} = \%M;
    }
    my $txt = czytaj($vp) // die "nie moge przeczytac $vp\n";
    my $mdlvp = $vp;
    if ($vp =~ /\.def$/i) {
        $M{def} = $vp;
        # .def + jego (include "...") z paka/dysku (np. lafette.inc z {extension}); /properties/... pomijamy
        my @drzewa;
        my %bylo;
        my $dolacz;
        $dolacz = sub {
            my ($fvp, $t, $gl) = @_;
            return if $bylo{$fvp}++ || $gl > 4;
            my $s = sdl($t);
            push @drzewa, $s;
            my @st = ($s);
            while (my $n = shift @st) {
                for my $c (grep { ref } @$n[1 .. $#$n]) {
                    if (!ref $c->[0] && lc $c->[0] eq 'include' && defined(my $f = napis($c))) {
                        my $ivp = obok($fvp, $f);
                        my $it = czytaj($ivp);
                        $dolacz->($ivp, $it, $gl + 1) if defined $it;
                    } else { push @st, $c }
                }
            }
        };
        $dolacz->($vp, $txt, 0);
        my ($ext) = grep { defined } map { napis(szukaj_wezla($_, 'extension')) } @drzewa;
        if (!$ext) { (my $m = $vp) =~ s/\.def$/.mdl/i; $ext = basename($m) }
        # {placer {place "1" {entity "X"} {linkbone "attach1"} {handlebone "body"}}} - encja X na kosci
        if (my ($pl) = grep { defined } map { szukaj_wezla($_, 'placer') } @drzewa) {
            for my $p (dzieci($pl, 'place')) {
                my $e = napis(dziecko($p, 'entity')) // next;
                push @{ $M{placer} }, { nazwa => napis($p) // '', encja => $e,
                    link => napis(dziecko($p, 'linkbone')) // '', handle => napis(dziecko($p, 'handlebone')) // '' };
            }
        }
        $mdlvp = obok($vp, $ext);
        $txt = czytaj($mdlvp) // die "def $vp wskazuje $ext, ale nie ma $mdlvp\n";
    }
    $M{mdl} = $mdlvp;
    my $s = sdl($txt);
    my %bw;
    if (my $sk = dziecko($s, 'skeleton')) {
        my $rek;
        $rek = sub {
            my ($n, $W, $rodzic) = @_;
            my $L = transform_z_wezla($n);
            my $Wk = zloz($L, $W);
            my %k = (nazwa => napis($n) // '?', W => $Wk, rodzic => $rodzic, siatki => []);
            my $par = napis(dziecko($n, 'parameters'));
            $k{param} = $par if defined $par;
            my $vis = dziecko($n, 'visibility');
            $k{ukryta} = 1 if $vis && (liczby($vis))[0] == 0;
            my @vv = dzieci($n, 'volumeview');
            for my $lod (dzieci($n, 'lodview')) { my @w = dzieci($lod, 'volumeview'); push @vv, $w[0] if @w }
            for my $v (@vv) {
                my $f = napis($v) // next;
                push @{ $k{siatki} }, { vp => obok($mdlvp, $f), plik => $f, ground => dziecko($v, 'ground') ? 1 : 0 };
            }
            push @{ $M{kosci} }, \%k;
            $bw{ lc $k{nazwa} } = $Wk;
            $rek->($_, $Wk, $k{nazwa}) for dzieci($n, 'bone');
        };
        $rek->($_, ident(), undef) for dzieci($sk, 'bone');
    }
    for my $k (qw(obstacle area)) {
        for my $n (dzieci($s, $k)) {
            my $ksz = ksztalt2($n) or next;
            my $tags = join ' ', map { napis($_) // () } dzieci($n, 'tags');
            my @t = dzieci($n, 'tags');
            $tags = join ' ', grep { !ref } map { @$_[1 .. $#$_] } @t;
            push @{ $M{ $k eq 'obstacle' ? 'przeszkody' : 'obszary' } }, { nazwa => napis($n) // '', ksztalt => $ksz, tags => $tags };
        }
    }
    for my $n (dzieci($s, 'volume')) {
        my $kn = napis(dziecko($n, 'bone')) // '';
        my $W = $bw{ lc $kn } // ident();
        my $L = transform_z_wezla($n);
        my %b = (nazwa => napis($n) // '', kosc => $kn, W => zloz($L, $W));
        if (my $box = dziecko($n, 'box')) { $b{box} = [liczby($box)] }
        elsif (my $ph = dziecko($n, 'polyhedron')) { $b{poly} = napis($ph) }
        elsif (my $c = dziecko($n, 'cylinder')) { $b{cyl} = [liczby($c)] }
        push @{ $M{bryly} }, \%b;
    }
    return $MODEL{$vp} = \%M;
}

# obb2 / polygon2 / circle2 -> lista punktow 2D w ukladzie encji
sub ksztalt2 {
    my ($n) = @_;
    if (my $o = dziecko($n, 'obb2')) {
        my @c = liczby(dziecko($o, 'center') || ['', 0, 0]);
        my @e = liczby(dziecko($o, 'extent') || ['', 0, 0]);
        my @a = liczby(dziecko($o, 'axis') || ['', 1, 0]);
        my $l = sqrt($a[0] ** 2 + $a[1] ** 2) || 1;
        my @u = ($a[0] / $l, $a[1] / $l);
        my @v = (-$u[1], $u[0]);
        return { typ => 'obb2', c => \@c, e => \@e, a => \@u,
                 pkt => [map { [$c[0] + $_->[0] * $e[0] * $u[0] + $_->[1] * $e[1] * $v[0], $c[1] + $_->[0] * $e[0] * $u[1] + $_->[1] * $e[1] * $v[1]] } ([-1, -1], [1, -1], [1, 1], [-1, 1])] };
    }
    if (my $p = dziecko($n, 'polygon2')) {
        my @v = liczby($p);
        my @pk;
        push @pk, [splice(@v, 0, 2)] while @v >= 2;
        return { typ => 'polygon2', pkt => \@pk };
    }
    if (my $c = dziecko($n, 'circle2')) {
        my @c = liczby(dziecko($c, 'center') || ['', 0, 0]);
        my ($r) = liczby(dziecko($c, 'radius') || ['', 1]);
        return { typ => 'circle2', c => \@c, r => $r, pkt => [map { [$c[0] + $r * cos($_ * 3.14159265 / 12), $c[1] + $r * sin($_ * 3.14159265 / 12)] } 0 .. 23] };
    }
    return undef;
}

# ------------------------------------------------------------------ scena
# instancja: {model, W, nazwa, nr, opcje}
my @INST;
my $TYTUL;

sub transform_instancji {
    my (%a) = @_;
    my $kat = ($a{obr} // 0) * 3.14159265358979 / 180;
    my @s = ref $a{skala} ? @{ $a{skala} } : (($a{skala} // 1) x 3);
    my ($c, $s) = (cos $kat, sin $kat);
    my $R = [[$c * $s[0], $s * $s[0], 0], [-$s * $s[1], $c * $s[1], 0], [0, 0, $s[2]]];
    return [$R, [$a{x} // 0, $a{y} // 0, $a{z} // 0]];
}

sub wczytaj_zlozenie {
    my ($plik) = @_;
    open my $fh, '<:encoding(UTF-8)', $plik or die "nie moge otworzyc $plik: $!\n";
    my $nr = 0;
    while (my $w = <$fh>) {
        $w =~ s/\s+#.*$//;
        $w =~ s/^\s*#.*$//;
        $w =~ s/^\s+|\s+$//g;
        next unless length $w;
        my ($k, $reszta) = split ' ', $w, 2;
        if (lc $k eq 'tytul') { $TYTUL = $reszta; next }
        if ($k =~ /^(siatka|kosci|bryly|przeszkody|szer|elewacja|przekroj)$/i) { $O{ lc $k } //= $reszta; next }
        if (lc $k eq 'bez') { push @bez, $reszta; next }
        my %a;
        my @poz;
        for my $t (split ' ', $reszta // '') {
            if ($t =~ /^(\w+)=(.*)$/) { $a{ lc $1 } = $2 } else { push @poz, $t }
        }
        @a{qw(x y z obr skala)} = map { $a{$_} // shift(@poz) } qw(x y z obr skala);
        $a{skala} = [split /,/, $a{skala}] if defined $a{skala} && $a{skala} =~ /,/;
        $a{skala} = $a{s} if !defined $a{skala} && defined $a{s};
        $nr++;
        my $vp = znajdz_encje($k);
        my $M = laduj_model($vp);
        my $W = transform_instancji(%a);
        my $pa;
        if (defined(my $kt = $a{kotwica})) {    # punkt encji, ktory ma wyladowac w (x, y, z)
            if ($kt =~ /^[-\d.,e+]+$/i) { my @v = split /,/, $kt; $pa = [$v[0] // 0, $v[1] // 0, $v[2] // 0] }
            elsif (my ($ob) = grep { lc $_->{nazwa} eq lc $kt } @{ $M->{przeszkody} }, @{ $M->{obszary} }) {
                my @p = @{ $ob->{ksztalt}{pkt} };
                $pa = [(sum0(map { $_->[0] } @p) / @p), (sum0(map { $_->[1] } @p) / @p), 0];
            }
            elsif (my ($kb) = grep { lc $_->{nazwa} eq lc $kt } @{ $M->{kosci} }) { $pa = $kb->{W}[1] }
            else { die "$plik: kotwica=$kt - nie ma takiej przeszkody/obszaru/kosci w $k\n" }
            my $o = vm3($pa, $W->[0]);
            $W->[1] = [map { $W->[1][$_] - $o->[$_] } 0 .. 2];
        }
        if (my $na = $a{na}) {
            my ($i, $kosc) = $na =~ /^(\d+):(.+)$/ or die "$plik: na=$na - oczekuje nr:kosc\n";
            my $baza = $INST[$i - 1] or die "$plik: na=$na - nie ma instancji $i\n";
            my ($k) = grep { lc $_->{nazwa} eq lc $kosc } @{ $baza->{model}{kosci} };
            die "$plik: instancja $i nie ma kosci '$kosc'\n" unless $k;
            $W = zloz($W, zloz($k->{W}, $baza->{W}));
        }
        push @INST, { model => $M, W => $W, nr => $nr, arg => $k, nazwa => $a{nazwa} // $k, a => \%a, kotwica => $pa };
    }
    die "$plik: brak encji\n" unless @INST;
}

# ------------------------------------------------------------------ font (atlas z ffmpeg + Consolas)
my %FONT;
sub katalog_cache {
    my $d = ($ENV{TMP} && -d '/tmp') ? '/tmp/goh-podglad' : (-d '/tmp' ? '/tmp/goh-podglad' : "$ENV{TEMP}/goh-podglad");
    mkdir $d unless -d $d;
    return $d;
}
sub font {
    my ($S) = @_;
    return $FONT{$S} if $FONT{$S};
    my @zn = ((map { chr } 33 .. 126), split //, 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ°×→←↑↓·±');
    my $cw = int(0.55 * $S + 0.6);
    my $ch = int($S * 1.3) + 1;
    my $base = int($S * 1.0);
    my $kol = 16;
    my $rz = ceil(@zn / $kol);
    my ($W, $H) = ($kol * $cw, $rz * $ch);
    my $dir = katalog_cache();
    my $raw = "$dir/font$S.raw";
    unless (-s $raw && -s $raw == $W * $H) {
        my $ttf = -f '/c/Windows/Fonts/consola.ttf' ? '/c/Windows/Fonts/consola.ttf' : -f 'C:/Windows/Fonts/consola.ttf' ? 'C:/Windows/Fonts/consola.ttf' : die "brak C:/Windows/Fonts/consola.ttf\n";
        unless (-f "$dir/consola.ttf") {
            open my $i, '<:raw', $ttf or die; open my $o, '>:raw', "$dir/consola.ttf" or die; local $/; print {$o} readline($i); close $o;
        }
        my @f;
        for my $k (0 .. $#zn) {
            open my $o, '>:encoding(UTF-8)', "$dir/g$k.txt" or die; print $o $zn[$k]; close $o;
            my ($x, $y) = (($k % $kol) * $cw, int($k / $kol) * $ch + $base);
            push @f, "drawtext=fontfile=consola.ttf:textfile=g$k.txt:expansion=none:fontsize=$S:fontcolor=white:x=$x:y=$y-ascent";
        }
        open my $o, '>', "$dir/vf$S.txt" or die; print $o join(',', @f); close $o;
        my $stary = `pwd`; chomp $stary;
        chdir $dir or die;
        system('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', "color=black:s=${W}x$H", '-frames:v', '1',
               '-/vf', "vf$S.txt", '-f', 'rawvideo', '-pix_fmt', 'gray', "font$S.raw") == 0 or die "ffmpeg nie zrobil atlasu fontu\n";
        chdir $stary;
    }
    open my $fh, '<:raw', $raw or die;
    local $/;
    my $d = <$fh>;
    my %g;
    for my $k (0 .. $#zn) {
        my ($x0, $y0) = (($k % $kol) * $cw, int($k / $kol) * $ch);
        $g{ $zn[$k] } = [map { [unpack 'C*', substr($d, ($y0 + $_) * $W + $x0, $cw)] } 0 .. $ch - 1];
    }
    return $FONT{$S} = { cw => $cw, ch => $ch, g => \%g };
}

# ------------------------------------------------------------------ obraz (tablica 0xRRGGBB)
sub nowy_obraz { my ($w, $h, $kol) = @_; return { w => $w, h => $h, p => [($kol) x ($w * $h)] } }
sub mieszaj {
    my ($c, $k, $a) = @_;
    my ($r, $g, $b) = (($c >> 16) & 255, ($c >> 8) & 255, $c & 255);
    return (int($r + ($k->[0] - $r) * $a) << 16) | (int($g + ($k->[1] - $g) * $a) << 8) | int($b + ($k->[2] - $b) * $a);
}
sub tekst {
    my ($img, $x, $y, $s, $kol, %o) = @_;    # x,y = lewy gorny rog
    my $F = font($o{rozmiar} // 14);
    my ($cw, $ch) = @$F{qw(cw ch)};
    my $tlo = $o{obwodka} // [255, 255, 255];
    my @zn = split //, $s;
    my $p = $img->{p};
    my ($W, $H) = @$img{qw(w h)};
    for my $faza ($o{bez_obwodki} ? (1) : (0, 1)) {
        my $cx = $x;
        for my $z (@zn) {
            my $g = $F->{g}{$z};
            if ($g) {
                for my $gy (0 .. $ch - 1) {
                    my $row = $g->[$gy];
                    for my $gx (0 .. $cw - 1) {
                        my $a = $row->[$gx] or next;
                        if ($faza == 0) {
                            for my $d ([-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, 1], [-1, 1], [1, -1]) {
                                my ($px, $py) = ($cx + $gx + $d->[0], $y + $gy + $d->[1]);
                                next if $px < 0 || $py < 0 || $px >= $W || $py >= $H;
                                $p->[$py * $W + $px] = mieszaj($p->[$py * $W + $px], $tlo, $a / 255 * 0.85);
                            }
                        } else {
                            my ($px, $py) = ($cx + $gx, $y + $gy);
                            next if $px < 0 || $py < 0 || $px >= $W || $py >= $H;
                            $p->[$py * $W + $px] = mieszaj($p->[$py * $W + $px], $kol, $a / 255);
                        }
                    }
                }
            }
            $cx += $cw;
        }
    }
    return length($s) * $cw;
}
sub szer_tekstu { my ($s, $r) = @_; return length($s) * font($r // 14)->{cw} }
sub prostokat {
    my ($img, $x0, $y0, $x1, $y1, $kol, $a) = @_;
    for my $y ($y0 < 0 ? 0 : $y0 .. ($y1 >= $img->{h} ? $img->{h} - 1 : $y1)) {
        for my $x ($x0 < 0 ? 0 : $x0 .. ($x1 >= $img->{w} ? $img->{w} - 1 : $x1)) {
            my $i = $y * $img->{w} + $x;
            $img->{p}[$i] = defined $a ? mieszaj($img->{p}[$i], $kol, $a) : ($kol->[0] << 16 | $kol->[1] << 8 | $kol->[2]);
        }
    }
}
sub zapisz_png {
    my ($f, $img) = @_;
    my ($w, $h, $p) = @$img{qw(w h p)};
    my $raw = '';
    for my $y (0 .. $h - 1) {
        $raw .= "\0" . pack('C*', map { (($_ >> 16) & 255, ($_ >> 8) & 255, $_ & 255) } @$p[$y * $w .. $y * $w + $w - 1]);
    }
    my $chunk = sub { my ($t, $d) = @_; return pack('N', length $d) . $t . $d . pack('N', Compress::Zlib::crc32($t . $d)) };
    open my $fh, '>:raw', $f or die "nie moge zapisac $f: $!\n";
    print $fh "\x89PNG\r\n\x1a\n", $chunk->('IHDR', pack('NNCCCCC', $w, $h, 8, 2, 0, 0, 0)),
              $chunk->('IDAT', Compress::Zlib::compress($raw, 6)), $chunk->('IEND', '');
    close $fh;
}

# ------------------------------------------------------------------ geometria sceny
my (@TRI, @LIN, @ZNACZ, $BB);   # trojkaty w ukladzie silnika; linie nakladek; znaczniki kosci
sub bb_dodaj { my ($p) = @_; $BB //= [[@$p], [@$p]]; for (0 .. 2) { $BB->[0][$_] = $p->[$_] if $p->[$_] < $BB->[0][$_]; $BB->[1][$_] = $p->[$_] if $p->[$_] > $BB->[1][$_] } }

my @OPIS;    # wiersze legendy
sub fmt { my $v = sprintf '%.1f', $_[0]; $v =~ s/\.0$//; $v = '0' if $v eq '-0'; return $v }
sub fmtp { return '(' . join(' ', map { fmt($_) } @{ $_[0] }) . ')' }

sub rozwin_placer {    # encje z {placer}: kosc handlebone encji X ustawiona na kosci linkbone
    my @nowe;
    for my $in (@INST) {
        for my $p (@{ $in->{model}{placer} // [] }) {
            my ($lk) = grep { lc $_->{nazwa} eq lc $p->{link} } @{ $in->{model}{kosci} };
            my $vp = eval { znajdz_encje($p->{encja}) };
            unless ($lk && $vp) { push @OPIS, "placer \"$p->{nazwa}\": $p->{encja} na $p->{link} - " . ($vp ? 'brak kosci' : 'brak encji') . ', nie rysuje'; next }
            my $X = laduj_model($vp);
            my ($hk) = grep { lc $_->{nazwa} eq lc $p->{handle} } @{ $X->{kosci} };
            my $W = zloz(odwrotna($hk ? $hk->{W} : ident()), zloz($lk->{W}, $in->{W}));
            push @nowe, { model => $X, W => $W, nr => "$in->{nr}p", nazwa => $p->{encja}, dziecko => 1,
                          a => { kosci => $O{kosci} // ($p->{handle} ? quotemeta($p->{handle}) : 0), przeszkody => 0, bryly => 0 } };
            push @OPIS, sprintf('placer "%s": %s, kosc %s na %s instancji #%s -> poczatek encji %s%s', $p->{nazwa}, $p->{encja},
                $p->{handle} || '-', $p->{link}, $in->{nr}, fmtp($W->[1]), $hk ? '' : ' (brak handlebone, uchwyt = poczatek)');
        }
    }
    push @INST, @nowe;
}

sub buduj_scene {
    rozwin_placer() unless $O{bez_placer};
    my $jedna = (grep { !$_->{dziecko} } @INST) == 1;
    my $id = 0;
    my %ply_opisane;
    for my $in (@INST) {
        my $M = $in->{model};
        my $o = $in->{a} // {};
        my $pk = $o->{kosci} // $O{kosci} // ($jedna ? 1 : 0);
        my $pb = $o->{bryly} // $O{bryly} // ($jedna ? 1 : 0);
        my $pp = $o->{przeszkody} // $O{przeszkody} // 1;
        my @bezi = (@bez, defined $o->{bez} ? $o->{bez} : ());
        my $pref = $in->{dziecko} ? "$in->{nazwa}: " : $jedna ? '' : "#$in->{nr} ";
        unless ($jedna || $in->{dziecko}) {
            my $a = $in->{a};
            push @OPIS, sprintf('#%d %s  poz %s obr %s skala %s%s  [%s]', $in->{nr}, $in->{nazwa}, fmtp($in->{W}[1]),
                fmt($a->{obr} // 0), ref $a->{skala} ? join(',', @{ $a->{skala} }) : fmt($a->{skala} // 1),
                $a->{na} ? " na $a->{na}" : '', $M->{def} ? basename($M->{def}) : basename($M->{mdl} // $M->{vp}));
        }
        for my $k (@{ $M->{kosci} }) {
            my $W = zloz($k->{W}, $in->{W});
            for my $s (@{ $k->{siatki} }) {
                next if grep { $s->{plik} =~ /$_/i || $k->{nazwa} =~ /$_/i } @bezi;
                my $ply = czytaj_ply($s->{vp}) or next;
                my $v = $ply->{v};
                my @wv;
                for (my $j = 0; $j < @$v; $j += 3) {
                    my $p = tp($W, [$v->[$j], $v->[$j + 1], $v->[$j + 2]]);
                    push @wv, $p;
                    bb_dodaj($p) unless $k->{ukryta};
                }
                $id++;
                for my $ms (@{ $ply->{mesh} }) {
                    my $mat = material($s->{vp}, $ms->{mtl});
                    my $kol = kolor_materialu($mat);
                    my $alfa = $k->{ukryta} ? 0.30 : $mat->{blend} eq 'test' ? 0.55 : $mat->{blend} eq 'blend' ? 0.75 : 1;
                    my $idx = $ply->{i};
                    for my $t ($ms->{ff} .. $ms->{ff} + $ms->{fc} - 1) {
                        my @p = map { $wv[ $idx->[3 * $t + $_] // 0 ] } 0 .. 2;
                        next if grep { !defined } @p;
                        push @TRI, [@p, $kol, $alfa, $id];
                    }
                }
                unless ($in->{dziecko} || $ply_opisane{ $s->{vp} }++) {
                    my $b = $ply->{bnds};
                    push @OPIS, sprintf('%s%s (kosc %s%s): BNDS x %s..%s y %s..%s z %s..%s, %d trojk., %s', $pref, $s->{plik}, $k->{nazwa},
                        ($k->{ukryta} ? ', visibility 0' : '') . ($s->{ground} ? ', {Ground}' : ''), map({ fmt($_) } @$b[0, 3, 1, 4, 2, 5]),
                        int(@{ $ply->{i} } / 3), join('+', map { $_->{mtl} . (material($s->{vp}, $_->{mtl})->{blend} ne 'none' ? '(' . material($s->{vp}, $_->{mtl})->{blend} . ')' : '') } @{ $ply->{mesh} })) if $b;
                }
            }
            if ($pk && ($pk =~ /^[01]$/ || $k->{nazwa} =~ /$pk/i)) {
                my $poz = $W->[1];
                push @ZNACZ, { p => $poz, nazwa => $pref . $k->{nazwa}, W => $W, pusta => !@{ $k->{siatki} } };
                bb_dodaj($poz);
                push @OPIS, sprintf('%skosc %s%s: %s%s', $pref, $k->{nazwa}, $k->{rodzic} ? " (w $k->{rodzic})" : '', fmtp($poz),
                    defined $k->{param} ? "  \"$k->{param}\"" : '') if $jedna || !@{ $k->{siatki} };
            }
        }
        if ($pp) {
            for my $grupa (['przeszkody', [200, 30, 30], 0], ['obszary', [30, 70, 200], 1]) {
                my ($kl, $kol, $kreski) = @$grupa;
                for my $ob (@{ $M->{$kl} }) {
                    my @pk = map { tp($in->{W}, [$_->[0], $_->[1], 0]) } @{ $ob->{ksztalt}{pkt} };
                    for my $j (0 .. $#pk) { push @LIN, { a => $pk[$j], b => $pk[ ($j + 1) % @pk ], kol => $kol, gr => 2, kreski => $kreski, typ => 'ob' } }
                    bb_dodaj($_) for @pk;
                    my $ks = $ob->{ksztalt};
                    push @OPIS, sprintf('%s%s "%s": %s%s', $pref, $kl eq 'przeszkody' ? 'przeszkoda' : 'obszar', $ob->{nazwa},
                        $ks->{typ} eq 'obb2' ? sprintf('srodek %s polowki %s os %s', fmtp($ks->{c}), fmtp($ks->{e}), fmtp($ks->{a}))
                        : $ks->{typ} eq 'circle2' ? sprintf('kolo %s r %s', fmtp($ks->{c}), fmt($ks->{r})) : scalar(@{ $ks->{pkt} }) . ' pkt',
                        $ob->{tags} ? "  [$ob->{tags}]" : '') if $jedna;
                }
            }
        }
        if ($pb) {
            for my $b (@{ $M->{bryly} }) {
                my $W = zloz($b->{W}, $in->{W});
                if ($b->{box}) {
                    my ($sx, $sy, $sz) = map { $_ / 2 } @{ $b->{box} };
                    my @r = map { my $c = $_; tp($W, [($c & 1 ? 1 : -1) * $sx, ($c & 2 ? 1 : -1) * $sy, ($c & 4 ? 1 : -1) * $sz]) } 0 .. 7;
                    for my $e ([0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]) {
                        push @LIN, { a => $r[ $e->[0] ], b => $r[ $e->[1] ], kol => [230, 130, 0], gr => 1, alfa => 0.8, typ => 'bryla' };
                    }
                }
                push @OPIS, sprintf('%sbryla "%s" (kosc %s): %s%s', $pref, $b->{nazwa}, $b->{kosc} || '-', fmtp($W->[1]),
                    $b->{box} ? ' box ' . join('x', map { fmt($_) } @{ $b->{box} }) : $b->{poly} ? " polyhedron $b->{poly} (nie rysuje)" : '') if $jedna;
            }
        }
    }
    die "nic do narysowania\n" unless $BB;
}

# ------------------------------------------------------------------ rzutowanie i rasteryzacja
# Uklad renderu = (x, -y, z): prawoskretny, zeby obraz nie byl lustrem.
sub norm3 { my ($v) = @_; my $l = sqrt($v->[0] ** 2 + $v->[1] ** 2 + $v->[2] ** 2) || 1; return [map { $_ / $l } @$v] }
sub kamera {
    my ($typ, $az, $el) = @_;
    return { r => [1, 0, 0], u => [0, 1, 0], f => [0, 0, -1] } if $typ eq 'gora';
    if ($typ eq 'przod') {    # $az = strona obserwatora w ukladzie silnika: +y -y +x -x
        my %f = ('+y' => [0, 1, 0], '-y' => [0, -1, 0], '+x' => [-1, 0, 0], '-x' => [1, 0, 0]);
        my $f = $f{$az} or die "--elewacja: +y, -y, +x albo -x\n";
        return { r => [$f->[1], -$f->[0], 0], u => [0, 0, 1], f => $f };
    }
    my ($a, $e) = map { $_ * 3.14159265358979 / 180 } ($az, $el);
    my $d = [cos($e) * cos($a), cos($e) * sin($a), sin($e)];    # od celu do obserwatora (uklad renderu)
    my $f = [map { -$_ } @$d];
    my $r = norm3([$f->[1], -$f->[0], 0]);
    my $u = [$r->[1] * $f->[2] - $r->[2] * $f->[1], $r->[2] * $f->[0] - $r->[0] * $f->[2], $r->[0] * $f->[1] - $r->[1] * $f->[0]];
    return { r => $r, u => $u, f => $f };
}
sub rzut2 {    # punkt silnika -> (x, y, glebokosc) w jednostkach swiata
    my ($k, $p) = @_;
    my @q = ($p->[0], -$p->[1], $p->[2]);
    return ($q[0] * $k->{r}[0] + $q[1] * $k->{r}[1] + $q[2] * $k->{r}[2],
            $q[0] * $k->{u}[0] + $q[1] * $k->{u}[1] + $q[2] * $k->{u}[2],
            $q[0] * $k->{f}[0] + $q[1] * $k->{f}[1] + $q[2] * $k->{f}[2]);
}

sub krok_siatki {
    my ($zakres) = @_;
    return $O{siatka} if $O{siatka};
    my $s = $zakres / 12;
    my $p = 10 ** floor(log($s) / log(10));
    for my $m (1, 2, 2.5, 5, 10) { return $m * $p if $m * $p >= $s }
}

sub rysuj_panel {
    my ($P) = @_;    # {typ, az, el, w, h, skala (opcjonalnie), tytul}
    my $ss = $O{ss};
    my $K = kamera($P->{typ}, $P->{az} // 0, $P->{el} // 0);
    my ($W, $H) = ($P->{w} * $ss, $P->{h} * $ss);
    my ($ml, $mr, $mt, $mb) = $P->{typ} =~ /gora|przod/ ? (48, 14, 26, 26) : (14, 14, 26, 14);
    # zakres w rzucie
    my @c = map { [$BB->[$_ & 1][0], $BB->[($_ >> 1) & 1][1], $BB->[($_ >> 2) & 1][2]] } 0 .. 7;
    my ($x0, $x1, $y0, $y1) = (1e30, -1e30, 1e30, -1e30);
    my $krok = $P->{krok};
    if ($P->{typ} !~ /gora|przod/) {    # siatka na z=0 tez ma sie zmiescic
        push @c, map { [$_->[0], $_->[1], 0] } @c;
    }
    for (@c) { my ($x, $y) = rzut2($K, $_); $x0 = $x if $x < $x0; $x1 = $x if $x > $x1; $y0 = $y if $y < $y0; $y1 = $y if $y > $y1 }
    my $sk = $P->{skala} // do { my $a = ($P->{w} - $ml - $mr) / (($x1 - $x0) || 1); my $b = ($P->{h} - $mt - $mb) / (($y1 - $y0) || 1); $a < $b ? $a : $b };
    $P->{skala_wyl} = $sk;
    my $S = $sk * $ss;
    my $ox = ($ml + ($P->{w} - $ml - $mr - ($x1 - $x0) * $sk) / 2) * $ss - $x0 * $S;
    my $oy = ($mt + ($P->{h} - $mt - $mb - ($y1 - $y0) * $sk) / 2) * $ss + $y1 * $S;
    my $proj = sub { my ($x, $y, $d) = rzut2($K, $_[0]); return ($x * $S + $ox, $oy - $y * $S, $d) };
    $P->{proj} = sub { my ($x, $y, $d) = $proj->($_[0]); return ($x / $ss, $y / $ss, $d) };

    my $N = $W * $H;
    my @col = (0xEEF0F3) x $N;
    my @dep = (1e30) x $N;
    my @id = (0) x $N;
    my $L = norm3([-0.35, 0.45, 0.82]);    # swiatlo w ukladzie renderu
    my ($zmin, $zmax) = ($BB->[0][2], $BB->[1][2]);
    my $zr = ($zmax - $zmin) || 1;

    my $raster = sub {
        my ($t, $a) = @_;
        my @s = map { [$proj->($_)] } @$t[0 .. 2];
        my ($ax, $ay, $az) = @{ $s[0] };
        my ($bx, $by, $bz) = @{ $s[1] };
        my ($cx, $cy, $cz) = @{ $s[2] };
        my $area = ($bx - $ax) * ($cy - $ay) - ($cx - $ax) * ($by - $ay);
        return if abs($area) < 1e-12;
        # cieniowanie plaskie z normalnej w ukladzie renderu
        my @q = map { [$_->[0], -$_->[1], $_->[2]] } @$t[0 .. 2];
        my @u = map { $q[1][$_] - $q[0][$_] } 0 .. 2;
        my @v = map { $q[2][$_] - $q[0][$_] } 0 .. 2;
        my $n = norm3([$u[1] * $v[2] - $u[2] * $v[1], $u[2] * $v[0] - $u[0] * $v[2], $u[0] * $v[1] - $u[1] * $v[0]]);
        my $sw = abs($n->[0] * $L->[0] + $n->[1] * $L->[1] + $n->[2] * $L->[2]);
        my $jas = 0.42 + 0.58 * $sw;
        if ($P->{typ} eq 'gora') { my $zs = ($t->[0][2] + $t->[1][2] + $t->[2][2]) / 3; $jas *= 0.70 + 0.30 * ($zs - $zmin) / $zr }
        my $k = $t->[3];
        my $pc = ((int(($k->[0] * $jas) > 255 ? 255 : $k->[0] * $jas)) << 16) | ((int(($k->[1] * $jas) > 255 ? 255 : $k->[1] * $jas)) << 8) | int(($k->[2] * $jas) > 255 ? 255 : $k->[2] * $jas);
        my @pk = ([$k->[0] * $jas, $k->[1] * $jas, $k->[2] * $jas]);
        my $dzdx = (($bz - $az) * ($cy - $ay) - ($cz - $az) * ($by - $ay)) / $area;
        my $dzdy = (($cz - $az) * ($bx - $ax) - ($bz - $az) * ($cx - $ax)) / $area;
        my $ymin = $ay < $by ? ($ay < $cy ? $ay : $cy) : ($by < $cy ? $by : $cy);
        my $ymax = $ay > $by ? ($ay > $cy ? $ay : $cy) : ($by > $cy ? $by : $cy);
        my $ya = ceil($ymin - 0.5); $ya = 0 if $ya < 0;
        my $yb = floor($ymax - 0.5); $yb = $H - 1 if $yb > $H - 1;
        my @kr = ([$ax, $ay, $bx, $by], [$bx, $by, $cx, $cy], [$cx, $cy, $ax, $ay]);
        my $id = $t->[5];
        for my $y ($ya .. $yb) {
            my $py = $y + 0.5;
            my ($xl, $xr) = (1e30, -1e30);
            for my $e (@kr) {
                my ($x1, $y1, $x2, $y2) = @$e;
                next if ($py < $y1 && $py < $y2) || ($py > $y1 && $py > $y2) || $y1 == $y2;
                my $x = $x1 + ($py - $y1) * ($x2 - $x1) / ($y2 - $y1);
                $xl = $x if $x < $xl;
                $xr = $x if $x > $xr;
            }
            next if $xl > $xr;
            my $xa = ceil($xl - 0.5); $xa = 0 if $xa < 0;
            my $xb = floor($xr - 0.5); $xb = $W - 1 if $xb > $W - 1;
            next if $xa > $xb;
            my $z = $az + $dzdx * ($xa + 0.5 - $ax) + $dzdy * ($py - $ay);
            my $i = $y * $W + $xa;
            if ($a >= 1) {
                for my $x ($xa .. $xb) {
                    if ($z < $dep[$i]) { $dep[$i] = $z; $col[$i] = $pc; $id[$i] = $id }
                    $z += $dzdx; $i++;
                }
            } else {
                for my $x ($xa .. $xb) {
                    $col[$i] = mieszaj($col[$i], $pk[0], $a) if $z < $dep[$i] - 0.05;
                    $z += $dzdx; $i++;
                }
            }
        }
    };
    my @tri = @TRI;
    if ($P->{typ} eq 'przod' && defined $O{przekroj}) {    # wytnij to, co przed plaszczyzna (od strony patrzacego)
        my ($zn, $os) = $P->{az} =~ /^([-+])([xy])$/;
        my $i = $os eq 'x' ? 0 : 1;
        my $v = $O{przekroj};
        @tri = $zn eq '+' ? grep { $_->[0][$i] <= $v || $_->[1][$i] <= $v || $_->[2][$i] <= $v } @tri
                          : grep { $_->[0][$i] >= $v || $_->[1][$i] >= $v || $_->[2][$i] >= $v } @tri;
    }
    $raster->($_, 1) for grep { $_->[4] >= 1 } @tri;

    # krawedzie: skok glebokosci albo zmiana obiektu
    my $prog = (($BB->[1][0] - $BB->[0][0]) + ($BB->[1][1] - $BB->[0][1]) + ($BB->[1][2] - $BB->[0][2])) / 3 * 0.02;
    $prog = 0.8 if $prog < 0.8;
    my @kraw;
    for my $y (0 .. $H - 2) {
        my $i = $y * $W;
        for my $x (0 .. $W - 2) {
            my $d = $dep[$i];
            my ($dr, $dd) = ($dep[$i + 1], $dep[$i + $W]);
            if ($d < 1e29 || $dr < 1e29 || $dd < 1e29) {
                if (abs($d - $dr) > $prog || abs($d - $dd) > $prog || $id[$i] != $id[$i + 1] || $id[$i] != $id[$i + $W]) {
                    my $j = $d <= $dr && $d <= $dd ? $i : $dr < $dd ? $i + 1 : $i + $W;
                    push @kraw, $j;
                }
            }
            $i++;
        }
    }
    for my $j (@kraw) { my $c = $col[$j]; $col[$j] = ((int((($c >> 16) & 255) * 0.45)) << 16) | ((int((($c >> 8) & 255) * 0.45)) << 8) | int(($c & 255) * 0.45) }

    # przezroczyste: od najdalszych
    my @pz = sort { $b->[1] <=> $a->[1] } map { my $t = $_; [$t, ((rzut2($K, $t->[0]))[2] + (rzut2($K, $t->[1]))[2] + (rzut2($K, $t->[2]))[2]) / 3] } grep { $_->[4] < 1 } @tri;
    $raster->($_->[0], $_->[0][4]) for @pz;

    # linie: stemplowanie kwadratow; test glebokosci opcjonalny
    my $linia = sub {
        my ($a, $b, $kol, $gr, $alfa, $test, $kreski) = @_;
        my ($xa, $ya, $za) = $proj->($a);
        my ($xb, $yb, $zb) = $proj->($b);
        my $len = sqrt(($xb - $xa) ** 2 + ($yb - $ya) ** 2);
        my $n = int($len / 0.7) + 1;
        my $r = $gr * $ss / 2;
        my $r0 = floor(-$r + 0.5);
        my $r1 = $r0 + int($gr * $ss) - 1;
        $r1 = $r0 if $r1 < $r0;
        my %bylo;
        for my $k (0 .. $n) {
            my $f = $k / $n;
            next if $kreski && (int($f * $len / (7 * $ss)) % 2);
            my $x = int($xa + ($xb - $xa) * $f);
            my $y = int($ya + ($yb - $ya) * $f);
            my $z = $za + ($zb - $za) * $f;
            for my $dy ($r0 .. $r1) {
                my $yy = $y + $dy;
                next if $yy < 0 || $yy >= $H;
                for my $dx ($r0 .. $r1) {
                    my $xx = $x + $dx;
                    next if $xx < 0 || $xx >= $W;
                    my $i = $yy * $W + $xx;
                    next if $bylo{$i}++;
                    next if $test && $z > $dep[$i] + $prog * 0.5;
                    $col[$i] = mieszaj($col[$i], $kol, $alfa);
                }
            }
        }
    };

    # siatka
    my $g0 = [map { floor($BB->[0][$_] / $krok) * $krok } 0 .. 2];
    my $g1 = [map { ceil($BB->[1][$_] / $krok) * $krok } 0 .. 2];
    my @etyk;    # [x, y, tekst, wyrownanie]
    if ($P->{typ} eq 'gora') {
        for (my $x = $g0->[0]; $x <= $g1->[0] + 1e-6; $x += $krok) {
            my $os = abs($x) < 1e-6;
            $linia->([$x, $g0->[1], 0], [$x, $g1->[1], 0], [40, 50, 70], $os ? 1.5 : 1, $os ? 0.55 : 0.22, 0);
            push @etyk, [$x, $g1->[1], fmt($x), 'dol'];
        }
        for (my $y = $g0->[1]; $y <= $g1->[1] + 1e-6; $y += $krok) {
            my $os = abs($y) < 1e-6;
            $linia->([$g0->[0], $y, 0], [$g1->[0], $y, 0], [40, 50, 70], $os ? 1.5 : 1, $os ? 0.55 : 0.22, 0);
            push @etyk, [$g0->[0], $y, fmt($y), 'lewo'];
        }
    } elsif ($P->{typ} eq 'przod') {
        my $h = $P->{az} =~ /y/ ? 0 : 1;    # os pozioma obrazu (x albo y silnika)
        my $pt = sub { my ($a, $z) = @_; my @p = (0, 0, $z); $p[$h] = $a; return \@p };
        for (my $a = $g0->[$h]; $a <= $g1->[$h] + 1e-6; $a += $krok) {
            $linia->($pt->($a, $g0->[2]), $pt->($a, $g1->[2]), [40, 50, 70], abs($a) < 1e-6 ? 1.5 : 1, abs($a) < 1e-6 ? 0.5 : 0.2, 0);
            push @etyk, [@{ $pt->($a, $g0->[2]) }[0, 1], fmt($a), 'dolz', $g0->[2]];
        }
        my ($l, $p) = ($g0->[$h], $g1->[$h]);
        ($l, $p) = ($p, $l) if ((rzut2($K, $pt->($p, 0)))[0] < (rzut2($K, $pt->($l, 0)))[0]);
        for (my $z = $g0->[2]; $z <= $g1->[2] + 1e-6; $z += $krok) {
            my $zero = abs($z) < 1e-6;
            $linia->($pt->($g0->[$h], $z), $pt->($g1->[$h], $z), $zero ? [20, 120, 40] : [40, 50, 70], $zero ? 2 : 1, $zero ? 0.75 : 0.2, 0);
            push @etyk, [@{ $pt->($l, $z) }[0, 1], fmt($z), 'lewoz', $z];
        }
    } else {
        for (my $x = $g0->[0]; $x <= $g1->[0] + 1e-6; $x += $krok) {
            $linia->([$x, $g0->[1], 0], [$x, $g1->[1], 0], [40, 50, 70], abs($x) < 1e-6 ? 1.5 : 1, abs($x) < 1e-6 ? 0.55 : 0.25, 1);
        }
        for (my $y = $g0->[1]; $y <= $g1->[1] + 1e-6; $y += $krok) {
            $linia->([$g0->[0], $y, 0], [$g1->[0], $y, 0], [40, 50, 70], abs($y) < 1e-6 ? 1.5 : 1, abs($y) < 1e-6 ? 0.55 : 0.25, 1);
        }
        my $dl = $krok * 2;
        $linia->([0, 0, 0], [$dl, 0, 0], [210, 40, 40], 2, 0.9, 0);
        $linia->([0, 0, 0], [0, $dl, 0], [30, 150, 40], 2, 0.9, 0);
        $linia->([0, 0, 0], [0, 0, $dl], [40, 70, 220], 2, 0.9, 0);
        push @etyk, [$dl * 1.08, 0, '+x', 'os', 0, [210, 40, 40]], [0, $dl * 1.08, '+y', 'os', 0, [30, 150, 40]], [0, 0, '+z', 'os', $dl * 1.08, [40, 70, 220]];
    }

    # nakladki (przeszkody, bryly) - zawsze widoczne
    for my $l (@LIN) {
        next if $P->{typ} eq 'przod' && $l->{typ} eq 'ob';
        $linia->($l->{a}, $l->{b}, $l->{kol}, $l->{gr}, $l->{alfa} // 0.9, 0, $l->{kreski});
    }
    # osie kosci bez siatki (punkty zaczepienia)
    my $dlo = $krok * 0.8;
    for my $z (grep { $_->{pusta} } @ZNACZ) {
        my $R = $z->{W}[0];
        my $p = $z->{p};
        $linia->($p, [map { $p->[$_] + $R->[0][$_] * $dlo } 0 .. 2], [220, 40, 40], 1.5, 0.9, 0);
        $linia->($p, [map { $p->[$_] + $R->[1][$_] * $dlo } 0 .. 2], [30, 160, 40], 1.5, 0.9, 0);
    }

    # zmniejszenie
    my ($w, $h) = ($P->{w}, $P->{h});
    my $img = { w => $w, h => $h, p => [] };
    my $q = $ss * $ss;
    for my $y (0 .. $h - 1) {
        for my $x (0 .. $w - 1) {
            my ($r, $g, $b) = (0, 0, 0);
            for my $dy (0 .. $ss - 1) {
                my $i = ($y * $ss + $dy) * $W + $x * $ss;
                for (0 .. $ss - 1) { my $c = $col[$i++]; $r += ($c >> 16) & 255; $g += ($c >> 8) & 255; $b += $c & 255 }
            }
            $img->{p}[$y * $w + $x] = (int($r / $q) << 16) | (int($g / $q) << 8) | int($b / $q);
        }
    }
    undef @col; undef @dep; undef @id;

    # etykiety siatki
    my $pp = $P->{proj};
    for my $e (@etyk) {
        my ($wx, $wy, $t, $wyr, $wz, $kol) = @$e;
        my ($x, $y) = $pp->([$wx, $wy, $wz // 0]);
        my $tw = szer_tekstu($t, 12);
        if ($wyr eq 'dol' || $wyr eq 'dolz') {
            next if $x < $ml - 4 || $x > $w - 6;
            tekst($img, int($x - $tw / 2), $h - $mb + 6, $t, [60, 66, 80], rozmiar => 12, bez_obwodki => 1);
        } elsif ($wyr eq 'lewo' || $wyr eq 'lewoz') {
            next if $y < $mt + 4 || $y > $h - $mb - 4;
            tekst($img, $ml - $tw - 6, int($y - 8), $t, [60, 66, 80], rozmiar => 12, bez_obwodki => 1);
        } else { tekst($img, int($x - $tw / 2), int($y - 8), $t, $kol, rozmiar => 14) }
    }
    # znaczniki kosci (zgrupowane w tym samym miejscu ekranu)
    my @grupy;
    for my $z (@ZNACZ) {
        my ($x, $y) = $pp->($z->{p});
        my ($g) = grep { abs($_->{x} - $x) < 5 && abs($_->{y} - $y) < 5 } @grupy;
        if ($g) { push @{ $g->{n} }, $z->{nazwa} } else { push @grupy, { x => $x, y => $y, n => [$z->{nazwa}] } }
    }
    my @zajete;
    for my $g (@grupy) {
        my ($x, $y) = (int($g->{x} + 0.5), int($g->{y} + 0.5));
        for my $d (-3 .. 3) { for my $e (-3 .. 3) { next if abs($d) + abs($e) > 3; my ($xx, $yy) = ($x + $d, $y + $e); next if $xx < 0 || $yy < 0 || $xx >= $w || $yy >= $h; $img->{p}[$yy * $w + $xx] = abs($d) + abs($e) == 3 ? 0xFFFFFF : 0xB01890 } }
        my $t = join ', ', @{ $g->{n} };
        my $tw = szer_tekstu($t, 13);
        my ($tx, $ty) = ($x + 6, $y - 8);
        $tx = $x - 6 - $tw if $tx + $tw > $w - 2;
        my $ty0 = $ty;
        for (1 .. 8) {
            last unless grep { $tx < $_->[2] && $tx + $tw > $_->[0] && $ty < $_->[3] && $ty + 16 > $_->[1] } @zajete;
            $ty += 15;
        }
        push @zajete, [$tx, $ty, $tx + $tw, $ty + 16];
        if ($ty != $ty0) {    # etykieta odsunieta - kreska do znacznika
            my ($lx, $ly) = ($tx < $x ? $tx + $tw : $tx - 1, $ty + 8);
            my $n = int(abs($ly - $y) + abs($lx - $x)) + 1;
            for my $k (0 .. $n) {
                my ($px, $py) = (int($x + ($lx - $x) * $k / $n), int($y + ($ly - $y) * $k / $n));
                next if $px < 0 || $py < 0 || $px >= $w || $py >= $h;
                $img->{p}[$py * $w + $px] = mieszaj($img->{p}[$py * $w + $px], [140, 10, 110], 0.7);
            }
        }
        tekst($img, $tx, $ty, $t, [140, 10, 110], rozmiar => 13);
    }
    # numery instancji w widoku z gory
    if ((grep { !$_->{dziecko} } @INST) > 1 && $P->{typ} eq q{gora}) {
        for my $in (grep { !$_->{dziecko} } @INST) {
            my ($x, $y) = $pp->(tp($in->{W}, $in->{kotwica} // [0, 0, 0]));
            tekst($img, int($x - 8), int($y - 9), "#$in->{nr}", [10, 30, 160], rozmiar => 15);
        }
    }
    # tytul panelu i ramka
    tekst($img, 8, 5, $P->{tytul}, [20, 24, 32], rozmiar => 15);
    for my $x (0 .. $w - 1) { $img->{p}[$x] = $img->{p}[($h - 1) * $w + $x] = 0xA0A6B0 }
    for my $y (0 .. $h - 1) { $img->{p}[$y * $w] = $img->{p}[$y * $w + $w - 1] = 0xA0A6B0 }
    return $img;
}

sub wklej {
    my ($dst, $src, $x0, $y0) = @_;
    for my $y (0 .. $src->{h} - 1) {
        my $d = ($y0 + $y) * $dst->{w} + $x0;
        @{ $dst->{p} }[$d .. $d + $src->{w} - 1] = @{ $src->{p} }[$y * $src->{w} .. ($y + 1) * $src->{w} - 1];
    }
}

# ------------------------------------------------------------------ main
if (defined $O{szukaj}) {
    laduj_zrodla();
    my $n = 0;
    for my $k (sort keys %IDX) { next unless $k =~ /$O{szukaj}/i; print "$k   [", basename($IDX{$k}[0]{nazwa}), "]\n"; last if ++$n >= 400 }
    exit 0;
}
if (defined $O{pokaz}) {
    my $vp = znajdz_encje($O{pokaz});
    my $d = czytaj($vp) // die "nie ma $O{pokaz}\n";
    binmode STDOUT, ':raw';
    print $d;
    exit 0;
}

if ($O{zlozenie}) {
    laduj_zrodla();
    wczytaj_zlozenie($O{zlozenie});
    $TYTUL //= basename($O{zlozenie});
} else {
    die "uzycie: perl podglad.pl <encja> [-o plik.png] | --zlozenie plik.txt | --info <encja> | --szukaj <regex>\n" unless @args;
    my $vp = znajdz_encje($args[0]);
    laduj_zrodla() if $vp =~ /^plik:/;
    push @INST, { model => laduj_model($vp), W => ident(), nr => 1, arg => $args[0], nazwa => $args[0], a => {} };
    my $M = $INST[0]{model};
    $TYTUL = ($vp =~ s/^\w+://r) . '  [' . skad($vp) . ']';
}
$TYTUL = $O{tytul} if defined $O{tytul};
buduj_scene();
my $zak = (sort { $b <=> $a } map { $BB->[1][$_] - $BB->[0][$_] } 0 .. 2)[0] || 1;
my $krok = krok_siatki($zak);
unshift @OPIS, sprintf('obrys sceny: x %s..%s  y %s..%s  z %s..%s  (%s x %s x %s j.)', map({ fmt($_) } $BB->[0][0], $BB->[1][0], $BB->[0][1], $BB->[1][1], $BB->[0][2], $BB->[1][2]),
    map { fmt($BB->[1][$_] - $BB->[0][$_]) } 0 .. 2);

print "$TYTUL\n";
print "  $_\n" for @OPIS;
exit 0 if $O{info};

my $FW = $O{szer};
my $ELEW = $O{elewacja} // '+y';
$ELEW = "+$ELEW" if $ELEW =~ /^[xy]$/;
my $gap = 8;
my $pw = int(($FW - 3 * $gap) / 2);
my $ph = int($pw * 0.68);
my @panele = (
    { typ => 'gora', tytul => "z gory (+x w prawo, +y w dol), kratka $krok j." },
    { typ => 'przod', az => $ELEW, tytul => "elewacja od strony $ELEW" . (defined $O{przekroj} ? " (przekroj " . ($ELEW =~ s/^[-+]//r) . "=$O{przekroj})" : '') . ", z w gore, zielona z=0, kratka $krok j." },
    { typ => 'iso', az => 235, el => 32, tytul => 'izometria od strony -x +y (lewy dolny rog widoku z gory)' },
    { typ => 'iso', az => 55, el => 32, tytul => 'izometria od strony +x -y (prawy gorny rog widoku z gory)' },
);
for (@panele) { @$_{qw(w h krok)} = ($pw, $ph, $krok) }
# wspolna skala dla rzutow prostokatnych
{
    my $zx = $BB->[1][0] - $BB->[0][0] || 1;
    my ($zy, $zz) = (($BB->[1][1] - $BB->[0][1]) || 1, ($BB->[1][2] - $BB->[0][2]) || 1);
    my @s = (($pw - 62) / $zx, ($ph - 52) / $zy, ($ph - 52) / $zz, ($pw - 62) / ($ELEW =~ /y/ ? $zx : $zy));
    my $s = (sort { $a <=> $b } @s)[0];
    $panele[0]{skala} = $panele[1]{skala} = $s;
}

my @ld = @OPIS;
my $lh = 16;
my $kolumny = @ld > 14 ? 2 : 1;
my $wiersze = ceil(@ld / $kolumny);
my $naglowek = 34;
my $FH = $naglowek + 2 * $ph + 3 * $gap + $wiersze * $lh + 16;
my $img = nowy_obraz($FW, $FH, 0xFAFAFB);
tekst($img, 10, 7, $TYTUL, [10, 14, 24], rozmiar => 18, bez_obwodki => 1);
my $t1 = time;
for my $i (0 .. 3) {
    my $p = rysuj_panel($panele[$i]);
    wklej($img, $p, $gap + ($i % 2) * ($pw + $gap), $naglowek + int($i / 2) * ($ph + $gap));
}
my $y0 = $naglowek + 2 * ($ph + $gap) + 6;
my $kw = int(($FW - 20) / $kolumny);
my $maxzn = int($kw / font(13)->{cw}) - 1;
for my $j (0 .. $#ld) {
    my $t = $ld[$j];
    $t = substr($t, 0, $maxzn - 1) . '…' if length $t > $maxzn;
    my $k = int($j / $wiersze);
    tekst($img, 10 + $k * $kw, $y0 + ($j % $wiersze) * $lh, $t, [30, 34, 44], rozmiar => 13, bez_obwodki => 1);
}
my $out = $O{o} // do {
    my $cwd = `pwd`; chomp $cwd;
    die "podaj -o (biezacy katalog to katalog gry/moda: $cwd)\n" if $cwd =~ /steamapps|Gates of Hell/i;
    my $n = $O{zlozenie} ? basename($O{zlozenie}) : basename($args[0]);
    $n =~ s/\.\w+$//;
    "podglad-$n.png";
};
die "nie zapisuje w katalogu gry/moda: $out\n" if $out =~ /steamapps/i;
zapisz_png($out, $img);
printf "zapisano %s (%dx%d, %d trojkatow, %.1f s)\n", $out, $FW, $FH, scalar(@TRI), time - $T0;
