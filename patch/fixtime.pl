use strict; use warnings;
my $f = shift;
open(my $h, '<:raw', $f) or die $!; local $/; my $c = <$h>; close $h;
my $T = "\t";
my $pat = qr/\t{4}\{condition\r\n\t{5}\{terms\r\n\t{6}\{"1\.time"\r\n\t{7}\{time (\d+)\}\r\n\t{6}\}\r\n\t{5}\}\r\n\t{4}\}\r\n\t{4}\{actions\r\n/;
my $n = 0;
while ($c =~ $pat) {
  my $t = $1;
  my $rep = ($T x 4) . "{condition\r\n" . ($T x 4) . "}\r\n"
          . ($T x 4) . "{actions\r\n"
          . ($T x 5) . "{\"delay\"\r\n"
          . ($T x 6) . "{time $t}\r\n"
          . ($T x 5) . "}\r\n";
  $c =~ s/$pat/$rep/;
  $n++;
  last if $n > 10;
}
open(my $w, '>:raw', $f) or die $!; print $w $c; close $w;
print "podmieniono blokow: $n\n";
