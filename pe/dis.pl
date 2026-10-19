package dis;
# Czesciowy dekoder x86-64 - tylko ten podzbior, ktory realnie wystepuje
# w prologach i w kodzie wokol crashy. NIE jest pelnym dezasemblerem.
#
# Pokrywa: push/pop, mov r/m<->r, mov r,imm, lea, add/sub/cmp/test/and/or/xor
# na r/m, inc/dec, call rel32 i posrednie, jmp/jcc, ret, nop, int3,
# oraz SSE movss/movaps/movdqu w wersji podstawowej.
#
# Czego nie umie: prefiksy segmentowe, VEX/EVEX, wiekszosc SSE/AVX, x87.
# Przy nieznanym opkodzie zwraca "db XX" i idzie o bajt dalej - dzieki temu
# nigdy sie nie zapetla, ale od tego miejsca moze zgubic synchronizacje.

use strict; use warnings;

my @R64 = qw(rax rcx rdx rbx rsp rbp rsi rdi r8 r9 r10 r11 r12 r13 r14 r15);
my @R32 = qw(eax ecx edx ebx esp ebp esi edi r8d r9d r10d r11d r12d r13d r14d r15d);
my @R16 = qw(ax cx dx bx sp bp si di r8w r9w r10w r11w r12w r13w r14w r15w);
my @R8  = qw(al cl dl bl spl bpl sil dil r8b r9b r10b r11b r12b r13b r14b r15b);

sub reg { my ($n,$sz) = @_;
    return $R64[$n] if $sz == 8; return $R32[$n] if $sz == 4;
    return $R16[$n] if $sz == 2; return $R8[$n] }

sub hx { my $v = shift; $v < 0 ? sprintf("-0x%x", -$v) : sprintf("0x%x", $v) }

# zwraca (tekst_operandu_rm, dlugosc_modrm_i_reszty, numer_rejestru_reg)
sub modrm {
    my ($b, $i, $sz, $rex, $rva) = @_;
    my $m   = ord(substr($b,$i,1));
    my $mod = ($m >> 6) & 3;
    my $r   = (($m >> 3) & 7) | ((($rex // 0) & 4) ? 8 : 0);
    my $rm  = ($m & 7);
    my $len = 1;
    my $base_ext = (($rex // 0) & 1) ? 8 : 0;

    if ($mod == 3) { return (reg($rm | $base_ext, $sz), $len, $r) }

    my ($sib_txt, $idx_txt) = ('', '');
    if ($rm == 4) {                                   # SIB
        my $s = ord(substr($b,$i+1,1)); $len++;
        my $scale = 1 << (($s >> 6) & 3);
        my $index = (($s >> 3) & 7) | ((($rex // 0) & 2) ? 8 : 0);
        my $base  = ($s & 7) | $base_ext;
        $sib_txt = $R64[$base];
        $idx_txt = "+" . $R64[$index] . ($scale > 1 ? "*$scale" : '') if $index != 4;
    }
    elsif ($mod == 0 && $rm == 5) {                   # RIP-relative
        my $d = unpack('l<', substr($b,$i+$len,4)); $len += 4;
        return ("[rip" . ($d ? "+".hx($d) : '') . "]", $len, $r, $d);
    }
    else { $sib_txt = $R64[$rm | $base_ext] }

    my $disp = 0;
    if    ($mod == 1) { $disp = unpack('c',  substr($b,$i+$len,1)); $len += 1 }
    elsif ($mod == 2) { $disp = unpack('l<', substr($b,$i+$len,4)); $len += 4 }

    my $d_txt = $disp ? ($disp < 0 ? "-".hx(-$disp) : "+".hx($disp)) : '';
    return ("[$sib_txt$idx_txt$d_txt]", $len, $r);
}

my %ARITH = (0x00=>'add',0x08=>'or',0x10=>'adc',0x18=>'sbb',
             0x20=>'and',0x28=>'sub',0x30=>'xor',0x38=>'cmp');
my @CC = qw(o no b ae e ne be a s ns p np l ge le g);

# dekoduje jedna instrukcje; zwraca (tekst, dlugosc)
sub one {
    my ($b, $i, $rva) = @_;
    my $start = $i;
    my ($rex, $o16) = (0, 0);

    while (1) {
        my $p = ord(substr($b,$i,1));
        if ($p == 0x66) { $o16 = 1; $i++; next }
        if ($p == 0xf2 || $p == 0xf3 || $p == 0x2e || $p == 0x3e || $p == 0x64 || $p == 0x65) { $i++; next }
        if ($p >= 0x40 && $p <= 0x4f) { $rex = $p & 0xf; $i++; next }
        last;
    }
    my $sz = ($rex & 8) ? 8 : ($o16 ? 2 : 4);
    my $op = ord(substr($b,$i,1)); $i++;

    # push/pop r64
    if ($op >= 0x50 && $op <= 0x57) { return ("push " . $R64[($op-0x50) | (($rex&1)?8:0)], $i-$start) }
    if ($op >= 0x58 && $op <= 0x5f) { return ("pop "  . $R64[($op-0x58) | (($rex&1)?8:0)], $i-$start) }

    # arytmetyka r/m,r  i  r,r/m
    if (exists $ARITH{$op & 0xf8} && ($op & 7) <= 3) {
        my $mn = $ARITH{$op & 0xf8};
        my $w  = ($op & 1) ? $sz : 1;
        my ($rm,$l,$r) = modrm($b,$i,$w,$rex,$rva); $i += $l;
        my $rg = reg($r,$w);
        return ((($op & 2) ? "$mn $rg, $rm" : "$mn $rm, $rg"), $i-$start);
    }
    # test r/m,r
    if ($op == 0x84 || $op == 0x85) {
        my $w = ($op == 0x85) ? $sz : 1;
        my ($rm,$l,$r) = modrm($b,$i,$w,$rex,$rva); $i += $l;
        return ("test $rm, " . reg($r,$w), $i-$start);
    }
    # mov r/m,r | r,r/m
    if ($op >= 0x88 && $op <= 0x8b) {
        my $w = ($op & 1) ? $sz : 1;
        my ($rm,$l,$r) = modrm($b,$i,$w,$rex,$rva); $i += $l;
        my $rg = reg($r,$w);
        return ((($op & 2) ? "mov $rg, $rm" : "mov $rm, $rg"), $i-$start);
    }
    # lea
    if ($op == 0x8d) {
        my ($rm,$l,$r,$d) = modrm($b,$i,$sz,$rex,$rva); $i += $l;
        if (defined $d) { my $tgt = $rva + ($i-$start) + $d;
            return (sprintf("lea %s, [rip+%s]   ; -> 0x%x", reg($r,$sz), hx($d), $tgt), $i-$start) }
        return ("lea " . reg($r,$sz) . ", $rm", $i-$start);
    }
    # mov r, imm
    if ($op >= 0xb8 && $op <= 0xbf) {
        my $r = ($op-0xb8) | (($rex&1)?8:0);
        if ($rex & 8) { my $v = unpack('Q<', substr($b,$i,8)); $i += 8;
                        return ("movabs " . $R64[$r] . ", " . hx($v), $i-$start) }
        my $v = unpack('V', substr($b,$i,4)); $i += 4;
        return ("mov " . reg($r,$sz) . ", " . hx($v), $i-$start);
    }
    # grupa 0x81/0x83 - arytmetyka z natychmiastowa
    if ($op == 0x81 || $op == 0x83) {
        my ($rm,$l,$r) = modrm($b,$i,$sz,$rex,$rva); $i += $l;
        my @g = qw(add or adc sbb and sub xor cmp);
        my $v = $op == 0x83 ? unpack('c', substr($b,$i,1)) : unpack('l<', substr($b,$i,4));
        $i += $op == 0x83 ? 1 : 4;
        return ($g[$r & 7] . " $rm, " . hx($v), $i-$start);
    }
    # mov r/m, imm
    if ($op == 0xc6 || $op == 0xc7) {
        my $w = ($op == 0xc7) ? $sz : 1;
        my ($rm,$l) = modrm($b,$i,$w,$rex,$rva); $i += $l;
        my $v = ($op == 0xc7) ? unpack('l<', substr($b,$i,4)) : unpack('C', substr($b,$i,1));
        $i += ($op == 0xc7) ? 4 : 1;
        return ("mov $rm, " . hx($v), $i-$start);
    }
    # call / jmp rel32, jmp rel8
    if ($op == 0xe8 || $op == 0xe9) {
        my $d = unpack('l<', substr($b,$i,4)); $i += 4;
        return (($op == 0xe8 ? 'call' : 'jmp') . sprintf(" 0x%x", $rva + ($i-$start) + $d), $i-$start);
    }
    if ($op == 0xeb) { my $d = unpack('c', substr($b,$i,1)); $i++;
        return (sprintf("jmp 0x%x", $rva + ($i-$start) + $d), $i-$start) }
    # jcc rel8 / rel32
    if ($op >= 0x70 && $op <= 0x7f) { my $d = unpack('c', substr($b,$i,1)); $i++;
        return (sprintf("j%-3s 0x%x", $CC[$op-0x70], $rva + ($i-$start) + $d), $i-$start) }
    if ($op == 0x0f) {
        my $o2 = ord(substr($b,$i,1)); $i++;
        if ($o2 >= 0x80 && $o2 <= 0x8f) { my $d = unpack('l<', substr($b,$i,4)); $i += 4;
            return (sprintf("j%-3s 0x%x", $CC[$o2-0x80], $rva + ($i-$start) + $d), $i-$start) }
        if ($o2 >= 0x90 && $o2 <= 0x9f) { my ($rm,$l) = modrm($b,$i,1,$rex,$rva); $i += $l;
            return ("set" . $CC[$o2-0x90] . " $rm", $i-$start) }
        if ($o2 == 0xb6 || $o2 == 0xb7 || $o2 == 0xbe || $o2 == 0xbf) {
            my $sw = ($o2 & 1) ? 2 : 1;
            my ($rm,$l,$r) = modrm($b,$i,$sw,$rex,$rva); $i += $l;
            return ((($o2 < 0xbe) ? 'movzx ' : 'movsx ') . reg($r,$sz) . ", $rm", $i-$start);
        }
        if ($o2 == 0x1f) { my ($rm,$l) = modrm($b,$i,$sz,$rex,$rva); $i += $l;
            return ("nop $rm", $i-$start) }
        if ($o2 == 0x10 || $o2 == 0x11) {             # movss/movups xmm
            my ($rm,$l,$r) = modrm($b,$i,8,$rex,$rva); $i += $l;
            return (($o2 == 0x10 ? "movs xmm$r, $rm" : "movs $rm, xmm$r"), $i-$start);
        }
        return (sprintf("(0f %02x ...)", $o2), $i-$start);
    }
    # grupa 0xff - call/jmp/push posrednie, inc/dec
    if ($op == 0xff) {
        my ($rm,$l,$r) = modrm($b,$i,$sz,$rex,$rva); $i += $l;
        my @g = ('inc','dec','call','callf','jmp','jmpf','push','?');
        return ($g[$r & 7] . " $rm", $i-$start);
    }
    if ($op == 0xc3) { return ("ret", $i-$start) }
    if ($op == 0x90) { return ("nop", $i-$start) }
    if ($op == 0xcc) { return ("int3", $i-$start) }

    return (sprintf("db 0x%02x", $op), $start == $i ? 1 : $i-$start);
}

1;
