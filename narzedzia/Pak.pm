package Pak;
# Pak.pm - czytanie plikow z pakow GEM2 (.pak = ZIP, paki gry ZIP64) bez uruchamiania unzip.
#
#   use lib '/c/Users/PC/Documents/goh-tools/narzedzia'; use Pak;
#   my $tekst = Pak::czytaj($sciezka_paka, 'set/breed/mp/ger/mid/engineer_1.set');
#   my @nazwy = Pak::lista($sciezka_paka);
#
# Pak jest otwierany raz (spis plikow w pamieci), kolejne odczyty to seek + inflate.
# 2026-10-24: generator fortyfikacji wolal `unzip -p` osobno dla kazdego pliku (setki procesow
# z konsola, kazdy od nowa czyta spis paka) - przy wlaczonej grze Windows tracil zasoby pulpitu
# (czarny pasek zadan). Kod spisu i odczytu jak w podglad.pl (zip_open / zip_read).
use strict;
use warnings;
use Compress::Raw::Zlib ();

my %OTWARTE;   # sciezka paka -> { fh, e => { lc nazwa -> [offset, rozm. skompr., rozm., metoda, nazwa] } }

sub otworz {
    my ($path) = @_;
    return $OTWARTE{$path} if $OTWARTE{$path};
    open my $fh, '<:raw', $path or die "nie moge otworzyc $path: $!\n";
    my $size = -s $fh;
    my $tail = $size < 70000 ? $size : 70000;
    seek $fh, $size - $tail, 0;
    my $buf; read $fh, $buf, $tail;
    my $i = rindex $buf, "PK\x05\x06";
    die "$path: brak katalogu ZIP\n" if $i < 0;
    my (undef, undef, undef, undef, $n, $cd_size, $cd_off) = unpack 'VvvvvVV', substr($buf, $i, 20);
    my $l64 = rindex $buf, "PK\x06\x07", $i;    # ZIP64: prawdziwe liczby w EOCD64
    if ($l64 >= 0 && ($cd_off == 0xFFFFFFFF || $n == 0xFFFF || $cd_size == 0xFFFFFFFF)) {
        my $off64 = unpack 'Q<', substr($buf, $l64 + 8, 8);
        seek $fh, $off64, 0;
        my $e64; read $fh, $e64, 56;
        die "$path: zly EOCD64\n" unless substr($e64, 0, 4) eq "PK\x06\x06";
        ($n, $cd_size, $cd_off) = unpack 'Q<Q<Q<', substr($e64, 32, 24);
    }
    seek $fh, $cd_off, 0;
    my $cd; read $fh, $cd, $cd_size;
    my %e;
    my $p = 0;
    for (1 .. $n) {
        my @h = unpack 'VvvvvvvVVVvvvvvVV', substr($cd, $p, 46);
        last unless $h[0] == 0x02014b50;
        my ($meth, $cs, $us, $nl, $xl, $cl, $lo) = @h[4, 8, 9, 10, 11, 12, 16];
        my $name = substr($cd, $p + 46, $nl);
        if ($us == 0xFFFFFFFF || $cs == 0xFFFFFFFF || $lo == 0xFFFFFFFF) {    # pole extra 0x0001
            my $x = substr($cd, $p + 46 + $nl, $xl);
            while (length $x >= 4) {
                my ($id, $sz) = unpack 'vv', $x;
                if ($id == 1) {
                    my @q = unpack 'Q<*', substr($x, 4, $sz);
                    $us = shift @q if $us == 0xFFFFFFFF;
                    $cs = shift @q if $cs == 0xFFFFFFFF;
                    $lo = shift @q if $lo == 0xFFFFFFFF;
                    last;
                }
                $x = substr($x, 4 + $sz);
            }
        }
        $p += 46 + $nl + $xl + $cl;
        next if $name =~ m{/$};
        $name =~ tr{\\}{/};
        $e{lc $name} = [$lo, $cs, $us, $meth, $name];
    }
    return $OTWARTE{$path} = { path => $path, fh => $fh, e => \%e };
}

sub lista { my $z = otworz($_[0]); return map { $_->[4] } values %{ $z->{e} } }

sub jest { my ($pak, $wpis) = @_; return exists otworz($pak)->{e}{lc $wpis} }

sub czytaj {   # tresc pliku z paka; die, gdy go nie ma
    my ($pak, $wpis) = @_;
    my $z = otworz($pak);
    my $e = $z->{e}{lc $wpis} or die "brak $wpis w $pak\n";
    my ($lo, $cs, $us, $meth) = @$e;
    my $fh = $z->{fh};
    seek $fh, $lo, 0;
    my $h; read $fh, $h, 30;
    my ($nl, $xl) = unpack 'vv', substr($h, 26, 4);
    seek $fh, $lo + 30 + $nl + $xl, 0;
    my $data = ''; read $fh, $data, $cs if $cs;
    return $data if $meth == 0;
    die "$pak: $wpis - metoda kompresji $meth\n" unless $meth == 8;
    my ($inf, $st) = Compress::Raw::Zlib::Inflate->new(-WindowBits => -Compress::Raw::Zlib::MAX_WBITS(),
                                                        -Bufsize => $us || 4096);
    my $out = '';
    $st = $inf->inflate($data, $out);
    die "$pak: $wpis - blad inflate $st\n" unless $st == Compress::Raw::Zlib::Z_STREAM_END() || $st == 0;
    return $out;
}

1;
