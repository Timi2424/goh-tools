#!/usr/bin/perl
# straznik.pl - hook PreToolUse Claude Code: nic nie trafia do gry ani modow z pominieciem narzedzi
#
#   perl hooks/straznik.pl [<projekt>/straznik.conf]      (JSON hooka na stdin)
#
# Blokada = kod 2 + powod na stderr (Claude Code pokazuje go asystentowi i nie
# wykonuje narzedzia). Kazdy inny przypadek - kod 0.
#
# PO CO
# Zmiany w grze powinny isc jedna droga: repo projektu -> skrypt wdrozenia, ktory
# wie, co wdrozono (i np. zapisuje przebieg testu). Reczne cp do katalogu moda omija
# to wszystko - tak w goh-hf-patch ginely przebiegi testow, a inna sesja nadpisala
# i skasowala plik eksperymentu. Do tego kopie zapasowe w katalogach gry: wracaly
# ze Steam Cloud i psuly gre.
#
# CO BLOKUJE
#   Write/Edit pliku pod chroniona sciezka (poza wyjatkami)
#   Bash/PowerShell, ktory dotyka chronionej sciezki i cos tam zapisuje/kasuje
#     (cp, mv, rm, tee, >, sed -i, perl -i, Copy-Item, Set-Content...), chyba ze
#     wola skrypt z listy "dozwolone"
# Czytanie (cat, grep, cmp, unzip -p, ls, Read) zawsze przechodzi.
#
# WYJSCIE AWARYJNE: komentarz "# straznik: <powod>" w komendzie - przepuszcza
# i dopisuje wpis do logu (data, powod, komenda).
#
# KONFIGURACJA (plik projektu, linie "klucz: wartosc", # = komentarz):
#   chronione:  <sciezka>     katalog chroniony (mozna wiele; dokleja sie do domyslnych)
#   wyjatek:    <sciezka>     podkatalog chroniony, w ktorym wolno pisac
#   dozwolone:  <nazwa>       skrypt projektu, ktory wolno wolac na chronionych sciezkach
#   log:        <sciezka>     log wyjatkow (wzgledna = wzgledem pliku konfiguracji)
#   podpowiedz: <tekst>       dopisywane do komunikatu blokady (np. jak wdrazac)
# Bez konfiguracji: domyslne sciezki ponizej, log w ~/.claude/straznik.log.

use strict; use warnings;
use JSON::PP;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use POSIX qw(strftime);

# Domyslnie: instalacja gry i wszystkie mody z Workshopu (400750 = Gates of Hell).
my @chronione = (
    'C:/Program Files (x86)/Steam/steamapps/common/Call to Arms - Gates of Hell/',
    'C:/Program Files (x86)/Steam/steamapps/workshop/content/400750/',
);
my @wyjatki   = ('C:/Program Files (x86)/Steam/steamapps/common/Call to Arms - Gates of Hell/.claude/');
my @dozwolone;
my @podpowiedzi;
my $log = ($ENV{HOME} // $ENV{USERPROFILE} // '.') . '/.claude/straznik.log';

if (my $conf = shift @ARGV) {
    if (open my $h, '<', $conf) {
        while (<$h>) {
            s/\r?\n$//; next if /^\s*(#|$)/;
            my ($k, $v) = /^\s*(\w+):\s*(.*?)\s*$/ or next;
            push @chronione, $v      if $k eq 'chronione';
            push @wyjatki, $v        if $k eq 'wyjatek';
            push @dozwolone, $v      if $k eq 'dozwolone';
            push @podpowiedzi, $v    if $k eq 'podpowiedz';
            $log = ($v =~ m{^(/|[a-z]:)}i ? $v : dirname(abs_path($conf)) . "/$v") if $k eq 'log';
        }
        close $h;
    }
}

# postac porownawcza: male litery, "/", bez litery dysku (/c/... i c:/... -> /...)
sub norm {
    my $s = lc shift;
    $s =~ s{\\}{/}g;
    $s =~ s{(?:^|(?<=[\s"'=]))(?:/([a-z])/|([a-z]):/)}{/}g;
    $s;
}
my @CH = map { norm($_) =~ s{^/}{}r } @chronione;      # bez wiodacego "/" - pasuje w srodku komendy
my @WY = map { norm($_) =~ s{^/}{}r } @wyjatki;

sub blokuj {
    my $msg = shift;
    $msg .= "\n" . join("\n", @podpowiedzi) if @podpowiedzi;
    print STDERR "STRAZNIK (goh-tools/hooks/straznik.pl): $msg\n";
    exit 2;
}

my $in = do { local $/; <STDIN> } // '';
my $j = eval { decode_json($in) } or exit 0;      # nie nasz format - nie przeszkadzamy
my $tool = $j->{tool_name} // '';
my $ti   = $j->{tool_input} // {};

if ($tool eq 'Write' || $tool eq 'Edit' || $tool eq 'NotebookEdit') {
    my $p = norm($ti->{file_path} // '');
    exit 0 if grep { index($p, $_) >= 0 } @WY;
    blokuj("bezposredni zapis pod chroniona sciezka: $ti->{file_path}\n"
         . "Zmiane zrob w repo projektu i wdroz jego skryptem. Kopie zapasowe nie w katalogach gry.")
        if grep { index($p, $_) >= 0 } @CH;
    exit 0;
}

if ($tool eq 'Bash' || $tool eq 'PowerShell') {
    my $raw = $ti->{command} // '';
    my $cmd = norm($raw);
    my $bez = $cmd;
    for my $w (@WY) { $bez =~ s/\Q$w\E\S*//g }          # wyjatki (np. .claude gry) nie licza sie
    exit 0 unless grep { index($bez, $_) >= 0 } @CH;

    my $zapis = qr{(?:^|[\s;&|(])(?:cp|mv|rm|rmdir|install|rsync|tee|truncate|touch|mkdir|ln|unzip\s+-o)\s
                  |\b(?:sed|perl)\s+(?:-\w+\s+)*-\w*i
                  |\b(?:copy-item|move-item|remove-item|set-content|add-content|out-file|new-item|rename-item)\b}xi;
    # przekierowanie liczy sie tylko wtedy, gdy jego CEL jest pod chroniona sciezka
    my $przekierowanie = 0;
    while ($bez =~ /(?<![0-9&])>>?\s*("[^"]*"|'[^']*'|[^\s&|;]+)/g) {
        my $cel = $1;
        $przekierowanie = 1 if grep { index($cel, $_) >= 0 } @CH;
    }
    exit 0 unless $przekierowanie || $bez =~ $zapis;
    for my $d (@dozwolone) { exit 0 if index($cmd, lc $d) >= 0 }

    if ($raw =~ /#\s*straznik:\s*(\S.*)$/m) {
        my $powod = $1;
        if (open my $w, '>>', $log) {
            print $w strftime('%Y-%m-%d %H:%M:%S', localtime), "\t$powod\t", ($raw =~ s/\s+/ /gr), "\n";
            close $w;
        }
        exit 0;
    }
    blokuj("komenda zapisuje/kasuje pod chroniona sciezka (gra/mody) z pominieciem narzedzi.\n"
         . (@dozwolone ? "Dozwolone skrypty: @dozwolone. " : '')
         . "Czytanie rozdziel do osobnej komendy. Swiadomy wyjatek: dopisz "
         . "'# straznik: <powod>' (trafi do $log).");
}
exit 0;
