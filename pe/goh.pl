#!/usr/bin/perl
# goh.pl - harness do grzebania w binarce Gates of Hell (GEM2, PE x64)
#
#   perl goh.pl <exe> info                 naglowki, sekcje, liczba funkcji
#   perl goh.pl <exe> fn    <rva>          ktora funkcja zawiera adres (z .pdata)
#   perl goh.pl <exe> near  <rva> [okno]   stringi wokol adresu -> identyfikacja modulu
#   perl goh.pl <exe> str   <regex>        stringi pasujace do wzorca, z RVA
#   perl goh.pl <exe> xref  <rva|regex>    kto odwoluje sie do stringa / adresu
#   perl goh.pl <exe> calls <rva>          kto wywoluje funkcje pod tym adresem
#   perl goh.pl <exe> cpp                  lista plikow zrodlowych silnika
#   perl goh.pl <exe> rtti  [regex]        klasy z RTTI
#   perl goh.pl <exe> dump  <rva> [n]      hexdump n bajtow od adresu
#   perl goh.pl <exe> dis   <rva> [n]      czesciowy dezasembler, n instrukcji
#   perl goh.pl <exe> pattern <hex>        szukanie po bajtach, ?? = dowolny
#   perl goh.pl <exe> strblock <rva>       ciagly blok stringow = tablica nazw
#
# Metoda: PE ma .pdata z wpisami RUNTIME_FUNCTION (12 B: begin/end/unwind),
# co daje DOKLADNE granice kazdej funkcji. Kod identyfikuje sie po LEA
# rip-wzglednym do stringow z .rdata - silnik ma ~540 stringow
# D:\BUILDS\PROJECT_2\goh\GEM\source_work\*.cpp, wiec sasiedztwo zdradza modul.

use strict; use warnings;
use FindBin;
require "$FindBin::Bin/dis.pl";
require "$FindBin::Bin/cmds.pl";

my ($exe, $cmd, @arg) = @ARGV;
die usage() unless $exe && $cmd;
open(my $fh, '<:raw', $exe) or die "nie moge otworzyc $exe: $!\n";
my $buf = do { local $/; <$fh> }; close $fh;

# ---------- PE ----------
my $e_lfanew = unpack('V', substr($buf, 0x3c, 4));
die "to nie jest PE\n" unless substr($buf, $e_lfanew, 4) eq "PE\0\0";
my $coff = $e_lfanew + 4;
my ($machine, $nsec, undef, undef, undef, $optsz) = unpack('vvVVVv', substr($buf, $coff, 18));
my $opt   = $coff + 20;
my $magic = unpack('v', substr($buf, $opt, 2));
my $base  = $magic == 0x20b ? unpack('Q<', substr($buf, $opt+24, 8))
                            : unpack('V',  substr($buf, $opt+28, 4));
my @sec;
for my $i (0 .. $nsec-1) {
    my $o = $opt + $optsz + $i*40;
    my $n = substr($buf, $o, 8); $n =~ s/\0+$//;
    my ($vsz,$va,$rsz,$rp) = unpack('VVVV', substr($buf, $o+8, 16));
    push @sec, { n=>$n, vsz=>$vsz, va=>$va, rsz=>$rsz, rp=>$rp };
}
sub sec_of { my $r = shift; for (@sec) { return $_ if $r >= $_->{va} && $r < $_->{va}+$_->{vsz} } undef }
sub rva2off { my $r = shift; my $s = sec_of($r) or return undef;
              my $d = $r - $s->{va}; return undef if $d >= $s->{rsz}; $s->{rp} + $d }
sub off2rva { my $o = shift; for (@sec) { return $_->{va} + ($o - $_->{rp})
                 if $o >= $_->{rp} && $o < $_->{rp} + $_->{rsz} } undef }
sub text { my ($t) = grep { $_->{n} eq '.text' } @sec; $t }

# ---------- .pdata: granice funkcji ----------
my @fn;
sub load_fn {
    return if @fn;
    my ($pd) = grep { $_->{n} eq '.pdata' } @sec or return;
    for my $i (0 .. int($pd->{vsz}/12)-1) {
        my ($b,$e) = unpack('VV', substr($buf, $pd->{rp} + $i*12, 8));
        push @fn, [$b,$e] if $b && $e > $b;
    }
    @fn = sort { $a->[0] <=> $b->[0] } @fn;
}
sub fn_of {                                   # wyszukiwanie binarne
    my $r = shift; load_fn();
    my ($lo,$hi) = (0, $#fn);
    while ($lo <= $hi) {
        my $m = int(($lo+$hi)/2);
        if    ($r <  $fn[$m][0]) { $hi = $m-1 }
        elsif ($r >= $fn[$m][1]) { $lo = $m+1 }
        else  { return @{$fn[$m]} }
    }
    return ();
}

# ---------- stringi ----------
my %str;                                      # rva => tekst
sub load_str {
    return if %str;
    for my $s (@sec) {
        next unless $s->{n} =~ /rdata|data/;
        my $blk = substr($buf, $s->{rp}, $s->{rsz});
        while ($blk =~ /([\x20-\x7e]{4,400})\0/g) {
            my $t = $1;
            my $off = $s->{rp} + pos($blk) - length($t) - 1;
            my $r = off2rva($off);
            $str{$r} = $t if defined $r;
        }
    }
}

# ---------- LEA rip-wzgledne: kod -> string ----------
sub lea_refs {                                # (od, do) => [[rva_instr, rva_celu], ...]
    my ($a, $b) = @_;
    my $o = rva2off($a) // return ();
    my $code = substr($buf, $o, $b - $a);
    my @out;
    for my $i (0 .. length($code)-8) {
        my $p1 = ord(substr($code,$i,1));
        next unless $p1 == 0x48 || $p1 == 0x4c;
        next unless ord(substr($code,$i+1,1)) == 0x8d;
        next unless (ord(substr($code,$i+2,1)) & 0xc7) == 0x05;
        my $disp = unpack('l<', substr($code,$i+3,4));
        push @out, [ $a+$i, $a+$i+7+$disp ];
    }
    @out;
}

# ---------- komendy ----------
if ($cmd eq 'info') {
    load_fn(); load_str();
    printf "plik      : %s (%d B)\n", $exe, length($buf);
    printf "machine   : 0x%x   imagebase: 0x%x\n", $machine, $base;
    printf "funkcji   : %d  (.pdata)\n", scalar @fn;
    printf "stringow  : %d\n", scalar keys %str;
    printf "%-9s %-12s %-12s %-12s\n", 'SEKCJA','VA','VSIZE','RAW';
    printf "%-9s 0x%08x   0x%08x   0x%08x\n", $_->{n}, $_->{va}, $_->{vsz}, $_->{rp} for @sec;
}
elsif ($cmd eq 'fn') {
    my $r = hex2($arg[0]);
    my ($s,$e) = fn_of($r) or die "brak funkcji dla 0x%x\n";
    printf "funkcja   : 0x%x .. 0x%x  (%d B)\n", $s, $e, $e-$s;
    printf "adres     : 0x%x  = start +0x%x\n", $r, $r-$s;
    printf "sekcja    : %s\n", (sec_of($r)//{n=>'?'})->{n};
    load_str();
    my @s = grep { exists $str{$_->[1]} } lea_refs($s,$e);
    print "stringi uzywane w funkcji:\n";
    printf "  +0x%-5x %s\n", $_->[0]-$s, $str{$_->[1]} for @s;
    print "  (brak)\n" unless @s;
}
elsif ($cmd eq 'near') {
    my $r = hex2($arg[0]); my $w = $arg[1] ? hex2($arg[1]) : 0x3000;
    load_str();
    my @h = grep { exists $str{$_->[1]} } lea_refs($r-$w, $r+$w);
    printf "stringi w oknie +/-0x%x wokol 0x%x:\n", $w, $r;
    for (@h) { printf "  %s 0x%06x (%+7d)  %s\n",
               ($_->[0] < $r ? '  ' : '>>'), $_->[0], $_->[0]-$r, $str{$_->[1]} }
}
elsif ($cmd eq 'str') {
    my $re = qr/$arg[0]/;
    load_str();
    for my $r (sort { $a <=> $b } keys %str) {
        printf "  0x%08x  %s\n", $r, $str{$r} if $str{$r} =~ $re;
    }
}
elsif ($cmd eq 'xref') {
    load_str(); load_fn();
    my @targets = $arg[0] =~ /^(0x)?[0-9a-f]+$/i
        ? (hex2($arg[0]))
        : (grep { $str{$_} =~ /$arg[0]/ } keys %str);
    printf "celow: %d\n", scalar @targets;
    my %want = map { $_ => 1 } @targets;
    my $t = text();
    my %seen;
    for my $h (lea_refs($t->{va}, $t->{va}+$t->{vsz})) {
        next unless $want{$h->[1]};
        my ($s,$e) = fn_of($h->[0]);
        next if !$s || $seen{$s}++;
        printf "  ref 0x%x  w funkcji 0x%x..0x%x\n", $h->[0], $s, $e;
        printf "      \"%s\"\n", $str{$h->[1]} if exists $str{$h->[1]};
    }
}
elsif ($cmd eq 'calls') {
    my $tgt = hex2($arg[0]); load_fn();
    my $t = text();
    my $code = substr($buf, $t->{rp}, $t->{rsz});
    my $n = 0;
    for my $i (0 .. length($code)-5) {
        next unless ord(substr($code,$i,1)) == 0xe8;
        my $rel = unpack('l<', substr($code,$i+1,4));
        my $site = $t->{va} + $i;
        next unless $site + 5 + $rel == $tgt;
        my ($s,$e) = fn_of($site);
        printf "  call z 0x%-8x  (funkcja 0x%x)\n", $site, $s // 0;
        $n++;
    }
    printf "razem: %d\n", $n;
}
elsif ($cmd eq 'cpp') {
    load_str();
    my %f;
    for (values %str) { $f{$1}++ while /source_work[\\\/]([A-Za-z0-9_]+\.(?:cpp|h))/g }
    printf "  %-44s x%d\n", $_, $f{$_} for sort keys %f;
    printf "razem: %d plikow\n", scalar keys %f;
}
elsif ($cmd eq 'rtti') {
    my $re = $arg[0] ? qr/$arg[0]/ : qr/./;
    my %h;
    while ($buf =~ /\.\?AV([A-Za-z0-9_\@\?\$]{3,160})/g) {
        my $n = $1; $n =~ s/\@\@.*//; $n =~ s/\@/::/g;
        $h{$n} = 1 if $n =~ $re;
    }
    print "  $_\n" for sort keys %h;
    printf "razem: %d klas\n", scalar keys %h;
}
elsif ($cmd eq 'dump') {
    my $r = hex2($arg[0]); my $n = $arg[1] // 64;
    my $o = rva2off($r) or die "adres poza plikiem\n";
    my $d = substr($buf, $o, $n);
    for (my $i = 0; $i < length($d); $i += 16) {
        my $c = substr($d, $i, 16);
        printf "0x%06x  %-48s %s\n", $r+$i,
            join(' ', map { sprintf '%02x', ord } split //, $c),
            join('', map { my $v=ord; ($v>=0x20 && $v<0x7f) ? chr($v) : '.' } split //, $c);
    }
}
elsif ($cmd eq 'dis' || $cmd eq 'pattern' || $cmd eq 'strblock') {
    load_fn(); load_str();
    my %ctx = (
        buf     => $buf,
        str     => \%str,
        text    => text(),
        fn_of   => \&fn_of,
        rva2off => \&rva2off,
    );
    if    ($cmd eq 'dis')     { cmds::dis(\%ctx, hex2($arg[0]), $arg[1]) }
    elsif ($cmd eq 'pattern') { cmds::pattern(\%ctx, $arg[0]) }
    else                      { cmds::strblock(\%ctx, hex2($arg[0]), $arg[1]) }
}
else { die usage() }

sub hex2 { my $v = shift // die "brak adresu\n"; $v =~ s/^0x//i; hex($v) }

sub usage {
<<"END";
goh.pl - harness do binarki Gates of Hell

  perl goh.pl <exe> info                naglowki, sekcje, liczba funkcji
  perl goh.pl <exe> fn    <rva>         ktora funkcja zawiera adres
  perl goh.pl <exe> near  <rva> [okno]  stringi wokol adresu
  perl goh.pl <exe> str   <regex>       stringi pasujace do wzorca
  perl goh.pl <exe> xref  <rva|regex>   kto odwoluje sie do stringa
  perl goh.pl <exe> calls <rva>         kto wywoluje funkcje
  perl goh.pl <exe> cpp                 pliki zrodlowe silnika
  perl goh.pl <exe> rtti  [regex]       klasy z RTTI
  perl goh.pl <exe> dump  <rva> [n]     hexdump

Przyklad - jak znalezlismy przyczyne crasha:
  perl goh.pl call_to_arms.exe fn   0x72673a
  perl goh.pl call_to_arms.exe near 0x72673a
  perl goh.pl call_to_arms.exe xref "Can't find entity"
END
}
