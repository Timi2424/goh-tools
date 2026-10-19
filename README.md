# goh-tools

Narzędzia do grzebania w **Call to Arms – Gates of Hell: Ostfront** i w modach do niej.
Silnik GEM2.

Formaty danych GEM2 nie są udokumentowane. Nieznana nazwa akcji, termu warunku albo
trybu kończy się ciszą, wpisem w logu albo crashem — bo silnik nie sprawdza wyniku
i dereferencjonuje nulla. Te narzędzia służą do tego, żeby nie zgadywać.

```
pe/      harness do binarki
test/    kontrola plikow przed uruchomieniem, snapshot wersji zrodlowych
gui/     maly panel na codzienna petle
patch/   skrypty do edycji plikow gry
docs/    jak to dziala i czego sie nauczylismy
```

## Dokumentacja

| | |
|---|---|
| [docs/harness.md](docs/harness.md) | praca z binarką: polecenia, metoda, przykłady |
| [docs/testowanie.md](docs/testowanie.md) | pętla edycja → kontrola → gra → log |
| [docs/proces.md](docs/proces.md) | co robić po patchu gry albo moda |
| [docs/lekcje.md](docs/lekcje.md) | dziesięć rzeczy kupionych crashem |
| [gui/README.md](gui/README.md) | panel |

## Start

```bash
gui\panel.bat                 # panel
raport.bat                    # caly stan do data/raport.txt
perl test/preflight.pl        # sama kontrola przed uruchomieniem
perl pe/goh.pl <exe> info     # binarka
```

Potrzebne: `perl`, `git`, `unzip`.

## Do zrobienia

[Issues](../../issues) — etykiety `modyfikacja`, `harness`, `upstream-fix`.

## Uwaga

Repozytorium zawiera wyłącznie narzędzia i dokumentację. Nie rozpowszechnia zawartości
gry ani cudzych modów — pliki czyta z lokalnej instalacji.
