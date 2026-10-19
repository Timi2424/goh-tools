package cmds;
# Dodatkowe komendy harnessu, trzymane osobno zeby goh.pl zostal czytelny.
# Wywolywane z goh.pl, korzystaja z przekazanego kontekstu.

use strict; use warnings;

# ---- dis: czesciowy dezasembler ----
sub dis {
    my ($ctx, $rva, $n) = @_;
    $n //= 24;
    my ($fs, $fe) = $ctx->{fn_of}->($rva);
    printf "funkcja 0x%x .. 0x%x  (%d B)\n\n", $fs, $fe, $fe-$fs if $fs;
    my $cur = $rva;
    for (1 .. $n) {
        my $off = $ctx->{rva2off}->($cur) or last;
        my ($txt, $len) = dis::one($ctx->{buf}, $off, $cur);
        $len = 1 if !$len || $len < 1;
        my $raw = join ' ', map { sprintf '%02x', ord } split //, substr($ctx->{buf}, $off, $len);
        my $note = '';
        if ($txt =~ /-> 0x([0-9a-f]+)/) {
            my $t = hex($1);
            $note = sprintf('   ; "%s"', $ctx->{str}{$t}) if exists $ctx->{str}{$t};
        }
        printf "  0x%06x  %-24s %s%s\n", $cur, $raw, $txt, $note;
        $cur += $len;
        last if $fe && $cur >= $fe;
    }
}

# ---- pattern: szukanie po bajtach, z ?? jako maska ----
sub pattern {
    my ($ctx, $pat) = @_;
    die "podaj wzorzec, np. 48895c2408 albo 4889??2408\n" unless defined $pat;
    $pat =~ s/\s+//g;
    die "nieparzysta liczba znakow\n" if length($pat) % 2;
    my (@by, @mask);
    while ($pat =~ /(..)/g) {
        my $p = $1;
        if ($p eq '??') { push @by, 0; push @mask, 0 }
        else            { push @by, hex($p); push @mask, 1 }
    }
    my $t    = $ctx->{text};
    my $code = substr($ctx->{buf}, $t->{rp}, $t->{rsz});
    my $hits = 0;
  OUTER:
    for my $i (0 .. length($code) - scalar(@by)) {
        for my $k (0 .. $#by) {
            next OUTER if $mask[$k] && ord(substr($code, $i+$k, 1)) != $by[$k];
        }
        my $rva = $t->{va} + $i;
        my ($fs, $fe) = $ctx->{fn_of}->($rva);
        printf "  0x%06x", $rva;
        printf "   funkcja 0x%x +0x%x", $fs, $rva - $fs if $fs;
        print "\n";
        last if ++$hits >= 40;
    }
    printf "trafien: %s\n", ($hits >= 40 ? '40+ (obciete)' : $hits);
    print "\nWzorzec unikalny = nadaje sie na kotwice patcha odporna na update gry.\n"
        if $hits == 1;
}

# ---- strblock: ciagly blok stringow, czyli zwykle tablica nazw ----
sub strblock {
    my ($ctx, $rva, $n) = @_;
    $n //= 60;
    my @k = sort { $a <=> $b }
            grep { $_ >= $rva - 0x200 && $_ <= $rva + 0x4000 } keys %{$ctx->{str}};
    printf "stringi w okolicy 0x%x:\n", $rva;
    my ($c, $prev) = (0, undef);
    for my $a (@k) {
        my $gap = defined $prev ? $a - $prev : 0;
        print "  ---- przerwa " . sprintf("%d B", $gap) . " ----\n" if defined $prev && $gap > 64;
        printf "  0x%08x  %s\n", $a, $ctx->{str}{$a};
        $prev = $a + length($ctx->{str}{$a}) + 1;
        last if ++$c >= $n;
    }
    print "\nCiagly blok bez duzych przerw to zwykle tablica nazw -\n"
        . "tak wygladaja listy akcji, termow i enumow w silniku.\n";
}

1;
