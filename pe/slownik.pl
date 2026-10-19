#!/usr/bin/perl
# slownik.pl - wyciaga z binarki GEM2 slownik skladni skryptow.
#
#   perl pe/slownik.pl <exe> tablice            rejestry {nazwa -> klasa} + parametry
#   perl pe/slownik.pl <exe> enumy              tablice nazw zakonczone NULL-em
#   perl pe/slownik.pl <exe> fn <rva> [glebia]  stringi funkcji i jej wywolan
#   perl pe/slownik.pl <exe> gen <katalog>      zapisuje tablice.txt i enumy.txt
#
# Dlaczego osobno od goh.pl: tam skaner stringow ma minimum 4 znaki (gubi "tag",
# "set", "con", "op") i nie czyta tablic wskaznikow ani RTTI. A sedno jest takie,
# ze silnik trzyma rejestry jako tablice par { const char* nazwa, Obiekt* (*fabryka)() }
# w .data. Nazwa nie ma zadnego xrefa w kodzie, wiec "goh.pl xref <nazwa>" jej
# nie znajdzie - trzeba szukac QWORD-a z jej adresem w sekcjach danych.
#
# Lancuch: tablica par -> fabryka -> LEA na vtable -> RTTI przed vtable -> nazwa
# klasy -> metody wirtualne -> stringi w nich = przyjmowane parametry.
#
# OFFSETY NIE PRZENOSZA SIE MIEDZY BUILDAMI. Po update gry puszcza sie to jeszcze
# raz; nic nie jest zapisane na sztywno.

use strict; use warnings;

my ($exe, $cmd, @arg) = @ARGV;
die usage() unless $exe && $cmd;
open(my $fh, '<:raw', $exe) or die "nie moge otworzyc $exe: $!\n";
my $buf = do { local $/; <$fh> }; close $fh;

# ---------- PE ----------
my $lf = unpack('V', substr($buf, 0x3c, 4));
die "to nie jest PE\n" unless substr($buf,$lf,4) eq "PE\0\0";
my $nsec  = unpack('v', substr($buf,$lf+6,2));
my $optsz = unpack('v', substr($buf,$lf+20,2));
my $opt   = $lf + 24;
my $base  = unpack('Q<', substr($buf,$opt+24,8));
my @sec;
for my $i (0..$nsec-1) {
    my $o = $opt + $optsz + $i*40;
    my $n = substr($buf,$o,8); $n =~ s/\0+$//;
    my ($vsz,$va,$rsz,$rp) = unpack('VVVV', substr($buf,$o+8,16));
    push @sec, { n=>$n, vsz=>$vsz, va=>$va, rsz=>$rsz, rp=>$rp };
}
my ($TEXT) = grep { $_->{n} eq '.text' } @sec;

sub sec_of {
    my $r = shift; return undef unless defined $r;
    for (@sec) { return $_ if $r >= $_->{va} && $r < $_->{va}+$_->{vsz} }
    undef;
}
sub rva2off {
    my $r = shift; my $s = sec_of($r) or return undef;
    my $d = $r - $s->{va}; return undef if $d >= $s->{rsz}; $s->{rp}+$d;
}
sub in_text { my $r = shift; defined $r && $r >= $TEXT->{va} && $r < $TEXT->{va}+$TEXT->{vsz} }

# ---------- .pdata: granice funkcji ----------
my @fn;
{
    my ($pd) = grep { $_->{n} eq '.pdata' } @sec;
    for my $i (0 .. int($pd->{vsz}/12)-1) {
        my ($b,$e) = unpack('VV', substr($buf, $pd->{rp}+$i*12, 8));
        push @fn, [$b,$e] if $b && $e > $b;
    }
    @fn = sort { $a->[0] <=> $b->[0] } @fn;
}
sub fn_idx {
    my $r = shift; my ($lo,$hi) = (0,$#fn);
    while ($lo <= $hi) {
        my $m = int(($lo+$hi)/2);
        if    ($r <  $fn[$m][0]) { $hi = $m-1 }
        elsif ($r >= $fn[$m][1]) { $lo = $m+1 }
        else  { return $m }
    }
    undef;
}
# MSVC tnie jedna funkcje na kilka wpisow .pdata (osobny unwind dla bloku).
# Bez sklejenia gubi sie koniec ciala - a tam zwykle siedzi LEA z vtable.
sub fn_span {
    my ($r,$cap) = @_; $cap //= 0x600;
    my $i = fn_idx($r);
    return ($r, $r+0x40) unless defined $i;
    my ($b,$e) = @{$fn[$i]};
    while ($i+1 <= $#fn && $fn[$i+1][0] == $e && $e-$b < $cap) { $i++; $e = $fn[$i][1] }
    ($b,$e);
}

# ---------- stringi (minimum 2 znaki - "op", "no", "if") ----------
my %str;
for my $s (@sec) {
    next unless $s->{n} =~ /rdata|data/;
    my $blk = substr($buf, $s->{rp}, $s->{rsz});
    while ($blk =~ /([\x20-\x7e]{2,400})\0/g) {
        my $t = $1;
        my $off = $s->{rp} + pos($blk) - length($t) - 1;
        $str{$s->{va} + ($off - $s->{rp})} = $t;
    }
}
sub cstr {
    my $r = shift; my $o = rva2off($r) // return undef;
    my $e = index($buf, "\0", $o);
    return undef if $e < 0 || $e-$o > 400;
    my $v = substr($buf, $o, $e-$o);
    $v =~ /^[\x20-\x7e]*$/ ? $v : undef;
}
sub qrva {
    my $o = rva2off(shift) // return undef;
    my $v = unpack('Q<', substr($buf,$o,8));
    return 0 unless $v;
    ($v < $base || $v > $base + 0x4000000) ? undef : $v - $base;
}

# ---------- LEA rip-wzgledne ----------
# Granica petli to length-7, nie length-8: LEA ma 7 bajtow, wiec przy -8 gubi sie
# instrukcja stojaca dokladnie na koncu funkcji - a male fabryki koncza sie
# wlasnie na LEA z vtable.
sub lea_refs {
    my ($a,$b) = @_;
    my $o = rva2off($a) // return ();
    my $code = substr($buf, $o, $b-$a);
    my @out;
    for my $i (0 .. length($code)-7) {
        my $p = ord(substr($code,$i,1));
        next unless $p == 0x48 || $p == 0x4c;
        next unless ord(substr($code,$i+1,1)) == 0x8d;
        next unless (ord(substr($code,$i+2,1)) & 0xc7) == 0x05;
        push @out, [$a+$i, $a+$i+7+unpack('l<', substr($code,$i+3,4))];
    }
    @out;
}
sub call_targets {
    my ($a,$b) = @_;
    my $o = rva2off($a) // return ();
    my $code = substr($buf, $o, $b-$a);
    my @out;
    for my $i (0 .. length($code)-5) {
        next unless ord(substr($code,$i,1)) == 0xe8;
        push @out, $a+$i+5+unpack('l<', substr($code,$i+1,4));
    }
    @out;
}

# ---------- mapa .text -> plik .cpp ----------
my @mod;
{
    my %cpp;
    for my $r (keys %str) {
        $cpp{$r} = $1 if $str{$r} =~ m{source_work.([A-Za-z0-9_]+[.](?:cpp|h))$};
    }
    for my $h (lea_refs($TEXT->{va}, $TEXT->{va}+$TEXT->{vsz})) {
        push @mod, [$h->[0], $cpp{$h->[1]}] if $cpp{$h->[1]};
    }
    @mod = sort { $a->[0] <=> $b->[0] } @mod;
}
sub module_of {
    my $r = shift;
    return '?' unless @mod && defined $r;
    my ($lo,$hi) = (0,$#mod);
    while ($lo < $hi) { my $m = int(($lo+$hi+1)/2); if ($mod[$m][0] <= $r) { $lo = $m } else { $hi = $m-1 } }
    my $best = $mod[$lo];
    my $next = $lo+1 <= $#mod ? $mod[$lo+1] : undef;
    $best = $next if $next && abs($next->[0]-$r) < abs($best->[0]-$r);
    abs($best->[0]-$r) > 0x20000 ? '?' : $best->[1];
}

# ---------- RTTI: vtable -> nazwa klasy ----------
sub vt_class {
    my $vt = shift;
    my $col = qrva($vt-8) or return undef;
    my $c = rva2off($col) // return undef;
    my ($sig,undef,undef,$td) = unpack('VVVV', substr($buf,$c,16));
    return undef unless $sig == 1;
    my $t = rva2off($td) // return undef;
    my $e = index($buf, "\0", $t+16);
    return undef if $e < 0;
    my $n = substr($buf, $t+16, $e-$t-16);
    return undef unless $n =~ s{^\.\?A[UV]}{};
    $n =~ s/\@\@\z//;
    join('::', reverse split /\@/, $n);
}
sub vt_methods {
    my $vt = shift; my @m;
    for my $i (0..127) {
        my $r = qrva($vt + $i*8);
        last unless $r && in_text($r);
        push @m, $r;
    }
    @m;
}

# ---------- fabryka -> (vtable, klasa) ----------
my %fac;
sub factory {
    my $f = shift;
    return @{$fac{$f}} if $fac{$f};
    my ($fs,$fe) = fn_span($f);
    my ($vt,$cls);
    for my $h (lea_refs($fs,$fe)) {
        my $c = vt_class($h->[1]);
        next unless defined $c;
        ($vt,$cls) = ($h->[1], $c);
        last;
    }
    $fac{$f} = [$vt,$cls];
    ($vt,$cls);
}

# stringi-identyfikatory, ktore nie sa nazwami parametrow
my %NOISE = map { $_ => 1 } qw(Unpack UnpackStr Property sqrtf powf expf fabsf memcpy memset);
sub ident {
    my $v = shift;
    defined $v && $v =~ /^[A-Za-z_][A-Za-z0-9_]{1,47}$/ && !$NOISE{$v};
}

# ---------- parametry klasy = stringi w metodach wirtualnych ----------
# Jeden poziom w glab wywolan, ale tylko w obrebie tego samego modulu - bez tego
# wyciekaja nazwy z przypadkowo zlinkowanych obok funkcji.
sub class_params {
    my ($vt, $home) = @_;
    return () unless $vt;
    my (%seen, @out, %got);
    my @q = map { [$_,0] } vt_methods($vt);
    while (my $e = shift @q) {
        my ($f,$d) = @$e;
        next if $seen{$f}++;
        my ($fs,$fe) = fn_span($f);
        next if $fe-$fs > 4000;
        next if $d > 0 && defined $home && module_of($fs) ne $home;
        for my $h (lea_refs($fs,$fe)) {
            my $s = cstr($h->[1]);
            push @out, $s if ident($s) && !$got{$s}++;
        }
        push @q, map { [$_,$d+1] } grep { in_text($_) } call_targets($fs,$fe) if $d < 1;
    }
    @out;
}

# ---------- tablice par { nazwa, fabryka } ----------
sub scan_tables {
    my @t;
    for my $s (grep { $_->{n} =~ /^[.](data|rdata)$/ } @sec) {
        my $a = $s->{va};
        my $end = $s->{va} + ($s->{rsz} < $s->{vsz} ? $s->{rsz} : $s->{vsz}) - 16;
        while ($a < $end) {
            my $q0 = qrva($a);
            my $nm = $q0 ? cstr($q0) : undef;
            my $q1 = qrva($a+8);
            my $fp = ($q1 && in_text($q1)) ? $q1 : undef;
            if (ident($nm) && $fp) {
                my @ent; my $b = $a;
                while ($b < $end) {
                    my $p0 = qrva($b);
                    my $n2 = $p0 ? cstr($p0) : undef;
                    my $p1 = qrva($b+8);
                    my $f2 = ($p1 && in_text($p1)) ? $p1 : undef;
                    last unless ident($n2) && $f2;
                    push @ent, [$n2,$f2,$b];
                    $b += 16;
                }
                # Krotkie serie tez sa prawdziwymi rejestrami - linker wcina miedzy
                # nie tablice enumow i pojedyncze globalne. Term "camera" stoi sam.
                # Przyjmujemy je tylko wtedy, gdy fabryka rozwiazuje sie na klase z RTTI.
                my $ok = @ent >= 3;
                if (!$ok && @ent) { $ok = grep { (factory($_->[1]))[1] } @ent }
                push @t, { rva=>$a, ent=>\@ent } if $ok;
                $a = $b; next;
            }
            $a += 8;
        }
    }
    @t;
}

# ---------- tablice nazw zakonczone NULL-em (enumy) ----------
sub scan_enums {
    my @t = @_;
    my %busy;
    for my $tb (@t) { for my $en (@{$tb->{ent}}) { $busy{$en->[2]} = 1; $busy{$en->[2]+8} = 1 } }
    my @e;
    for my $s (grep { $_->{n} =~ /^[.](data|rdata)$/ } @sec) {
        my $a = $s->{va};
        my $end = $s->{va} + ($s->{rsz} < $s->{vsz} ? $s->{rsz} : $s->{vsz}) - 16;
        while ($a < $end) {
            if (!$busy{$a}) {
                my @run; my $b = $a;
                while ($b < $end && !$busy{$b}) {
                    my $q = qrva($b);
                    last unless $q;
                    my $v = cstr($q);
                    last unless defined $v && length($v) <= 48;
                    push @run, $v; $b += 8;
                }
                my $term = $b < $end ? qrva($b) : undef;
                if (@run >= 2 && defined $term && $term == 0) {
                    push @e, { rva=>$a, v=>[@run] };
                    $a = $b + 8; next;
                }
            }
            $a += 8;
        }
    }
    @e;
}

# ---------- funkcja -> klasa, ktorej vtable ja zawiera ----------
sub owner_map {
    my @t = @_;
    my %own;
    for my $tb (@t) {
        for my $en (@{$tb->{ent}}) {
            my ($vt,$cls) = factory($en->[1]);
            next unless $cls;
            $own{$_} = $cls for vt_methods($vt);
        }
    }
    \%own;
}

# ================= komendy =================
if ($cmd eq 'tablice' || $cmd eq 'enumy' || $cmd eq 'gen') {
    my @t = scan_tables();

    my $out_tab = '';
    if ($cmd ne 'enumy') {
        for my $tb (sort { $a->{rva} <=> $b->{rva} } @t) {
            my $m = module_of($tb->{ent}[0][1]);
            $out_tab .= sprintf "\n=== 0x%08x  %-34s wpisow: %d\n", $tb->{rva}, $m, scalar @{$tb->{ent}};
            for my $en (@{$tb->{ent}}) {
                my ($vt,$cls) = factory($en->[1]);
                my @p = class_params($vt, $m);
                $out_tab .= sprintf "  %-32s %-38s %s\n", $en->[0], $cls // '-', join(' ', @p);
            }
        }
        $out_tab .= sprintf "\nrazem tablic: %d\n", scalar @t;
    }

    my $out_en = '';
    if ($cmd ne 'tablice') {
        my $own = owner_map(@t);
        my %want = map { $_->{rva} => 1 } (my @en = scan_enums(@t));
        my %by;
        for my $h (lea_refs($TEXT->{va}, $TEXT->{va}+$TEXT->{vsz})) {
            next unless $want{$h->[1]};
            my ($fs) = fn_span($h->[0]);
            $by{$h->[1]}{ $own->{$fs} // module_of($fs) } = 1;
        }
        for my $e (@en) {
            $out_en .= sprintf "0x%08x  %-44s %s\n", $e->{rva},
                (join(',', sort keys %{$by{$e->{rva}} || {}}) || '?'),
                join(' ', map { "\"$_\"" } @{$e->{v}});
        }
    }

    if    ($cmd eq 'tablice') { print $out_tab }
    elsif ($cmd eq 'enumy')   { print $out_en }
    else {
        my $dir = $arg[0] or die "gen wymaga katalogu\n";
        open my $f1, '>', "$dir/tablice.txt" or die "$dir/tablice.txt: $!";
        print $f1 header(), $out_tab; close $f1;
        open my $f2, '>', "$dir/enumy.txt" or die "$dir/enumy.txt: $!";
        print $f2 header(), $out_en; close $f2;
        print "zapisano $dir/tablice.txt i $dir/enumy.txt\n";
    }
}
elsif ($cmd eq 'modul') {
    # Caly modul, nie jedna funkcja. Czesc skladni nie siedzi w zadnej tablicy,
    # tylko w lancuchu porownan stringow rozrzuconym po kilku funkcjach jednego
    # pliku .cpp - tak jest z klauzulami selektora.
    my $want = $arg[0] or die "podaj nazwe pliku .cpp\n";
    my %seen;
    for my $f (@fn) {
        my ($b,$e) = @$f;
        next if $seen{$b}++;
        next unless module_of($b) eq $want;
        my @s = grep { ident($_) } map { cstr($_->[1]) } lea_refs($b,$e);
        printf "0x%06x (%5d B) %s\n", $b, $e-$b, join(' | ', @s) if @s;
    }
}
elsif ($cmd eq 'fn') {
    my $a0 = $arg[0] // die "podaj rva\n"; $a0 =~ s/^0x//i;
    my $depth = $arg[1] // 1;
    my %seen; my @q = ([hex($a0),0]);
    while (my $e = shift @q) {
        my ($f,$d) = @$e;
        next if $seen{$f}++;
        my ($fs,$fe) = fn_span($f);
        next if $fe-$fs > 6000;
        my @s = grep { ident($_) } map { cstr($_->[1]) } lea_refs($fs,$fe);
        printf "%s0x%x (%d B) [%s] %s\n", '  'x$d, $fs, $fe-$fs, module_of($fs), join(' | ', @s) if @s;
        push @q, map { [$_,$d+1] } grep { in_text($_) } call_targets($fs,$fe) if $d < $depth;
    }
}
else { die usage() }

sub header {
    my @t = localtime;
    sprintf "# wygenerowane przez pe/slownik.pl\n# exe: %s (%d B)\n# data: %04d-%02d-%02d\n"
          . "# OFFSETY SA WAZNE TYLKO DLA TEGO BUILDA - po update gry przegeneruj\n",
          $exe, (-s $exe), $t[5]+1900, $t[4]+1, $t[3];
}

sub usage {
<<"END";
slownik.pl - slownik skladni skryptow GEM2 wyciagniety z binarki

  perl pe/slownik.pl <exe> tablice            rejestry {nazwa -> klasa} + parametry
  perl pe/slownik.pl <exe> enumy              tablice nazw zakonczone NULL-em
  perl pe/slownik.pl <exe> modul <plik.cpp>      stringi wszystkich funkcji modulu
  perl pe/slownik.pl <exe> fn <rva> [glebia]  stringi funkcji i jej wywolan
  perl pe/slownik.pl <exe> gen <katalog>      zapisuje tablice.txt i enumy.txt
END
}
