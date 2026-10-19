#!/usr/bin/perl
# sprawdz-slownik.pl - konfrontuje slownik wyciagniety z binarki z tym, co
# naprawde stoi w plikach gry.
#
#   perl test/sprawdz-slownik.pl data/slownik/tablice.txt <katalog> [<katalog>...]
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
#
# Kierunek, ktory naprawde cos mowi: UZYTE, A NIE MA W SLOWNIKU. Taka nazwa
# znaczy, ze ekstrakcja ma dziure i slownikowi nie wolno ufac. Odwrotny kierunek
# (w slowniku, nieuzyte) nie jest bledem - silnik zna wiecej, niz kampania wola.

use strict; use warnings;
use File::Find;

my ($dict, @dirs) = @ARGV;
die "uzycie: perl test/sprawdz-slownik.pl <tablice.txt> <katalog> [...]\n"
    unless $dict && @dirs;

# ---------- slownik ----------
my (%known, %mod_of);
{
    open my $d, '<', $dict or die "$dict: $!\n";
    my $mod = '?';
    while (<$d>) {
        if (/^=== 0x\w+\s+(\S+)/) { $mod = $1; next }
        next unless /^  (\S+)\s/;
        $known{$1} = 1;
        $mod_of{$1}{$mod} = 1;
    }
    close $d;
}
printf "slownik : %d nazw (%s)\n", scalar keys %known, $dict;

# ---------- parser formatu GEM2 ----------
# Komentarz: ';' do konca linii. Token: {, }, "napis", goly ciag.
sub parse {
    my $txt = shift;
    $txt =~ s/;[^\n]*//g;
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
            my ($v,$q) = defined $3 ? ($3,1) : ($4,0);
            my $n = $stack[-1];
            if (!defined $n->{head}) { $n->{head} = $v; $n->{q} = $q }
            else { push @{$n->{kids}}, { head => $v, q => $q, kids => [], leaf => 1 } }
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

my %act_ent;
# Tylko bezposrednie dzieci {on ...} i akcji sterujacych sa akcjami. Glebiej
# siedza juz parametry danej akcji - {health_damage_pierce {effects ...}} to
# parametr, nie akcja, i wrzucanie go do porownania zasmieca wynik.
sub is_container { my $v = shift; $v =~ /^(?:on|if|else|elif|with_\w+|for_each_\w+)$/ }
sub collect_actions {
    my ($n,$f) = @_;
    for my $k (@{$n->{kids}}) {
        next if $k->{leaf} || $k->{q} || !ident($k->{head});
        $act_ent{$k->{head}}{$f} = 1;
        collect_actions($k,$f) if is_container($k->{head});
    }
}

# ---------- korpus ----------
my @files;
for my $dir (@dirs) { find(sub { push @files, $File::Find::name if -f }, $dir) }

my (%act_mi, %term_mi);
my ($n_mi, $n_ent, $bytes) = (0,0,0);
for my $f (@files) {
    next unless $f =~ /\.(mi|inc|set)$/i;
    open my $h, '<:raw', $f or next;
    my $txt = do { local $/; <$h> }; close $h;
    next unless $txt =~ /\{/;
    $bytes += length $txt;
    my $root = parse($txt);

    my $hit_mi = 0;
    walk($root, sub {
        my $n = shift;
        for my $trg (kids_named($n,'triggers')) {
            $hit_mi = 1;
            for my $t (@{$trg->{kids}}) {
                next if $t->{leaf};
                for my $acts (kids_named($t,'actions')) {
                    for my $c (@{$acts->{kids}}) {
                        next if $c->{leaf} || !defined $c->{head};
                        my ($nm,$q) = ($c->{head}, $c->{q});
                        # edytor wylacza akcje, wstawiajac '##' przed nazwa
                        if (!$q && $nm eq '##' && @{$c->{kids}} && $c->{kids}[0]{q}) {
                            ($nm,$q) = ($c->{kids}[0]{head}, 1);
                        }
                        $act_mi{$nm}{$f} = 1 if $q && ident($nm);
                    }
                }
                # termy warunku
                for my $cond (kids_named($t,'condition')) {
                    for my $terms (kids_named($cond,'terms')) {
                        for my $tm (@{$terms->{kids}}) {
                            next if $tm->{leaf} || !defined $tm->{head};
                            $term_mi{$1}{$f} = 1 if $tm->{head} =~ /^\d+\.([a-z_][a-z0-9_]*)$/;
                        }
                    }
                }
            }
        }
    });
    $n_mi++ if $hit_mi;

    # skrypt encji: {"blok" {on ... {akcja ...}}}
    my $hit_ent = 0;
    for my $blk (@{$root->{kids}}) {
        next if $blk->{leaf} || !$blk->{q};
        for my $on (kids_named($blk,'on')) {
            $hit_ent = 1;
            collect_actions($on, $f);
        }
    }
    $n_ent++ if $hit_ent;
}
printf "korpus  : %.1f MB, %d plikow misji, %d plikow interakcji\n\n",
    $bytes/1048576, $n_mi, $n_ent;

# ---------- raport ----------
my $gaps = 0;
sub report {
    my ($title, $used, %o) = @_;
    my @miss = sort grep { !$known{$_} } keys %$used;
    printf "## %s - uzyte: %d, w tym spoza slownika: %d\n", $title, scalar keys %$used, scalar @miss;
    for my $n (@miss) {
        my @f = sort keys %{$used->{$n}};
        printf "   %-26s %3d plik(ow)  np. %s\n", $n, scalar @f, short($f[0]);
    }
    print "\n";
    $gaps += @miss unless $o{soft};
    return @miss;
}
sub short { my $p = shift; $p =~ s{.*[/\\]([^/\\]+[/\\][^/\\]+)$}{$1}; $p }

report('AKCJE TRIGGEROW (.mi)', \%act_mi);
report('TERMY WARUNKOW (.mi)',  \%term_mi);
report('AKCJE SKRYPTOW ENCJI (.inc/.set)', \%act_ent);

my %used = (%act_mi, %term_mi, %act_ent);
my @conf = sort grep { $used{$_} } keys %known;
printf "## potwierdzone w plikach gry: %d z %d nazw slownika\n\n", scalar @conf, scalar keys %known;

printf "WYNIK: %s\n", $gaps ? "$gaps nazw uzytych poza slownikiem - ekstrakcja ma dziure"
                            : 'slownik pokrywa kazda nazwe uzyta w korpusie';
exit($gaps ? 1 : 0);
