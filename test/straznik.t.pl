#!/usr/bin/perl
# straznik.t.pl - testy hooks/straznik.pl
#
#   perl test/straznik.t.pl
#
# Wejscie hooka generujemy encode_json - recznie sklejany JSON w powloce gubil
# ukosniki i dawal niepoprawne wejscie, na ktore straznik (celowo) nie reaguje.

use strict; use warnings;
use JSON::PP; use IPC::Open3; use FindBin; use File::Temp qw(tempdir);

my $H  = "$FindBin::Bin/../hooks/straznik.pl";
my $MW = 'C:\\Program Files (x86)\\Steam\\steamapps\\workshop\\content\\400750\\3359417100\\resource';
my $MB = '/c/Program Files (x86)/Steam/steamapps/workshop/content/400750/3359417100/resource';
my $GB = '/c/Program Files (x86)/Steam/steamapps/common/Call to Arms - Gates of Hell';

my $tmp  = tempdir(CLEANUP => 1);
my $conf = "$tmp/straznik.conf";
open my $c, '>', $conf or die; print $c <<'K'; close $c;
# konfiguracja testowa projektu
chronione: D:/projekt/wdrozone/
dozwolone: wdroz.sh
log: straznik.log
podpowiedz: Wdrazaj: bash wdroz.sh
K

sub bash { { tool_name => 'Bash', tool_input => { command => shift } } }
my @t = (
 # [oczekiwany kod, opis, wejscie, konfiguracja?]
 [2, 'Write do moda (Windows)',   { tool_name=>'Write', tool_input=>{file_path=>"$MW\\set\\x.set"}}],
 [2, 'Edit do gry',               { tool_name=>'Edit',  tool_input=>{file_path=>'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Call to Arms - Gates of Hell\\resource\\a.bak'}}],
 [0, 'Write .claude gry',         { tool_name=>'Write', tool_input=>{file_path=>'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Call to Arms - Gates of Hell\\.claude\\settings.local.json'}}],
 [0, 'Edit poza gra',             { tool_name=>'Edit',  tool_input=>{file_path=>'C:\\Users\\X\\repo\\SPEC.md'}}],
 [0, 'Read z moda',               { tool_name=>'Read',  tool_input=>{file_path=>"$MW\\set\\x.set"}}],
 [2, 'cp do moda',                bash("M=\"$MB\"; cp a.def \"\$M/entity/a.def\"")],
 [0, 'cmp z moda',                bash("cmp \"$MB/x\" y")],
 [0, 'unzip -p, wynik gdzie indziej', bash("unzip -p \"$MB/map/multi.pak\" a | grep b > /tmp/x")],
 [2, 'przekierowanie do gry',     bash("echo x > \"$GB/resource/a.bak\"")],
 [0, 'ls gry',                    bash("ls -la \"$GB/\"")],
 [2, 'PowerShell Copy-Item',      { tool_name=>'PowerShell', tool_input=>{command=>"Copy-Item a.def \"$MW\\a.def\""}}],
 [2, 'perl -i w modzie',          bash("perl -pi -e s/a/b/ \"$MB/x.set\"")],
 [0, 'wyjatek z powodem',         bash("rm \"$MB/x\" # straznik: test")],
 [2, 'cudzy mod (domyslnie caly 400750)', bash('cp a "/c/Program Files (x86)/Steam/steamapps/workshop/content/400750/123/resource/a"')],
 # z konfiguracja projektu
 [0, 'conf: skrypt dozwolony',    bash("bash wdroz.sh \"$MB\" && cp x \"$MB/y\""), 1],
 [2, 'conf: dodatkowa sciezka',   bash('cp a "D:/projekt/wdrozone/a"'), 1],
 [0, 'conf: wyjatek -> log projektu', bash("rm \"$MB/x\" # straznik: test conf"), 1],
);

# log wyjatkow bez konfiguracji idzie do ~/.claude - w tescie do katalogu tymczasowego
local $ENV{HOME} = $tmp; local $ENV{USERPROFILE} = $tmp;
my $bad = 0;
for my $t (@t) {
    my ($want, $name, $in, $z_conf) = @$t;
    my $pid = open3(my $wr, my $rd, undef, 'perl', $H, ($z_conf ? $conf : ()));
    print $wr encode_json($in); close $wr; my $o = do { local $/; <$rd> }; waitpid $pid, 0;
    my $kod = $? >> 8;
    printf "%s kod %d (oczek. %d)  %s\n", ($kod == $want ? 'ok  ' : 'ZLE '), $kod, $want, $name;
    $bad++ if $kod != $want;
}
if (-f "$tmp/straznik.log") { print "ok   log projektu zapisany\n" } else { print "ZLE  brak logu projektu\n"; $bad++ }
print "bledow: $bad\n";
exit($bad ? 1 : 0);
