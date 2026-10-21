---
name: gem2-modding
description: Modding Call to Arms - Gates of Hell i innych gier na silniku GEM2 - edycja plikow .set/.inc/.mi/.def, triggery, encje, breedy, selektory celu, paki .pak, analiza binarki i czytanie game.log. Uzyj przy kazdej zmianie w plikach gry lub moda, przy diagnozie crasha albo desynca w co-opie, oraz przy grzebaniu w call_to_arms.exe.
---

# Modding GEM2

Formaty danych GEM2 **nie są udokumentowane**. Nieznana nazwa akcji, termu warunku,
trybu albo parametru kończy się jednym z trzech scenariuszy: cisza (silnik ignoruje),
wpis w logu, albo **crash** — bo silnik nie sprawdza wyniku i dereferencjonuje nulla.

Te zasady powstały po sesji, w której cztery razy pod rząd wymyśliłem składnię zamiast
ją sprawdzić. Każda kosztowała straconą bitwę albo crash.

## Zasada numer jeden

**Zanim napiszesz jakąkolwiek składnię GEM2, znajdź ją w cudzym działającym pliku.**

Nazwa akcji, term warunku, tryb, parametr, klauzula selektora — wszystko musi istnieć
w plikach gry albo moda, zanim trafi do naszych. Bez wyjątków, także gdy „to oczywiste".

```bash
grep -rhoE '\{"[a-z_]+"' <plik ze skryptem> | sort | uniq -c | sort -rn   # jakie akcje istnieja
grep -rhoE '\{mode [a-z_]+\}' <pliki>                                      # jakie tryby
grep -rhoE '\{spawn "[^"]+"[^{}]*' <pliki .inc>                            # co przyjmuje spawn
grep -rhoE '\{"[0-9]+\.[a-z_]+"' <pliki>                                   # jakie termy warunkow
```

Jeśli czegoś nie ma w żadnym prawdziwym pliku — **to prawdopodobnie nie istnieje**.
Przykład: warunek `{"N.time"}` wygląda naturalnie i nie istnieje. Trigger natychmiastowy
to pusty `{condition}`, a opóźnienie idzie przez `{"delay"}` w akcjach.

## Rzeczy, które powodują crash

| | |
|---|---|
| `{spawn "X"}` bez encji `.def` | `can't spawn entity X` → null → **crash** |
| makro `squad_vehicleN` z mniej niż N parametrami `crewN` | niepodstawiony `%crew8` leci jako nazwa breeda → **crash** |
| odwołanie do nieistniejącego breeda/tagu w selektorze | zwykle cisza, czasem crash |

Encja to **nie** to samo co blok zachowania. Blok `{"nazwa"}` w `set/interaction_entity/*.inc`
dokleja zachowanie do **istniejącej** encji; sam niczego nie tworzy. Minimalna encja to 30 bajtów:

```
{game_entity
	{Skeleton}
}
```

Trzy osobne byty, mylone najczęściej:
- **encja** — `.def` w pakach `entity/*`, to ją tworzy `{spawn}`
- **breed** — `set/breed/mp/<nacja>/<okres>/<nazwa>.set`, definiuje człowieka (skin, ekwipunek, tagi).
  `{spawn}` w skrypcie encji **nie tworzy ludzi z breeda** — milczy. Ludzie powstają tylko
  przez ścieżkę zakupu jednostek.
- **blok interaction** — zachowanie doklejane do encji po nazwie

## Zanim uruchomisz grę

```bash
perl test/preflight.pl      # z repo goh-tools
```

Sprawdza nawiasy, niepodstawione makra, arność makr, brakujące encje, końce linii
i czy gra nie chodzi. Jeśli repo nie jest dostępne, sprawdź ręcznie przynajmniej:
zbilansowane `{}` i `()`, zero `%param` w plikach jednostek, każda nazwa w `{spawn}`
ma odpowiednik `.def`.

## Testowanie

**Mody montują się raz, przy starcie procesu gry.** Zmiana plików wymaga restartu —
wyjście do menu nie wystarczy.

**`game.log` kasuje się przy każdym starcie.** Po nieudanej próbie: najpierw zgraj log,
dopiero potem odpalaj ponownie.

**Jedna zmienna na test.** Jeśli test dotyczy wysokości, usuń z niego wszystko inne.

**Gdy trzy podejścia pod rząd nie trafiają — przestań zgadywać i zmierz.** Zrób test
pokazujący wszystkie warianty naraz: cztery obiekty, każdy z innym parametrem, w odstępach
czasowych. Jedno uruchomienie, jednoznaczna odpowiedź.

## Czytanie game.log

| wpis | znaczenie |
|---|---|
| `can't spawn entity X` | brak `.def`, za chwilę crash |
| `Remap actor_id X to N` | encja powstała poprawnie — **tego szukaj jako potwierdzenia** |
| `***** Exception *****` | pełny stos, na dole nazwa podsystemu |
| `no breed found` + `Undefined skin "skeleton"` | szum, setki przy starcie każdej misji |
| `not registerd in unit manager` | wisząca referencja, zwykle nieszkodliwa |

**Cisza nie znaczy sukcesu.** Udane spawny nic nie logują. Brak błędu znaczy tylko tyle,
że nie było błędu.

## Analiza binarki

Gdy składni nie da się znaleźć w plikach, bo to enum albo tablica w kodzie:

```bash
perl pe/goh.pl <exe> str  <regex>    # stringi - tu zwykle sa nazwy akcji i termow
perl pe/goh.pl <exe> fn   <rva>      # ktora funkcja zawiera adres (granice z .pdata)
perl pe/goh.pl <exe> near <rva>      # sasiednie stringi -> nazwa pliku .cpp
perl pe/goh.pl <exe> xref <regex>    # kto odwoluje sie do stringa
```

Binarka ma RTTI (~2900 klas z przestrzeniami nazw), `.pdata` z granicami ~85 000 funkcji
i ~540 nazw plików `.cpp` w komunikatach asercji. Brak symboli PDB, brak DRM.

**Offsetów nie przenosi się między buildami** — gra aktualizuje się co kilka tygodni.

## Praca z patchem na co-op

Co-op wymaga plików **bit w bit identycznych** u obu graczy.

Pliki patcha to zmienione kopie plików autora moda. Bez zapisanego punktu wyjścia nie
da się odróżnić własnej zmiany od cudzej treści — i tak powstają „nieaktualne nadpisania",
które po cichu cofają poprawki autora.

```bash
perl test/snapshot-upstream.pl    # zrzuca wersje z pakow
diff -r upstream <nasze-pliki>    # dokladnie wlasna delta
```

Po update gry albo moda **najpierw licz delty, dopiero potem kopiuj**. Przy jednej
z aktualizacji okazało się, że autor sam naprawił 140 ze 158 rzeczy.

**Kopiowanie nowej paczki nie kasuje starych plików** — to klasyczne źródło desynca.

## Drobiazgi techniczne

- paki `.pak` to zwykłe archiwa ZIP, `unzip -p <pak> <wpis>` czyta jeden plik
- część plików silnika wymaga **CRLF** — sprawdź `file` przed i po edycji
- do edycji wieloliniowej `perl -0777 -pi -e`; uważaj na `\r` w `printf` (staje się CR)
- eksperymenty trzymaj poza wersją produkcyjną patcha
- przed eksperymentem commit, cofanie przez `git checkout`
