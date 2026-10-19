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
my $T = "\t";
my @new = (
  ($T x 2)."
",
  ($T x 2).";// POMIAR OSI - ktora czasza wisi w powietrzu?\n",
  ($T x 2)."{delay 2  {spawn \"paratrooper_attach\"}}\t\t\t\t;// A - bez offsetu\n",
  ($T x 2)."{delay 5  {spawn \"paratrooper_attach\" offset 80 0 0}}\t;// B - pierwsza\n",
  ($T x 2)."{delay 8  {spawn \"paratrooper_attach\" offset 0 80 0}}\t;// C - druga\n",
  ($T x 2)."{delay 11 {spawn \"paratrooper_attach\" offset 0 0 80}}\t;// D - trzecia\n",
);
splice(@L, $s+5, $e-$s-5, @new);
open(my $w,'>:raw',$f) or die $!; print $w join('',@L); close $w;
print "podmieniono blok define\n";
