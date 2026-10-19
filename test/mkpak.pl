#!/usr/bin/perl
# Sklada .pak z katalogu. Pak to zwykly ZIP; zapisujemy bez kompresji (metoda
# "stored"), bo tak trzyma je sama gra i nie trzeba zadnych bibliotek.
#
#   perl test/mkpak.pl <katalog> <wyjscie.pak>
#
# Sciezki w archiwum sa wzgledne wobec <katalog>, z ukosnikami w przod.
# Pliki trafiaja do archiwum bajt w bajt - zadnego tlumaczenia koncow linii.

use strict;
use warnings;

my ($dir, $out) = @ARGV;
die "uzycie: perl test/mkpak.pl <katalog> <wyjscie.pak>\n" unless $dir && $out;
die "nie ma katalogu: $dir\n" unless -d $dir;

# ---- CRC32 ----
my @CRC;
for my $n (0 .. 255) {
    my $c = $n;
    $c = ($c & 1) ? (0xedb88320 ^ ($c >> 1)) : ($c >> 1) for 1 .. 8;
    $CRC[$n] = $c;
}
sub crc32 {
    my $c = 0xffffffff;
    $c = $CRC[($c ^ $_) & 0xff] ^ ($c >> 8) for unpack 'C*', $_[0];
    return $c ^ 0xffffffff;
}

# ---- zbierz pliki ----
my @files;
sub walk {
    my $d = shift;
    opendir(my $h, $d) or die "nie moge otworzyc $d: $!\n";
    for my $e (sort grep { !/^\.\.?$/ } readdir $h) {
        my $p = "$d/$e";
        -d $p ? walk($p) : push @files, $p;
    }
    closedir $h;
}
walk($dir);
die "katalog jest pusty: $dir\n" unless @files;

# ---- data/czas w formacie DOS ----
my @t = localtime;
my $dtime = ($t[2] << 11) | ($t[1] << 5) | int($t[0] / 2);
my $ddate = (($t[5] + 1900 - 1980) << 9) | (($t[4] + 1) << 5) | $t[3];

open(my $zip, '>:raw', $out) or die "nie moge zapisac $out: $!\n";
my (@central, $offset);
$offset = 0;

for my $f (@files) {
    open(my $in, '<:raw', $f) or die "nie moge czytac $f: $!\n";
    my $data = do { local $/; <$in> };
    close $in;

    (my $name = $f) =~ s/^\Q$dir\E\/?//;
    $name =~ s/\\/\//g;

    my $crc = crc32($data);
    my $len = length $data;

    my $local = pack('V v v v v v V V V v v',
        0x04034b50, 20, 0, 0, $dtime, $ddate, $crc, $len, $len,
        length($name), 0);
    print $zip $local, $name, $data;

    push @central, pack('V v v v v v v V V V v v v v v V V',
        0x02014b50, 20, 20, 0, 0, $dtime, $ddate, $crc, $len, $len,
        length($name), 0, 0, 0, 0, 0, $offset) . $name;

    $offset += length($local) + length($name) + $len;
    printf "  %-52s %8d B\n", $name, $len;
}

my $cd = join '', @central;
print $zip $cd;
print $zip pack('V v v v v V V v',
    0x06054b50, 0, 0, scalar(@central), scalar(@central),
    length($cd), $offset, 0);
close $zip;

printf "\n%s: %d plikow, %d B\n", $out, scalar(@files), -s $out;
