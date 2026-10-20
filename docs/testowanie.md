# Pętla testowania

Są dwie pętle. Wybór między nimi jest najważniejszą decyzją w całym dniu pracy.

| | laboratorium | konkwista |
|---|---|---|
| jeden przebieg | **cel: poniżej minuty** (jeszcze niezmierzone, #12) | kilka minut |
| co trzeba zrobić | Reload, Start | restart gry, wejście w bitwę, zakup |
| prędkość gry | **10× … 0,1×** | 1× |
| co da się testować | triggery, skrypty encji, własność, fizyka | to samo + ekonomia i sklep |

Retrospektywa zrzutu spadochronowego: **około trzydziestu przebiegów w konkwiście,
kilkanaście bitów informacji, kilka godzin.** Żadna ilość wiedzy o silniku tego
nie nadrabia — trzeba skrócić pętlę, a nie lepiej zgadywać.

---

## Laboratorium

Mapy testowe Hortena (`map/testing_ground/`, `map/testing_ground_800x800/`)
**nie leżą w żadnym paku**, więc plik `.mi` czytany jest wprost z dysku,
a triggery siedzą w nim samym. Bez `zz_multi.pak`, bez `dcg_script.inc`,
bez kupowania jednostek.

```bash
bash eksperymenty/lab/zainstaluj.sh        # z repo goh-hf-patch
```

Potem:

1. **Steam → Gates of Hell → Play → „Editor"**
2. w opcjach modów włącz Hortena (i nasz patch, jeśli go testujesz)
3. otwórz mapę `testing_ground_800x800`
4. górna linia panelu (tytuł misji) → **Load other mission** → `hf_lab`
5. **Start** — przycisk w prawym dolnym rogu panelu

Po każdej zmianie pliku: skrypt instalacyjny, potem w edytorze
**Reload → Start**. Gry się nie restartuje.

W edytorze *view* (klawisz `1`) jest **regulacja prędkości gry** i **Diplomacy** —
relacje między stronami. Zrzut, który trwa pół minuty, oglądasz w trzy sekundy.

Szczegóły edytora: [edytor-misji.md](edytor-misji.md).

**Czego laboratorium nie zastąpi:** sklepu, ekonomii i zachowania w co-opie.
To, co dotyczy zakupów i drugiego gracza, i tak trzeba sprawdzić w konkwiście —
ale dopiero wtedy, gdy mechanizm już działa.

---

## Najpierw udowodnij, że kod dociera do silnika

**Sześć przebiegów poszło na debugowanie zachowania w pliku, którego gra nie
czytała.** Nic w logu tego nie pokazywało, bo cisza w logu nie odróżnia sukcesu
od porażki — udany spawn, udany emit i udane przypisanie właściciela nie
zapisują niczego.

Zanim zaczniesz debugować *dlaczego robi nie to, co chcesz*, sprawdź, czy
w ogóle się wykonuje.

| sonda | efekt | kiedy |
|---|---|---|
| celowy błędny klucz | ścieżka ładowania, plik, numer linii, token z `«` | parsowanie |
| `{waypoint "999999"}` | `Waypoint 999999 not found` | czas gry, log |
| nieistniejąca kość w `{spawn}` | `Bone X not found in Y` — **niezweryfikowane** | czas gry, log |
| `{"timer" {time N}}` | liczba na HUD | czas gry, ekran |

Gotowe bloki do wklejenia: **[`test/sondy.inc`](../test/sondy.inc)**.

### Dwie pułapki, które nas kosztowały

**Sonda nie może zależeć od badanej rzeczy.** Dwa nasze beacony miały selektor
`{tag c47_d}`. Gdy tag nie łapał, milczały — i nie dowodziły niczego. Jeśli
badasz tag, sonda nie może go używać.

**Komunikat o błędzie parsowania NIE TRAFIA do `game.log`.** Siedzi w
`Documents/My Games/gates of hell/log/minidumps/*.crash.mdmp.log`. Najmocniejsza
sonda, jaką mamy, była przez cały czas poza raportem. `test/raport.pl` czyta
teraz oba pliki i ma osobną sekcję **SONDY**.

### Zegar jako wyświetlacz

`{"timer"}` pokazuje liczbę, więc `switch` po wariantach zwraca **wartość**,
a nie jeden bit. Tak odczytuje się numer właściciela encji: 11 = gracz 1,
22 = gracz 2, 99 = niczyj. Jeden przebieg zamiast ośmiu.

---

## Kontrola przed uruchomieniem

```bash
perl test/preflight.pl
```

Kończy werdyktem `>>> mozesz testowac` albo `>>> NIE ODPALAJ`.

| kontrola | dlaczego |
|---|---|
| klamry `{}` i głębokość | literówka cicho psuje parsowanie całego pliku |
| nawiasy `()` | tylko **uwaga** — sama gra ma `t()))` w `units/early/units_eng.set` i wczytuje go |
| **sklejony wiersz `}{"nazwa"`** | **bilansuje się poprawnie, parser połyka cały blok** |
| znaki spoza ASCII | tylko uwaga — gra ma je w `textures.set` |
| niepodstawione `%param` | dosłowny `%crew8` poleciał jako nazwa jednostki i **wywalił grę** |
| arność `squad_vehicleN` | makro na 10 załóg z siedmioma to ten sam crash |
| `{spawn "X"}` bez encji | brak `.def` → null → **crash**, najczęstsza przyczyna |
| nazwy akcji i termów warunków | sprawdzane względem `data/slownik/tablice.txt` z binarki |
| końce linii vs oryginał | część plików silnika wymaga CRLF |
| pliki spoza patcha | eksperymenty nie mogą wyciec do wersji produkcyjnej |
| czy gra chodzi | mody montują się przy starcie, zmiany w trakcie nie wejdą |

Komentarze (średnik do końca wiersza, poza stringami) są wycinane przed liczeniem
nawiasów — pliki GEM2 zawierają wiersze w rodzaju `;//{state`, czyli komentarz
z niesparowanym nawiasem. Treść stringów też: `"{"` w napisie to nie blok.

Ta kontrola istnieje **w jednym miejscu** — `gem2::sprawdz_tekst`. Skrypty
powłoki wołają ją przez:

```bash
perl test/sprawdz-plik.pl <plik>...
```

Wcześniej były trzy kopie i się rozjechały: jedna przepuszczała sklejki
z tabulatorem. Sprawdzona na ~24 tys. plików gry i Hortena: **zero błędów**,
czyli zero fałszywych alarmów na kodzie, który silnik przyjmuje.

Misje laboratorium (`hf_lab*.mi` w katalogach `testing_ground*`) preflight
traktuje jako nasze i sprawdza — mimo że reszta tych katalogów należy do Hortena.

Dwie kontrole mają **znane fałszywe alarmy** i zgłaszają ostrzeżenie zamiast
błędu: indeks encji bywa niepełny, a porównanie końców linii przez shell zawodzi.
Przy ostrzeżeniu o brakującej encji **sprawdź ręcznie** — to jedyny błąd, który
gwarantuje crash.

---

## Czy wolno tego użyć w tym pliku?

```bash
perl test/kontekst.pl <nazwa>
perl test/kontekst.pl --odswiez      # przebuduj korpus z paków (~2 min, 330 MB)
```

Słownik z binarki mówi, **co silnik zna**. Nie mówi, **w jakim pliku wolno tego
użyć**. `TravelAltitude` z tablicy podwozia `airborne` wyglądał jak klucz `.ext` —
wpisany do `.ext` dał `unexpected token (eResource.cpp:102)` i wywalił
wczytywanie kampanii.

`kontekst.pl` zestawia jedno z drugim: wpis ze słownika (klasa C++, kolumna
`kontekst`) plus **rzeczywiste wystąpienia w plikach gry, w rozbiciu na typ pliku**
i na to, czy nazwa stoi jako klucz `{nazwa …}`, czy jako blok `{"nazwa" …}`.

```
TravelAltitude  ->  nie ma w binarce, zero wystąpień  ->  nie istnieje
crew_emit       ->  Interaction::eAction_CrewEmit, encja, 53 użycia w 9 plikach .inc
Maxspeed        ->  nie ma w binarce, ale 2 użycia w .ext  ->  wolno
```

Zasada: **wystąpienie w prawdziwym pliku tego samego typu jest jedynym pewnym
dowodem na dopuszczalność.** Binarka służy do zawężania listy kandydatów i do
obalania — jeśli nazwy nie ma w exe, nie istnieje.

---

## Kolejność, która się sprawdza

1. **Kontrola** — `preflight.pl` musi dać „można testować"
2. **Sonda** — czy kod w ogóle dociera do silnika
3. **Jedna zmienna na przebieg** — jeśli test dotyczy wysokości, wywal z niego
   wszystko inne. Zmiana dwóch rzeczy naraz zepsuła nam działający stan
   i odebrała punkt odniesienia.
4. **Albo odwrotnie: wszystkie warianty naraz** — gdy nie wiesz, który parametr
   jest tym właściwym, zrób jeden przebieg pokazujący cztery warianty
   rozróżnialne po efekcie. Za każdym razem było to najbardziej produktywne
   pół godziny.
5. **Przeczytaj raport**

---

## Co znaczą wpisy w logu

| wpis | znaczenie |
|---|---|
| `can't spawn entity X` | brak `.def` — za chwilę crash |
| `Remap actor_id X to N` | encja powstała poprawnie — **tylko przy wczytywaniu mapy** |
| `***** Exception *****` | pełny stos, na dole nazwa podsystemu |
| `unexpected token (eResource.cpp:102)` | **w pliku crasha, nie w game.log** |
| `no breed found` + `Undefined skin "skeleton"` | szum, setki przy starcie każdej misji |
| `not registerd in unit manager` | wisząca referencja, zwykle nieszkodliwa |

**Cisza nie znaczy sukcesu.** Brak błędu znaczy tylko tyle, że nie było błędu.

---

## Raport dla drugiej osoby

Gdy pracujesz z kimś, kto nie siedzi przy tym komputerze, wyniki trzeba jakoś
przekazać. Opisywanie z pamięci gubi szczegóły, przeklejanie konsoli jest
upierdliwe.

```
raport.bat
```

Jedno polecenie zbiera wszystko do `data/raport.txt`: wersje gry i moda, kontrolę
plików, deltę, triage logu, **sekcję SONDY** i ślady naszych encji. Archiwizuje
też `game.log` i najnowszy `*.crash.mdmp.log` do `data/logi/`, zanim skasuje je
następny start gry.

Potem wystarczy wskazać plik.
