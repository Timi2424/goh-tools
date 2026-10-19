#!/usr/bin/perl
# raport.pl - jedno polecenie, caly stan do pliku
#
#   perl test/raport.pl
#
# Zbiera: kontrole plikow, stan moda, delte, triage logu i wersje gry,
# i zapisuje do data/raport.txt. Pomyslane tak, zeby czlowiek odpalil jedno
# polecenie, a druga strona (asystent) przeczytala plik z dysku - bez
# przeklejania, bez opisywania z pamieci.
#
# Dodatkowo archiwizuje game.log, bo kasuje sie przy kazdym starcie gry.

use strict; use warnings;
use POSIX qw(strftime);

use File::Basename; use Cwd qw(abs_path);
my $ROOT = abs_path(dirname(abs_path($0)) . "/..");
$ROOT = '.' unless length $ROOT;
my $PATCH = 'C:/Users/PC/Documents/goh-hf-patch';
my $MOD   = 'C:/Program Files (x86)/Steam/steamapps/workshop/content/400750/3359417100';
my $GAME  = 'C:/Program Files (x86)/Steam/steamapps/common/Call to Arms - Gates of Hell';
my $LOG   = "$ENV{USERPROFILE}/Documents/My Games/gates of hell/log/game.log";
my $OUT   = "$ROOT/data/raport.txt";

mkdir "$ROOT/data" unless -d "$ROOT/data";
open(my $R, '>', $OUT) or die "$OUT: $!";
sub say_ { print $R "$_[0]\n"; print "$_[0]\n" }
sub hdr  { say_(''); say_("=" x 64); say_(" $_[0]"); say_("=" x 64) }

say_("RAPORT  " . strftime("%Y-%m-%d %H:%M:%S", localtime));

# ---------- wersje ----------
hdr("WERSJE");
my $acf = "$GAME/../../appmanifest_400750.acf";
if (open(my $h, '<', $acf)) { local $/; my $t = <$h>; close $h;
    say_("  gra buildid : " . ($t =~ /"buildid"\s+"(\d+)"/ ? $1 : '?'));
    my %b; $b{$1}=1 while $t =~ /"BetaKey"\s+"([^"]+)"/g;
    say_("  galezie     : " . join(', ', sort keys %b));
}
for my $p ("$MOD/resource/gamelogic.pak", "$MOD/resource/map/multi.pak") {
    next unless -f $p;
    my @s = stat $p;
    say_(sprintf("  %-22s %s", (split m{/}, $p)[-1], strftime("%Y-%m-%d %H:%M", localtime $s[9])));
}
my $run = `tasklist /FI "IMAGENAME eq call_to_arms.exe" 2>/dev/null`;
say_("  gra          : " . ($run =~ /call_to_arms/ ? "URUCHOMIONA" : "zamknieta"));

# ---------- kontrola plikow ----------
hdr("KONTROLA PLIKOW (preflight)");
say_($_) for split /\n/, `perl "$ROOT/test/preflight.pl" 2>&1`;

# ---------- delta ----------
hdr("NASZA DELTA");
if (-d "$PATCH/upstream" && -d "$PATCH/resource") {
    my @rel; walk("$PATCH/resource", '', \@rel);
    my $sum = 0;
    for my $rel (sort @rel) {
        next unless -f "$PATCH/upstream/$rel";
        my $d = () = `diff "$PATCH/upstream/$rel" "$PATCH/resource/$rel" 2>/dev/null` =~ /^[<>]/mg;
        $sum += $d;
        say_(sprintf("  %-54s %4d linii", $rel, $d));
    }
    say_(''); say_("  RAZEM: $sum linii");
} else { say_("  brak upstream/ - odpal test/snapshot-upstream.pl") }

# ---------- log ----------
hdr("GAME.LOG");
if (-f $LOG) {
    my @s = stat $LOG;
    say_(sprintf("  z %s, %d B", strftime("%Y-%m-%d %H:%M", localtime $s[9]), $s[7]));
    open(my $h, '<', $LOG) or die; my @t = <$h>; close $h;
    my %c;
    for (@t) {
        $c{crash}++   if /\*{5} Exception/;
        $c{spawn}++   if /can't spawn entity/;
        $c{breed}++   if /no breed found/;
        $c{unitmgr}++ if /not registerd in unit/;
    }
    say_('');
    say_(sprintf("  crashe            : %d", $c{crash}   // 0));
    say_(sprintf("  can't spawn       : %d", $c{spawn}   // 0));
    say_(sprintf("  no breed found    : %d   (szum)", $c{breed} // 0));
    say_(sprintf("  not registerd     : %d   (szum)", $c{unitmgr} // 0));

    if ($c{crash}) {
        say_(''); say_("  --- CRASH ---");
        for my $i (0 .. $#t) {
            next unless $t[$i] =~ /\*{5} Exception/;
            say_("  $_") for map { s/\s+$//r } @t[$i .. ($i+18 > $#t ? $#t : $i+18)];
            last;
        }
    }
    my @e = grep { /can't spawn entity|Remap actor_id/ } @t;
    if (@e) {
        say_(''); say_("  --- encje (ostatnie 20) ---");
        say_("  " . ($_ =~ s/\s+$//r)) for @e[($#e > 19 ? $#e-19 : 0) .. $#e];
    }
    # archiwum
    my $d = "$ROOT/data/logi"; mkdir $d unless -d $d;
    my $n = "$d/game_" . strftime("%m%d_%H%M", localtime) . ".log";
    if (open(my $w, '>', $n)) { print $w @t; close $w; say_(''); say_("  kopia: $n") }
} else { say_("  brak logu") }

close $R;
print "\n\nzapisane: $OUT\n";

sub walk { my ($d,$pre,$o) = @_;
    opendir(my $h,$d) or return;
    for my $e (grep { !/^\.\.?$/ } readdir $h) {
        my $p = "$d/$e"; my $r = $pre ? "$pre/$e" : $e;
        -d $p ? walk($p,$r,$o) : push @$o, $r;
    }
    closedir $h;
}
