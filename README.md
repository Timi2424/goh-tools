# goh-tools

Narzędzia do grzebania w **Call to Arms – Gates of Hell: Ostfront** i w modach do niej.
Silnik GEM2.

Powstały przy utrzymywaniu własnych modyfikacji do gry w kooperacji — gdzie każdy plik
musi być bit w bit identyczny u obu graczy, a każdy patch gry albo moda potrafi po cichu
cofnąć wcześniejszą pracę.

**Co jest do zrobienia → [Issues](../../issues).**

---

## Po co to jest

Formaty danych GEM2 nie są udokumentowane. Nieznana nazwa akcji, termu warunku albo
trybu kończy się jednym z trzech scenariuszy: cisza (silnik ignoruje), wpis w logu,
albo **crash** — bo silnik nie sprawdza wyniku i dereferencjonuje nulla.

Zamiast zgadywać, wyciąga się słownik prosto z binarki.

---

## Zawartość

```
pe/        harness do binarki - lokalizacja funkcji, stringow, odwolan
test/      kontrola plikow przed uruchomieniem gry, snapshot wersji zrodlowych
patch/     skrypty do edycji plikow gry, zachowujace konce linii
docs/      lekcje i proces utrzymania modyfikacji
```

---

## Harness

```bash
perl pe/goh.pl <exe> info                naglowki, sekcje, liczba funkcji
perl pe/goh.pl <exe> fn    <rva>         ktora funkcja zawiera adres
perl pe/goh.pl <exe> near  <rva> [okno]  stringi wokol adresu -> modul
perl pe/goh.pl <exe> str   <regex>       stringi pasujace do wzorca
perl pe/goh.pl <exe> xref  <rva|regex>   kto odwoluje sie do stringa
perl pe/goh.pl <exe> calls <rva>         kto wywoluje funkcje
perl pe/goh.pl <exe> cpp                 pliki zrodlowe silnika
perl pe/goh.pl <exe> rtti  [regex]       klasy z RTTI
perl pe/goh.pl <exe> dump  <rva> [n]     hexdump
```

Binarka jest nietypowo przyjaznym celem:

| | |
|---|---|
| symbole PDB | brak |
| RTTI | ~2900 klas z pełnymi przestrzeniami nazw |
| `.pdata` | ~85 000 wpisów → dokładne granice każdej funkcji |
| nazwy źródeł | ~540 plików `.cpp` w komunikatach asercji |
| skrypty | LuaBridge + Lua 5.2.3 |
| DRM / anti-cheat | brak |

Identyfikacja kodu polega na skanowaniu `.text` po LEA rip-względnym i dopasowywaniu
celu do stringów z `.rdata`. Sąsiedztwo zdradza moduł, bo silnik trzyma nazwy plików
źródłowych przy asercjach.

**Offsetów nie przenosi się między buildami** — gra aktualizuje się co kilka tygodni,
więc harness liczy granice za każdym razem, zamiast trzymać zapisane adresy.

### Przykłady użycia

Spór o to, czy predykat selektora celu istnieje — rozstrzygnięty jednym poleceniem,
bo tablica predykatów jest w binarce jako stringi.

Diagnoza crasha: `fn <rva>` dał funkcję i offset wewnątrz niej, `dump` pokazał
instrukcję (`mov eax,[rcx+0x1C0]` przy zerowym rejestrze), `near` wskazał moduł po
sąsiednich nazwach plików źródłowych, a `xref` na komunikat z logu znalazł funkcję,
która zwróciła nulla, i jej 116 miejsc wywołania.

---

## Kontrola przed uruchomieniem

```bash
perl test/preflight.pl
```

Kończy werdyktem „można testować" albo „nie odpalaj". Sprawdza niezbilansowane nawiasy,
niepodstawione parametry makr, arność makr pojazdów, odwołania do nieistniejących encji,
rozjazd końców linii, obecność plików eksperymentalnych tam, gdzie ich nie powinno być,
oraz czy gra nie jest uruchomiona.

Dwie kontrole mają **znane fałszywe alarmy** i zgłaszają ostrzeżenie zamiast błędu:
indeks encji bywa niepełny, a porównanie końców linii przez shell zawodzi.

---

## Utrzymywanie modyfikacji przez patche

Modyfikacje w GEM2 to pliki nadpisujące zawartość paków w całości, nie fragmentami.
Po patchu gry albo moda nie da się na oko odróżnić własnej zmiany od przepisanej
cudzej treści.

```bash
perl test/snapshot-upstream.pl   # zrzuca wersje z pakow do upstream/
diff -r upstream <nasze-pliki>   # dokladnie wlasna delta
```

Mając zapisany punkt wyjścia, aktualizacja staje się mechaniczna: porównujesz, co zmienił
autor, z tym, co zmieniłeś ty, i rozstrzygasz cztery przypadki. Przy ostatniej większej
aktualizacji okazało się, że autor sam naprawił **140 ze 158** rzeczy, które wcześniej
trzeba było łatać ręcznie.

Procedura krok po kroku: `docs/proces.md`.

---

## Środowisko

Potrzebne: `perl`, `git`, `unzip`. Przydatne: `gh`, `xxd`.
Paki `.pak` to zwykłe archiwa ZIP — `unzip -p` czyta jeden wpis bez rozpakowywania całości.

`.gitattributes` wyłącza normalizację końców linii. Bez tego checkout dawałby pliki z LF,
a silnik w części plików wymaga CRLF.

---

## Zanim coś zmienisz

`docs/lekcje.md` — dziesięć punktów, każdy kupiony crashem albo straconym wieczorem.
Najważniejszy jest pierwszy: **nie pisz składni z głowy, sprawdź w prawdziwym pliku.**

---

## Uwaga

Repozytorium zawiera wyłącznie narzędzia i dokumentację. Nie rozpowszechnia zawartości
gry ani cudzych modów — pliki gry czyta z lokalnej instalacji.
