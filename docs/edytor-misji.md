# Edytor misji — oficjalny podręcznik, którego nie czytaliśmy

Gra ma własną dokumentację składni misji i nikt z nas na nią nie wpadł:

```
mods/tools/mission_editor(eng).pdf     37 stron
mods/tools/map_editor(eng).pdf
```

Opisuje selektory, warunki i komendy triggerów — czyli dokładnie to, co przez
kilka wieczorów odtwarzaliśmy z binarki i z cudzych plików. **Nie zastępuje
słownika z exe** (jest starsza od tego builda i niekompletna), ale rozstrzyga
semantykę, której z nazwy nie widać.

PDF nie ma warstwy tekstowej do wygodnego czytania; tekst wyciąga
`test/pdftext.ps1` (inflacja strumieni FlateDecode).

---

## Co to zmienia w naszych ustaleniach

| nasze ustalenie | podręcznik mówi |
|---|---|
| `air_state` działa **przyrostowo** | `altitude` to **wysokość lotu w metrach** — o przyroście ani słowa; nasza obserwacja wymaga ponownego pomiaru |
| `emit` „nie działa na samolot" | `emit` **wysadza aktorów na wskazanym waypoincie** — bez waypointa nie ma gdzie ich postawić |
| numeracja graczy jest zagadką | strony są numerowane **player 0 … player 7**, a edytor pozwala nadać im aliasy i relacje |
| selektor nie umie czytać właściciela | Local selector ma pole **`player`** — „entities of the indicated player only are selected" |

Pierwsze dwa to **korekty do `goh-hf-patch/eksperymenty/LEKCJE.md`**, nie drobiazgi:
jeśli `altitude` jest bezwzględne, to seria dwunastu podbić po 1200 m była
walką z systemem nalotów, a nie z jednostką miary.

---

## Laboratorium: skąd się bierze szybka pętla

To jest powód, dla którego ten plik powstał.

> Górna linia panelu to przycisk z tytułem misji. Pod nim menu: **Save,
> Reload, Load other mission, Unload the mission, Leave the mission editor**.
> W prawym dolnym rogu panelu jest przycisk **Start (Stop)**, który uruchamia
> i zatrzymuje edytowaną misję.

Czyli pętla wygląda tak:

```
edytuj .mi na dysku  ->  Reload  ->  Start  ->  patrz  ->  Stop
```

**Bez restartu gry, bez wchodzenia w bitwę, bez kupowania jednostek.** Do tego
w edytorze *view* siedzi regulacja **prędkości gry od 10× do 0,1×** — zrzut,
który trwa pół minuty, da się obejrzeć w trzy sekundy albo w zwolnionym tempie.

Uruchomienie edytora: **Steam → Gates of Hell → Play → „Editor"**
(`binaries/x64/call_to_arms_ed.exe`). Edytor ma ten sam ekran modów co gra,
więc Hortena i nasz patch włącza się tak samo.

Praktyka: `goh-hf-patch/eksperymenty/lab/` i [testowanie.md](testowanie.md).

---

## Dziewięć edytorów

Przełączane ikoną w lewej części panelu albo **cyfrą na klawiaturze**.

| nr | edytor | do czego |
|---|---|---|
| 1 | view | co jest widoczne, **prędkość gry**, **Diplomacy**, **Aliases** |
| 2 | entity | stawianie jednostek, ich właściwości |
| 3 | group | grupy aktorów (ruch w szyku, konwoje) |
| 4 | waypoint | trasy i komendy wykonywane przy mijaniu punktu |
| 5 | zone | strefy kołowe i wielokątne |
| 6 | trigger | komendy wykonywane po spełnieniu warunków |
| 7 | camera | kamery i klatki bazowe |
| 8 | cover | osłony |
| 9 | environment | pogoda, oświetlenie |

**Diplomacy** ustawia relacje między stronami: *enemy* (czerwony, strzelają do
siebie), *ally* (zielony, wspólne pole widzenia), *neutral* (żółty, nie
wpływają na siebie). Klik przełącza po kolei.

---

## Selektor

Trzy rodzaje, wybierane w oknie *Edit selector*:

- **Local** — robiony na miejscu, działa tylko dla tej jednej komendy
- **Waypoint** — tylko dla komendy przypisanej do waypointa; łapie wszystkich aktorów w tym punkcie
- **Defined** — nazwana selekcja utworzona wcześniej w edytorze triggerów

### Pola selektora lokalnego

Puste pole = warunek nienadany, czyli **spełniony przez wszystkich**. To ważne:
pusty selektor łapie wszystko, a nie nic.

| pole | znaczenie |
|---|---|
| `mids` | numery konkretnych encji, po spacji |
| `tag` | znaczniki |
| `zone` | tylko z danej strefy |
| **`player`** | **tylko encje wskazanego gracza** |
| `relation` | razem z `player`: dokłada graczy w danej relacji — `neutral`, `enemy`, `ally` |
| `covers` | aktorzy w danej osłonie |
| `type` | `human`, `auto`, `tank` |
| `state` | `dead`, `not dead`, `operatable`, `not operatable`, `moveable`, `not moveable`, `broken` |
| `components` | razem ze `state`: aktorzy, których komponent jest w danym stanie; można łączyć przez OR |
| `clip.min` / `clip.max` | ogranicznik liczby wybranych aktorów |

Pole **`player`** to brakujący detektor własności. Podręcznik je dokumentuje,
a `multi.pak → multi/1_frontlines/fr-kharkov/frontlines.mi:9589` używa go
naprawdę, razem z tagiem.

---

## Warunki

`event`, `trigger`, `rand`, `actors`, `entities`, `see_enemy`, `inventory`.

`event` i `trigger` mają tryb **`work` / `on` / `off`** — odpowiednio: warunek
jest w trakcie, zaczął się, nie jest spełniony.

---

## Komendy, które nas dotyczą

Pełna lista jest w PDF (strony 25–35). Tu te, o które się potykaliśmy.

**`player`** — zmienia przynależność aktora do strony. Pola: `selector`
i `player`. Podręcznik podaje jako przykład branie jeńców. To potwierdza, że
komenda jest przewidziana do przepisywania własności w trakcie gry; nie ma
jednak wariantu „skopiuj właściciela z innej encji".

**`actors_state`** — zmiana stanu aktora. Pola m.in.:
- **`control`** — kto steruje: **`user`** (gracz) albo **`AI`** (komputer)
- `speed` — `slow` / `normal` / `fast`
- `speed_kmh` — prędkość w km/h, **nie może przekroczyć maksymalnej prędkości aktora**

Pola `control` **nigdy nie próbowaliśmy**, a to nie jest tylko zapis
z podręcznika — Horten używa go naprawdę:

```
multi.pak -> multi/HF-dcg_script.inc:1078
{"actor_state"
    {selector ...}
    {control user}
    {fire_mode hold}
    {move_mode hold}
}
```

Czyli składnia jest potwierdzona w pliku tego samego typu — spełnia naszą
własną regułę dopuszczalności. Czy `control user` wystarczy, żeby desant dał
się zaznaczyć, to już pytanie do laboratorium, ale jest to **jedna linijka
w komendzie, której i tak już używamy** do prędkości maszyny.

**`air_state`** — sterowanie lotem. Pola: `selector`, `ground` (normalny lot na
zadanej wysokości albo ruch po ziemi) i **`altitude` — wysokość lotu w metrach**.

**`emit`** — **wysadza aktorów na wskazanym waypoincie**. Pola: `selector`
(skąd wysiadają) i `waypoint` (.uid albo .name) — dokąd. To tłumaczy naszą
porażkę: bez waypointa komenda nie ma celu, a maszyna w powietrzu i tak nie
ma jak nikogo „postawić".

**`board`** — wsiadanie do pojazdu lub do działa. Pola: `mids` (do czego)
i `place` (`gunner`, `driver`, `commander`, `charger` albo puste). **Używana
na waypoincie.**

**`wait_crew`** — pojazd czeka, aż wsiądzie cała załoga i pasażerowie, i dopiero
wtedy rusza. Pola: `selector` (pojazd) i `units` (mid-y, po spacji).

---

## Czego podręcznik nie powie

Jest starszy niż ten build i opisuje edytor, nie format pliku. Nie ma w nim
`crew_emit`, `actor_state` z blokiem `{movement}`, ani niczego z warstwy
skryptów encji (`set/interaction_entity/*.inc`). Na to nadal jedyne źródła to
słownik z binarki i prawdziwe pliki gry — `test/kontekst.pl`.

Zasada bez zmian: **wystąpienie w prawdziwym pliku tego samego typu jest
jedynym pewnym dowodem na dopuszczalność.**
