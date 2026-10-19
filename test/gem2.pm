package gem2;
# gem2.pm - parser formatu GEM2 i wyluskiwanie nazw akcji oraz termow.
#
# Wydzielone z sprawdz-slownik.pl, bo preflight.pl potrzebuje dokladnie tej
# samej roboty. Dwie kopie parsera rozjechalyby sie przy pierwszej poprawce,
# a wtedy jedno narzedzie milczy tam, gdzie drugie krzyczy.
#
# Regexem tego sie nie da: {"nazwa"} w .mi to raz akcja triggera, a raz nazwa
# jednostki w rejestrze DLC. Trzeba sparsowac drzewo {} i patrzec na sciezke.
#
# Dwie gramatyki:
#
#   skrypt misji (.mi)         {triggers {"nazwa_triggera"
#                                  {condition {terms {"1.event" ...}}}
#                                  {"fade" {time 3}}          <- akcja, w cudzyslowie
#                                  {trigger_on_next "..."}    <- wlasciwosc, goly token
#                              }}
#
#   skrypt encji (.inc/.set)   {"nazwa_bloku"
#                                  {on spawn
#                                      {link_sound "fall" "..."}   <- akcja, goly token
#                                  }
#                              }

use strict; use warnings;

# ---------- parser ----------
# Komentarz: ';' do konca linii. Token: {, }, "napis", goly ciag.
#
# Komentarze wycinamy bez zjadania '\n', wiec liczba nowych linii przed danym
# offsetem w tekscie obcietym jest ta sama co w oryginale - numery linii zgadzaja
# sie mimo przesunietych offsetow.
sub bez_komentarzy { my $t = shift; $t =~ s/;[^\n]*//g; $t }

sub parse {
    my $txt = bez_komentarzy(shift);
    my @stack = ({ head => '', q => 0, kids => [] });
    my $root = $stack[0];
    while ($txt =~ /\G(?:\s+|(\{)|(\})|"([^"]*)"|([^\s{}"]+))/gc) {
        if (defined $1) {
            my $n = { head => undef, q => 0, kids => [] };
            push @{$stack[-1]{kids}}, $n;
            push @stack, $n;
        }
        elsif (defined $2) { pop @stack if @stack > 1 }
        else {
            my ($v,$q,$off) = defined $3 ? ($3,1,$-[3]) : ($4,0,$-[4]);
            my $n = $stack[-1];
            if (!defined $n->{head}) { $n->{head} = $v; $n->{q} = $q; $n->{off} = $off }
            else { push @{$n->{kids}}, { head => $v, q => $q, off => $off, kids => [], leaf => 1 } }
        }
    }
    $root;
}

sub kids_named {
    my ($n,$name) = @_;
    grep { !$_->{leaf} && defined $_->{head} && !$_->{q} && $_->{head} eq $name } @{$n->{kids}};
}

sub walk {                      # walk($node, sub { ... })
    my ($n,$cb) = @_;
    $cb->($n);
    walk($_,$cb) for grep { !$_->{leaf} } @{$n->{kids}};
}

sub ident { my $v = shift; defined $v && $v =~ /^[a-z_][a-z0-9_]*$/ }

# Tylko bezposrednie dzieci {on ...} i akcji sterujacych sa akcjami. Glebiej
# siedza juz parametry danej akcji - {health_damage_pierce {effects ...}} to
# parametr, nie akcja, i wrzucanie go do porownania zasmieca wynik.
sub is_container { my $v = shift; $v =~ /^(?:on|if|else|elif|with_\w+|for_each_\w+)$/ }

# ---------- wyluskiwanie nazw ----------
# zwraca { mi => 0/1, ent => 0/1, uzycia => [ {nazwa, rodzaj, off}, ... ] }
# rodzaj: 'akcja_mi' | 'term_mi' | 'akcja_encji'
sub uzycia {
    my $txt = shift;
    my %out = (mi => 0, ent => 0, uzycia => []);
    return \%out unless $txt =~ /\{/;
    my $root = parse($txt);
    my $add = sub { push @{$out{uzycia}}, { nazwa => $_[0], rodzaj => $_[1], off => $_[2] } };

    walk($root, sub {
        my $n = shift;
        for my $trg (kids_named($n,'triggers')) {
            $out{mi} = 1;
            for my $t (@{$trg->{kids}}) {
                next if $t->{leaf};
                for my $acts (kids_named($t,'actions')) {
                    for my $c (@{$acts->{kids}}) {
                        next if $c->{leaf} || !defined $c->{head};
                        my ($nm,$q,$off) = ($c->{head}, $c->{q}, $c->{off});
                        # edytor wylacza akcje, wstawiajac '##' przed nazwa
                        if (!$q && $nm eq '##' && @{$c->{kids}} && $c->{kids}[0]{q}) {
                            ($nm,$q,$off) = ($c->{kids}[0]{head}, 1, $c->{kids}[0]{off});
                        }
                        $add->($nm,'akcja_mi',$off) if $q && ident($nm);
                    }
                }
                # termy warunku
                for my $cond (kids_named($t,'condition')) {
                    for my $terms (kids_named($cond,'terms')) {
                        for my $tm (@{$terms->{kids}}) {
                            next if $tm->{leaf} || !defined $tm->{head};
                            $add->($1,'term_mi',$tm->{off})
                                if $tm->{head} =~ /^\d+\.([a-z_][a-z0-9_]*)$/;
                        }
                    }
                }
            }
        }
    });

    # skrypt encji: {"blok" {on ... {akcja ...}}}
    my $zbierz;
    $zbierz = sub {
        my $n = shift;
        for my $k (@{$n->{kids}}) {
            next if $k->{leaf} || $k->{q} || !ident($k->{head});
            $add->($k->{head},'akcja_encji',$k->{off});
            $zbierz->($k) if is_container($k->{head});
        }
    };
    for my $blk (@{$root->{kids}}) {
        next if $blk->{leaf} || !$blk->{q};
        for my $on (kids_named($blk,'on')) {
            $out{ent} = 1;
            $zbierz->($on);
        }
    }
    \%out;
}

# Offset -> numer linii. Tablica nowych linii liczona raz na plik, bo liczenie
# od poczatku przy kazdym trafieniu zabija przebieg po calym korpusie.
sub indeks_linii {
    # offsety z parse() licza sie w tekscie po wycieciu komentarzy, wiec indeks
    # musi powstac z tego samego tekstu - inaczej numery linii uciekaja
    my $txt = bez_komentarzy(shift);
    my @nl;
    while ($txt =~ /\n/g) { push @nl, $-[0] }
    \@nl;
}
sub linia {
    my ($nl,$off) = @_;
    return 0 unless defined $off;
    my ($lo,$hi) = (0, scalar @$nl);
    while ($lo < $hi) {
        my $mid = int(($lo+$hi)/2);
        if ($nl->[$mid] < $off) { $lo = $mid+1 } else { $hi = $mid }
    }
    $lo + 1;
}

# ---------- slownik z binarki ----------
# format: '=== 0x... <modul.cpp> wpisow: N', potem wpisy wciete dwiema spacjami
sub wczytaj_slownik {
    my $plik = shift;
    open my $d, '<', $plik or return undef;
    my (%known, %mod_of);
    my $mod = '?';
    while (<$d>) {
        if (/^=== 0x\w+\s+(\S+)/) { $mod = $1; next }
        next unless /^  (\S+)\s/;
        $known{$1} = 1;
        $mod_of{$1}{$mod} = 1;
    }
    close $d;
    return (\%known, \%mod_of);
}

1;
