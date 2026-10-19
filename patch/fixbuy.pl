use strict; use warnings;
my $f = shift;
open(my $h,'<:raw',$f) or die $!; local $/; my $c = <$h>; close $h;
my $old = qr/\t\("squad_vehicle" side\(ger\) period\(mid\)  min_stage\(1\) max_stage\(99\) cw\(0\) cp\(0\) crew\(pilot:2\) vehicle\(c47_d\)\)/;
my $new = "\t(\"squad_vehicle10\" side(ger) period(mid) min_stage(1) max_stage(99) cw(0) cp(0) vehicle(c47_d) "
        . "crew1(pilot:2) crew2(fallsch_recon_sl:1) crew3(fallsch_recon_sl_asst:1) crew4(fallsch_recon_mg:1) "
        . "crew5(fallsch_recon_mg34:1) crew6(fallsch_recon_mg_asst:1) crew7(fallsch_recon_mg_asst_gren:1))";
die "nie znalazlem wpisu\n" unless $c =~ $old;
$c =~ s/$old/$new/;
open(my $w,'>:raw',$f) or die $!; print $w $c; close $w;
print "podmieniono wpis zakupowy\n";
