# goh-tools

Narzędzia do grzebania w **Call to Arms – Gates of Hell: Ostfront** i w modach do niej.
Silnik GEM2.

Formaty danych GEM2 nie są udokumentowane. Nieznana nazwa akcji, termu warunku albo
trybu kończy się ciszą, wpisem w logu albo crashem — bo silnik nie sprawdza wyniku
i dereferencjonuje nulla. Te narzędzia służą do tego, żeby nie zgadywać.

```
pe/      harness do binarki
test/    kontrola plikow przed uruchomieniem, snapshot zrodel, raport
patch/   skrypty do edycji plikow gry
docs/    jak to dziala i czego sie nauczylismy
```

## Dokumentacja

| | |
|---|---|
| [docs/harness.md](docs/harness.md) | praca z binarką: polecenia, metoda, przykłady |
| [docs/testowanie.md](docs/testowanie.md) | **dwie pętle testowe, sondy, kontrola przed startem** |
| [docs/edytor-misji.md](docs/edytor-misji.md) | **oficjalny podręcznik edytora: selektory, warunki, komendy** |
| [docs/proces.md](docs/proces.md) | co robić po patchu gry albo moda |
| [docs/lekcje.md](docs/lekcje.md) | dziesięć rzeczy kupionych crashem |
| [data/slownik/README.md](data/slownik/README.md) | składnia skryptów wyciągnięta z exe: akcje, termy, selektory, enumy |

## Start

```bash
raport.bat                    # caly stan do data/raport.txt
perl test/preflight.pl        # kontrola przed uruchomieniem gry
perl test/kontekst.pl <nazwa> # czy wolno uzyc tej nazwy i w jakim pliku
perl test/sprawdz-plik.pl <plik>  # nawiasy, sklejki, ASCII - jedna kontrola dla wszystkich skryptow
perl test/sprawdz-klucze.pl <plik> # klucze .ext/.def wzgledem plikow gry
perl test/lab.pl start|przeladuj|wynik  # petla laboratorium w edytorze misji
perl pe/goh.pl <exe> info     # binarka
perl pe/slownik.pl <exe> gen data/slownik   # slownik skladni z binarki
```

Dwie rzeczy, które oszczędzają najwięcej czasu:

- **[`test/sondy.inc`](test/sondy.inc)** — gotowe bloki, które zmuszają silnik
  do potwierdzenia, że kod się wykonał. Cisza w logu nie odróżnia sukcesu od
  porażki, więc zanim zaczniesz debugować zachowanie, udowodnij, że kod
  w ogóle dociera do silnika.
- **laboratorium na luźnej mapie** zamiast konkwisty — pętla skraca się
  z kilku minut do kilkunastu sekund. Opis w
  [docs/testowanie.md](docs/testowanie.md), misje w `goh-hf-patch/eksperymenty/lab/`.

Potrzebne: `perl`, `git`, `unzip`.

## Do zrobienia

[Issues](../../issues) — etykiety `modyfikacja`, `harness`, `upstream-fix`.

## Uwaga

Repozytorium zawiera wyłącznie narzędzia i dokumentację. Nie rozpowszechnia zawartości
gry ani cudzych modów — pliki czyta z lokalnej instalacji.
