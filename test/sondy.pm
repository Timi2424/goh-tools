package sondy;
# sondy.pm - wzorce, po ktorych w logu rozpoznajemy, ze kod DOSZEDL do silnika
#
# Wspolne dla raport.pl i lab.pl. Bloki do wklejania w pliki gry: sondy.inc.
#
# Reszta logu mowi, co sie zepsulo; sondy mowia, co sie wykonalo. Cisza w logu
# nie odroznia sukcesu od porazki - udany spawn, emit i przypisanie wlasciciela
# nie loguja niczego.

use strict; use warnings;

# [ nazwa, wzorzec, co znaczy, ile wierszy kontekstu po trafieniu ]
# Blad parsowania ma 20: sciezka ladowania, plik i numer linii z tokenem <<
# sa w wierszach PO komunikacie.
our @WZORCE = (
    ['plik zyje (blad parsowania)' => qr/unexpected token/,       'ladowanie dotarlo do pliku',     20],
    ['sonda waypointa'             => qr/Waypoint \S+ not found/, 'akcja triggera sie wykonala',     0],
    ['sonda kosci'                 => qr/Bone \S+ not found/,     'skrypt encji doszedl do spawnu',  0],
    ['nieznana komenda skryptu'    => qr/unknown script command/, 'nazwa akcji nie istnieje',        0],
    ['nieznany squad'              => qr/Squad "\S+" not found/,  'akcja squad sie wykonala',        0],
    ['nasz znacznik hf_sonda'      => qr/hf_sonda/i,              'cokolwiek nazwanego hf_sonda',    0],
);

# Zwraca liste trafien: { nazwa, znaczy, ile, kontekst => [wiersze] }
sub szukaj {
    my ($wiersze) = @_;
    my @out;
    for my $s (@WZORCE) {
        my ($nazwa, $re, $znaczy, $ctx) = @$s;
        my @idx = grep { $wiersze->[$_] =~ $re } 0 .. $#$wiersze;
        next unless @idx;
        my $i = $idx[0];
        my $do = $i + $ctx; $do = $#$wiersze if $do > $#$wiersze;
        push @out, { nazwa => $nazwa, znaczy => $znaczy, ile => scalar @idx,
                     kontekst => [ map { s/\s+$//r } @{$wiersze}[$i .. $do] ] };
    }
    @out;
}

1;
