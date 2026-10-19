use strict; use warnings;
my $f = shift;
open(my $h,'<:raw',$f) or die $!; local $/; my $c = <$h>; close $h;
my @L = split /(?<=\n)/, $c;
my ($s,$e);
for my $i (0..$#L) {
  $s = $i if !defined($s) && $L[$i] =~ /\(define "conquest_paradrop_point"/;
  if (defined($s) && $i > $s && $L[$i] =~ /\{delay %lifetime/) { $e = $i; last }
}
die "nie znalazlem bloku\n" unless defined $s && defined $e;
my $T = "\t"; my @new;
push @new, ($T x 2).";// pelny zrzut - rozstaw poziomy 80 (sprawdzony), bez kombinowania z pulapem\n";
my @x = (-160, -80, 0, 80, 160);
my $t = 1.0;
for my $x (@x) {
  push @new, ($T x 2)."{delay $t {spawn \"paratrooper_attach\" offset $x 0 0}}\n";
  my $t2 = sprintf("%.1f", $t + 0.3);
  push @new, ($T x 2)."{delay $t2 {spawn \"mp/ger/mid/fallsch_para_drop\" offset $x 0 0}}\n";
  $t = sprintf("%.1f", $t + 1.0);
}
splice(@L, $s+5, $e-$s-5, @new);
open(my $w,'>:raw',$f) or die $!; print $w join('',@L); close $w;
print "podmieniono\n";
