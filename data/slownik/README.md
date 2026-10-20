# Słownik składni skryptów GEM2

Wyciągnięty z `call_to_arms.exe`, nie z dokumentacji — tej nie ma. Powstał po
serii wpadek przy zrzucie spadochronowym, gdzie każdy błąd brał się z wymyślonej
składni, nie ze złego pomysłu (issue #1).

```bash
EXE="…/binaries/x64/call_to_arms.exe"
perl pe/slownik.pl "$EXE" gen data/slownik          # przegenerowanie
perl test/sprawdz-slownik.pl data/slownik/tablice.txt <katalog z plikami gry>
```

**Offsety w plikach są ważne tylko dla builda z nagłówka.** Gra aktualizuje się
co kilka tygodni — po update przegeneruj, nie przepisuj.

| plik | co zawiera |
|---|---|
| `tablice.txt` | 110 rejestrów, 738 nazw: akcja/term → klasa C++ → **kontekst** → przyjmowane parametry |
| `enumy.txt` | 76 tablic nazw zakończonych NULL-em (wartości dla `{mode …}`, `{state …}` itp.) |

### Kolumna `kontekst`

Mówi, **w jakim pliku** wolno nazwy użyć. Tablice w `.rdata` mieszają co najmniej
cztery rodzaje nazw i sama nazwa niczego nie rozstrzyga.

| wartość | znaczenie |
|---|---|
| `trigger` | komenda w `{actions}` misji albo `dcg_script.inc` |
| `warunek` | term warunku (`Helper::eTerm_*`) |
| `encja` | akcja skryptu encji w `set/interaction_entity/*.inc` |
| `rozkaz` | wewnętrzny rozkaz silnika, nie składnia skryptu |
| `interfejs` | akcja UI |
| `dane?` | **prawdopodobnie** klucz pliku danych — znak zapytania jest celowy |
| `obce` | Lua, Xerces, alokatory — nie nasza składnia |
| `?` | nierozstrzygnięte |

Kontekst wyprowadzamy z klasy C++ i z pliku źródłowego, w którym leży string.
To **zawężenie listy kandydatów, nie dowód** — `TravelAltitude` z tablicy podwozia
`airborne` wyglądał jak klucz `.ext`, a wpisany do `.ext` wywalił grę.

Dowód daje dopiero wystąpienie w prawdziwym pliku tego samego typu:

```bash
perl test/kontekst.pl <nazwa>
```

> **Nie wszystko tu jest GEM2.** 18 rejestrów z modułem `?` (228 nazw) to biblioteka
> standardowa Lua (`0x0115xxxx` — `io`, `os`, `string`, `bit32`) i parser XML Xerces
> (`0x014aexxx`). Rejestry samego silnika to **270 nazw**: termy warunków
> (`Helper::eTerm_*`), akcje triggerów (`Helper::*`) i akcje skryptów encji
> (`Interaction::*`). Czytanie `tablice.txt` jako jednego płaskiego zbioru przykrywa
> nieistniejące nazwy cudzymi — `os.time` przepuszczał zmyślony term `{"1.time"}`.
> Porównuj po klasie C++, nie po samej obecności nazwy; `test/gem2.pm` ma to
> rozpisane w `%REJESTRY`.

---

## Jak to zostało wyciągnięte

Silnik trzyma rejestry jako tablice par `{ const char* nazwa, Obiekt* (*fabryka)() }`
w `.data`. Nazwa nie ma **żadnego** odwołania w kodzie — leży tylko jako wskaźnik
w tablicy — więc `goh.pl xref <nazwa>` jej nie znajdzie. Trzeba szukać QWORD-a
z jej adresem w sekcjach danych.

Dalej łańcuch jest już mechaniczny:

```
tablica par -> fabryka -> LEA na vtable -> RTTI przed vtable -> nazwa klasy
            -> metody wirtualne -> stringi w nich = przyjmowane parametry
```

RTTI daje nazwy w rodzaju `Helper::eCmd_spawn`, `Interaction::eAction_Spawn`,
`Helper::eTerm_near`. To jest ten sam build bez symboli, co zawsze — tyle że
tablica wyjątków i RTTI wystarczają.

Przy okazji wyszły dwa błędy w `pe/goh.pl`, oba cicho gubiące dane (poprawione):

- skaner stringów miał **minimum 4 znaki**, więc `tag`, `op`, `no`, `if`, `on`
  nie istniały dla harnessu w ogóle. Teraz minimum to 2 (`GOH_MINSTR=4` wraca
  do starego progu)
- `lea_refs` iterował do `length-8`, a instrukcja `LEA` ma 7 bajtów — ginęła ta
  stojąca dokładnie na końcu funkcji. Małe fabryki kończą się właśnie na `LEA`
  z vtable, więc co czwarta klasa nie dawała się rozwiązać

---

## 1. Akcje i ich parametry

Dwa osobne światy, mylone najłatwiej.

### Skrypt misji (`.mi`) — 79 komend

W `{triggers}{"nazwa"}{actions}`, nazwa **w cudzysłowie**. Pełna lista w
`tablice.txt` pod modułami `eHelperCommand*.cpp` i `eHelperThreadStatement.cpp`.

```
spawn              Helper::eCmd_spawn       entity waypoint disable_random_spawn_position in_camera
waypoint           Helper::eCmd_waypoint    action type direction clone make_squad name_squad copy_squad approach
task               Helper::eCmd_task        name state
event              Helper::eCmd_event       event mode delay
trigger            Helper::eCmd_trigger     on off name
set_i              Helper::eCmd_set_i       var op value
delay              Helper::Thread::eStatementDelay   time
```

Komendy pokazane jako `Helper::eGameEntityCommand` z parametrami `selector command`
to wspólna obudowa — nazwa jest prawdziwa, ale własnych parametrów tą metodą się
z nich nie wyciągnie, bo parsuje je podkomenda. Dotyczy to m.in. `emit`, `effect`,
`animate`, `board`, `inventory`, `throw_off`.

### Skrypt encji (`.inc`, `.set`) — 196 akcji i predykatów

W `{"blok"}{on …}`, nazwa **gołym tokenem**. Moduły `eIA_*.cpp`:

| moduł | ile | co |
|---|---|---|
| `eIA_If.cpp` | 82 | `{if …}` i wszystkie predykaty warunku |
| `eIA_Actor.cpp` | 42 | akcje na żołnierzu i załodze |
| `eIA_GameEntity.cpp` | 35 | akcje na encji |
| `eIA_Skeleton.cpp` | 19 | kości, animacja |
| `eIA_Generic.cpp` | 18 | `log set delay call spawn delete … ` |

---

## 2. Termy warunków — 23, i `time` wśród nich nie ma

Składnia to `{"N.term"}` w `{condition}{terms}`. Pełne parametry w `tablice.txt`.

```
altitude   arrival  camera   cmp_i      crew     difficulty  entities  event
inventory  linked   mined    mission_option      mod         near      rand
reinforcements_score          see_actors          see_enemy   side
signal     task     trigger  waypoint_canmove
```

W 479 plikach misji z paków używanych jest 17 z nich. Sześć istnieje, ale nie
wywołuje ich żadna misja z gry: `arrival`, `mined`, `mod`, `rand`, `side`,
`waypoint_canmove`.

**`{"1.time"}` nie istnieje** — nigdy nie istniało. Wyzwolenie natychmiastowe
to pusty `{condition}`, a opóźnienie idzie przez akcję `{"delay" {time N}}`
(`Helper::Thread::eStatementDelay`).

Term wysokości istnieje i wygląda tak (z `dlc1/…/1942_11-ger_mamayev_kurgan/0.mi`):

```
{"4.altitude"
    {selector {tag enemy} {zone "arty_6"} {type human} {state "not dead"}}
    {altitude {op "<<"} {value 15} {absolute 0}}
}
```

---

## 3. Selektory — dwa silniki, nie jeden

`{selector}` czyta najpierw `{source …}`, a to przełącza cały zestaw klauzul:

| `{source …}` | silnik | kształt |
|---|---|---|
| `standart` (domyślny) | `eHelperSelectionEngineStd` | płaska lista klauzul |
| `advanced` | ten sam moduł, inne klasy | `{group {include …}{select …}{exclude …}}` |

Klauzule czytane wprost przez główny parser `standart` (funkcja `0x9e0a20`
w tym buildzie, `slownik.pl fn`): `amount` `entities` `mids` `tag` `zone`
`player` `user_player` `relation` `type` `state`. Do tego `sort` z osobnej
funkcji tego samego modułu i `source` + `ignore_captured_by_user`, które
parsuje `eHelperCondition.cpp` jeszcze przed wyborem silnika.

Reszta modułu `eHelperSelectionEngineStd.cpp` (`slownik.pl modul`) dokłada
klasy predykatów używane w trybie `advanced`: `include` `exclude` `select`
`cover` `team` `order` `with_item` `entity_stuff` `movement_type`
`broken_components` `destroyed_components` `name` `id` `from_entities`
`using` `existance` `in_squad` `masks` `zone_ex` `inventory_items`.

W plikach misji pojawiają się wewnątrz `{selector}` jeszcze `prop`, `item`,
`min`, `squad`, `wpid` i `discovered`. Każde z nich ma w binarce swój string
i swój parser, ale w innym module (`eHelperCondition.cpp`, `eHelperEvent.cpp`,
`eHelperCommand*.cpp`) — atrybucja modułu jest tu wskazówką, nie pewnikiem.

**Zasięgu w selektorze nie ma.** Żadna klauzula nie filtruje po odległości —
selektor wybiera encje, a dystans liczą dopiero termy: `near` (`distance`,
`near_to`, `high_precision`) i `see_actors` (`distance`, `min`, `max`, `meters`,
`detection`).

Wszystkie 36 nazw klauzul użytych w 479 plikach misji sprawdzono po jednej
w binarce; każda ma tam swój string i swój parser.

---

## 4. `spawn` — też dwa, z różnymi parametrami

### `{spawn}` w skrypcie encji — `Interaction::eAction_Spawn`

```
offset   local_offset   local   scale   volume   texmod   terrain_texmod
no_normal   inv_normal   no_position   dir_velocity   constrain_after_dir
random_position   random_orientation
```

`impulse` **nie jest parametrem spawnu** — to osobna akcja `Interaction::eAction_Impulse`
z własnym zestawem: `up dir cx cy cz fx fy fz forward rnd_dir no_position com`.
Nazwy `cx cy cz fx fy fz` sugerują, że to tutaj, a nie w `offset`, siedzi sterowanie
wektorem.

Czego słownik nie rozstrzyga: **co znaczą trzy liczby w `offset`**. Binarka mówi,
że parametr istnieje i jest przyjmowany — nie mówi, która oś jest pionowa. To
zostaje pomiarem (patrz `docs/testowanie.md`), i pomiar już pokazał, że wszystkie
trzy przesuwają w poziomie.

### `{"spawn"}` w skrypcie misji — `Helper::eCmd_spawn`

```
entity   waypoint   disable_random_spawn_position   in_camera
```

Inny zestaw, inna klasa. Parametry jednego nie działają w drugim.

### `{mode …}`

Nie ma jednego enuma `mode`. Każda komenda ma swój, `enumy.txt` wiąże je
z klasami:

| enum | właściciel |
|---|---|
| `all` `passengers` `crew` | `emit` (`eHelperCommandActorOrder.cpp`) |
| `reset` `set` `toggle` | `Helper::eCmd_event` |
| `show` `hide` `complete` `fail` | `Helper::eCmd_task` |
| `best` `random` `density` | `eHelperCommandActorOrder.cpp` |
| `-` `force` `teleport` `teleport & rotate` `safe teleport` `safe teleport & rotate` | `eHelperCommandWaypoint.cpp` |
| `game` `narrator` `interface` | `Helper::eCmd_music` |

Załoga i pasażerowie to w `emit` dwie różne wartości i dwa różne podselektory —
`{crew …}` wybiera ludzi, `{emit {mode crew}}` mówi, kogo wysadzić:

```
{"emit"
    {selector {tag convoy2} {player "2"} {type vehicle} {state inhabited}}
    {crew {ignore_captured_by_user 0}}
    {emit {mode passengers}}
}
```

---

## Weryfikacja

```
perl test/sprawdz-slownik.pl data/slownik/tablice.txt <korpus>
```

Korpus: 479 plików misji (214 MB) z `map/single.pak`, `map/multi.pak`,
`dlc1`…`dlc5`, `_dlc7` oraz 50 plików interakcji z `gamelogic.pak`.

```
AKCJE TRIGGEROW (.mi)       - uzyte: 62, w tym spoza slownika: 0
TERMY WARUNKOW (.mi)        - uzyte: 17, w tym spoza slownika: 0
AKCJE SKRYPTOW ENCJI        - uzyte: 97, w tym spoza slownika: 0
potwierdzone w plikach gry  - 164 z 272 nazw w rejestrach GEM2
```

Każda sekcja idzie przeciw **swojemu** rejestrowi, nie przeciw całemu plikowi —
inaczej `os.time` z tablic Lua przykrywa nieistniejący term `{"1.time"}`.

Zero nazw użytych poza słownikiem. Druga strona — 108 nazw z rejestrów, których
żadna misja z gry nie wywołuje — **nie jest błędem**: silnik zna więcej, niż
kampania potrzebowała. To wciąż lepszy punkt wyjścia niż zgadywanie.

Weryfikacja nie jest regexem. `{"nazwa"}` w `.mi` raz jest akcją triggera, a raz
nazwą jednostki w rejestrze DLC — skrypt parsuje drzewo `{}` i patrzy na ścieżkę.

---

## Czego ta metoda nie da

- **Semantyki.** Słownik mówi, że parametr istnieje i jak się nazywa. Nie mówi,
  co robi ani w jakich jednostkach. To nadal pomiar.
- **Parametrów za wspólną obudową.** `Helper::eGameEntityCommand` obsługuje
  kilkanaście komend; ich własne parametry parsują podkomendy, których ta metoda
  nie dosięga.
- **Pełnej atrybucji do pliku `.cpp`.** Moduł zgaduje się po najbliższym stringu
  z asercji, a asercje z nagłówków (`eReferenced.h`) są poinlinowane wszędzie
  i psują sąsiedztwo. Nazwa modułu to wskazówka, nie pewnik.
- **Rejestrów, które nie są tablicą par.** Predykaty trybu `advanced` trzymają
  nazwę w metodzie wirtualnej klasy, nie w tablicy — tam szło przez `modul`
  i przez korpus, nie przez `gen`.
