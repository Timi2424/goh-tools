# Mapa możliwości — co da się zmienić, gdzie silnik mówi „nie"

Spisane 2026-10-22 na buildzie 1.067/1.068. Inwentarz warstw, osobno balans co-opa,
osobno potwierdzone blokery. Bez zmian w grze — to mapa, nie plan robót.

Źródła: pliki gry, [zrodla-dokumentacji.md](zrodla-dokumentacji.md),
[warstwa-lua.md](warstwa-lua.md), [lekcje.md](lekcje.md),
`goh-hf-patch/eksperymenty/LEKCJE.md` (gałąź `paradrop`).

---

## A. Warstwy, które silnik pozwala podmienić

| warstwa | ile tego jest | czym sterujemy | nasz stan |
|---|---:|---|---|
| `set/breed/**` | 5127 plików | człowiek: skin, ekwipunek, **tagi** (uchwyt dla selektorów) | ruszane w eksperymentach |
| `set/stuff/**` | 2805 | przedmioty, ekwipunek, zawartość skrzyń | — |
| `set/environment/**` | 609 | pogoda, pory dnia, oświetlenie | — |
| `set/multiplayer/**` | 103 | **tryby gry, armie, cenniki, rostery zakupowe** | — |
| `set/interaction_entity/**` | 52 | zachowania doklejane do encji (`crew_emit`, konstrukcje) | `fence.inc` w paczce |
| `set/target/*.inc`, `ammo.set` | 23 | **tabele trafień i penetracji** | 6 plików w paczce |
| `set/ability`, `set/registry`, `set/curves`, `set/blow`, `set/vision`, `set/talk` | ~90 | zdolności, rejestry przeszkód, krzywe, wybuchy, wykrywanie, kwestie mówione | `obstacles.reg` w paczce |
| `set/dynamic_campaign/**` | 16 | **CP, MP, research, ryzyko, czas trwania kampanii** | 6 plików w paczce |
| `set/difficulty/*.dl` | 7 | mnożniki zdrowia, czas wykrwawiania | — |
| `properties/*.ext` + `.inc` | 44 + 106 | klasy encji: człowiek, pojazd, czołg, drzewo | `human.ext` w paczce |
| `entity/**/*.def` | **17 649** | każda encja w grze (pojazdy 2442, budynki 6905, skiny 3667, ekwipunek 1630) | stuby w eksperymentach |
| mapy: `.mi` + `.inc` | 305 w `multi.pak`, +93 w DLC | **skrypty misji: triggery, strefy, waypointy, kamery** | `dcg_script.inc` w paczce |
| `script/multiplayer/**.lua` | 45 | **bot: konkwista, fale, zakupy, rostery** | nic — patrz [warstwa-lua.md](warstwa-lua.md) |
| `interface/*.pak` (xml) | 3 paki | układ ekranów i paneli | `DynamicCampaignMapPointLarge.xml` w paczce |
| `localizations/<lang>/` | `.po`/`.pot` | teksty; silnik scala je do VFS automatycznie | — |
| dźwięk, tekstury, modele | `sound.set`, `.dds`, `.ply`/`.mdl`/`.anm` | +eksporter do 3ds Max 2011–2020 w `mods/tools/plug-ins` | `sound.set` w paczce |
| `mod.info` | 1 | pakowanie: `{delete}`, `{require}`, `{tags}`, wersje, `.pat` | używamy minimalnie |

**Wniosek z proporcji:** wszystko, co realnie robimy, to warstwa SDL (`set/`,
`properties/`, `.inc` map) plus jeden plik interfejsu. Dwie duże warstwy stoją
nietknięte: **Lua** (bot) i **skrypty misji w `.mi`** poza `dcg_script.inc`.

---

## B. Balans co-opa — gdzie dokładnie siedzi

To są **cztery niezależne dźwignie**. Mieszanie ich w jednym teście = nie wiadomo,
która zadziałała.

### B1. Ekonomia bitwy — `set/dynamic_campaign/resources_*.set`

Plik, który już nadpisujemy (`resources_low.set`). Klucze — wszystkie opisane
komentarzami w `set/dynamic_campaign/values.set`, to gotowa dokumentacja:

```
{GlobalMaxCP 550}            ; sufit na sumę CP wszystkich jednostek
{StageCP 60 80 100 120 140}  ; CP na każdy etap; liczba wpisów = liczba etapów
{SpecialCP 50}               ; zakładka nalotów
{EmplacementCP 50}           ; to, co stawia saper
{Bots
  {StartMP 1.00 min 99999 attackerMultiplier 1.00}   ; startowe MP bota
  {FinishMP 1.00 min 99999 attackerMultiplier 1.00}  ; tempo wzrostu MP (start→finish w 20 min)
  {CP {Base "0:500"} {RoundMultiplier "0:100"} {AttackMultiplier 1}}
  {DefenseLevel level_1..3 {DefenseBudgetPlayer} {DefenseBudgetAI} {unlock games N progress X}}
}
{PaybackFactor 0.3 0 0 0}    ; ile MP wraca za stratę
{SellFactor 0.5 0 0 0}
{RiskFactor {Low {BotResources 1.0} {BotVeterancy 0}} … }
```

`DefenseBudgetPlayer` **mnoży się przez liczbę flag** i rośnie z postępem kampanii
(`unlock games 4 progress 0.4`). To jest ten człon, który sprawia, że późna kampania
robi się ciężka niezależnie od trudności.

### B2. Zasady trybu — `set/multiplayer/games/campaign_capture_the_flag.set`

Tryb, w który gramy (`campaign_capture_the_flag` = konkwista DCG):

```
{preparationTime 1200}      ; ile bot czeka, zanim ruszy, gdy bronimy
{impregnableTimeout 10}     ; ochrona spawnu
{scoreFinal 1000}
{friendlyFire 1} {enableBots 1} {randomSpawnPoints 1}
parameters: flag_capture_time=75, flag_release_time=25, flag_capture_factor=0.9,
            points_table_player vs points_table_ai, kill_score_multiplier=0
```

`points_table_*` to tempo punktowania osobno dla gracza i dla AI — w pliku jest
tabelka przeliczeniowa na minuty (0.277 = 60 min, 0.555 = 30 min). **To jest
najczystsze pokrętło długości bitwy.**

Sekcja `{presets}` → `{bots}` ustawia per trudność `("bot_state" cp() mpStart()
mpFinish() payback())`. W konkwiście **wszystkie cztery poziomy mają 1.00/1/1/0.0** —
komentarz w pliku mówi wprost: „overridden in dynamic campaign difficulty files".
Czyli dla DCG trudność z menu nie robi tu nic, robi to B1.

Dla porównania `presets/global_parameters/bots_generic.inc` (frontlines, last stand)
ma realne wartości: easy `cp 0.80 / unitScore 1.2`, heroic `cp 1.10 / mpFinish 1.75
/ payback 4.00 / unitScore 0.5`.

Jest też osobny `set/multiplayer/games/cooperative.set` — **nietknięty przez nas
i niezbadany**.

### B3. Decyzje bota — Lua, `modes/conquest/runtime_config.lua`

Opisane w [warstwa-lua.md](warstwa-lua.md). W skrócie: liczba i rozmiar fal,
odstępy między falami, garnizon 7–8 **na flagę**, kontratak, delty za trudność
i ryzyko, oraz **skalowanie presji progami CP** (`PlayerBattleScalePurchaseCountDelta`)
i zużyciem CP przez graczy (`commitment`).

To jest jedyne miejsce, gdzie „we dwóch" wchodzi do rachunku — nie przez liczbę
graczy wprost, tylko przez CP, które dwóch graczy razem wystawia.

### B4. Twardość jednostek — `set/target/*.inc`, `ammo.set`, `properties/human.ext`, `set/difficulty/*.dl`

Tabele trafień i penetracji (to już ruszamy), oraz `set/difficulty/multiplayer.dl`:

```
{death_delay_min 90} {death_delay_max 120}   ; wykrwawianie w sekundach
{health 1.0}                                  ; mnożnik zdrowia
;{burst 1.5}                                  ; zakomentowany mnożnik serii
```

**Uwaga:** `multiplayer.dl` jest wspólny dla wszystkich trybów sieciowych, więc
zmiana tutaj dotyka też zwykłego multi, nie tylko naszego co-opa.

---

## C. Blokery silnika — potwierdzone, z dowodem

| bloker | objaw | obejście |
|---|---|---|
| **`(include)` z wnętrza paka szuka w tym samym paku** | luźny plik o tej samej ścieżce jest ignorowany, także przy ścieżce bezwzględnej | własny pak sortujący się po oryginale (`zz_multi.pak`); `set/*` i `properties/*` tego nie dotyczy |
| **silnik nie sprawdza wyniku `{spawn}`** | brak `.def` → `can't spawn entity` → null → crash | stub `.def` (30 bajtów) zanim użyjesz nazwy |
| **nazwa w binarce ≠ dopuszczalna składnia** | `TravelAltitude` jest w exe i wywala grę w `.ext` | dowodem jest tylko wystąpienie w prawdziwym pliku **tego samego typu** (`test/kontekst.pl`) |
| **makro bez kompletu parametrów** | literalny `%crew8` leci do silnika → access violation | po edycji wpisu zakupowego `grep -c '%crew'` musi dać 0 |
| **sklejony wiersz `}{"nazwa"`** | nawiasy się bilansują, parser po cichu połyka blok, zero śladu | domknąć plik nową linią przed doklejeniem; `grep -nE '\}[ \t]*\{"'` |
| **nadpisywanie całymi plikami, nie fragmentami** | 229 linii naszych zmian niesie 19 pełnych plików cudzej treści | trójstronny merge przy każdym update — [proces.md](proces.md) |
| **log kasuje się przy starcie gry** | nieudana próba + ponowny start = dowód przepadł | zgrać `game.log` przed kolejnym uruchomieniem |
| **mody montują się raz, ~6 s od startu** | zmiana plików moda nie wchodzi po wyjściu do menu | restart całej gry |
| **`Remap actor_id` tylko przy wczytaniu mapy** | udany spawn/emit w trakcie bitwy nie loguje nic | cisza ≠ sukces; każda zmiana musi dawać widoczny efekt albo celowy błąd |
| **błędy parsowania nie trafiają do `game.log`** | `unexpected token` siedzi w `log/minidumps/*.crash.mdmp.log` | szukać tam, nie w game.log |
| **offsety w binarce nie przenoszą się między buildami** | adres z sierpnia wypada w innej funkcji w 1.066 | harness liczy granice z `.pdata` przy każdym uruchomieniu |
| **edytor wraca do własnej kopii misji** | po Stop zmiany z dysku nie wchodzą | Stop → F3 → **Reload** → START |
| **co-op wymaga identycznych plików, a kopiowanie nie kasuje** | stare pliki po poprzedniej wersji patcha desynchronizują; hashe ich nie wykryją | lista kasowania w `SPRAWDZ.bat`; docelowo `{delete}` w `mod.info` |
| **`{spawn}` nie tworzy ludzi z breeda** | cisza, zero efektu | ludzie powstają tylko ścieżką zakupu |
| **dwie numeracje graczy, `{player "255"}` odrzucone** | `value "255" is invalid for enum` | człowiek w edytorze to `user 255`, w selektorze `{player "N"}` |
| **rozrzut boczny desantu nieosiągalny** | `throw_off dir` bez efektu, `random_position` ignorowane przy spawnie na kości | zostaje `offset` albo dwa samoloty |
| **`preprocess_sdl` nie istnieje w naszym exe** | narzędzie z dokumentacji MoW II nie działa | sprawdzone; zostaje czytanie plików i log |
| **bot Lua liczy się tylko u hosta** | `math.randomseed(os.time() * hostId)` | nie bloker, ale zasięg: zmiany w Lua działają po stronie hosta |

---

## D. Czego nie wiemy — otwarte pytania

1. ~~Czy luźny plik dokłada nowy wpis do katalogu, czy tylko podmienia istniejący?~~
   **Rozstrzygnięte korpusem 2026-10-22** — VFS scala **per ścieżka**, luźny plik nie
   zasłania katalogu, a nowe ścieżki działają (360 nowych breedów w modzie
   „Panzergrenadier", nasze stuby `.def`). „Dokładanie do katalogu" nie jest
   mechanizmem: silnik bierze zasób po nazwie z pliku, który go wymienia, więc każde
   dodanie to **dwa pliki — zasób i lista**. Zostało jedno pytanie: czy luźny plik
   o ścieżce z paka podmienia go **w całości**, czy treść się scala. Patrz
   [test-luzne-pliki.md](test-luzne-pliki.md).
2. **Czy gra porównuje pliki między graczami, czy tylko listę modów?** Desynce
   obserwowaliśmy empirycznie, mechanizmu nie znamy. Odpowiedź zmienia koszt każdej
   zmiany w Lua (host-side) — patrz [warstwa-lua.md](warstwa-lua.md).
3. **`ArmyCP = 4294967295`** w logu i zawsze `FullCommitment` — usterka czy DCG po prostu
   nie ustawia tego licznika.
4. **`{##` jako wyłącznik bloku w naszych plikach** — Horten tak wyłączył swój detektor
   `hf_check_compat`, więc działa; nie sprawdziliśmy, czy wolno tego użyć w `.set`/`.ext`.
5. **`set/multiplayer/games/cooperative.set`** — osobny tryb co-op, nigdy nie oglądany.
6. **Podręcznik mapy** (`map_editor(eng).pdf`) nieprzerobiony: tryby `Clip`, `Edifice`,
   uruchamianie edytora z linii poleceń.

---

## E. Gdzie jest najwięcej do ugrania, gdyby pytać o kolejność

Nie jest to plan, tylko ocena stosunku efektu do ryzyka:

1. **B2 `points_table_*` i `preparationTime`** — czysta zmiana tempa bitwy, jeden plik,
   zero logiki, łatwa do zmierzenia.
2. **B1 `DefenseLevel` i `Bots CP/MP`** — już nadpisujemy ten plik, więc koszt
   utrzymania zerowy, a to właśnie ten człon skaluje trudność z postępem kampanii.
3. **B3 Lua `runtime_config`** — najbogatsze pokrętła (fale, garnizon per flaga),
   Horten tego nie wydaje, więc jego update tego nie cofnie; koszt to nowy plik w paczce.
4. **B4 `multiplayer.dl`** — najmocniejszy efekt na odczucie walki, ale dotyka też
   zwykłego multi.
