# Warstwa Lua — bot konkwisty, rostery, co wolno ruszyć

Rozebrane 2026-10-22 na buildzie 1.067/1.068. Źródło: `resource/gamelogic.pak`,
ścieżka `script/multiplayer/` (45 plików, ~520 KB), plus dwa readme twórców
opisane w [zrodla-dokumentacji.md](zrodla-dokumentacji.md).

Uwaga na wypakowywanie: **`unzip` w Git Bash nie łapie wzorca** `"script/*"`
(„filename not matched"). Trzeba lecieć plik po pliku z listy `unzip -l`.

Odnośniki do `zrodla/` poniżej prowadzą do lokalnych kopii plików z paka —
tego katalogu nie ma w repo, patrz [zrodla-dokumentacji.md](zrodla-dokumentacji.md).

---

## 1. Jak to jest poskładane

```
bot.main.lua                  <- punkt wejścia, mapuje tryb gry na plik
  campaign_capture_the_flag -> modes/conquest.lua     <- NASZE mapy DCG
  frontlines                -> modes/frontlines.lua
  battle_zones, ammunition  -> modes/battlezones.lua
  evacuation                -> modes/laststand.lua
```

`conquest.lua` to tylko spinacz: `require` 19 modułów i cztery funkcje zdarzeń
(`OnGameStart`, `OnGameQuant`, `OnGameSpawn`, `OnPrepTimeOver`) podpięte pod
`BotApi.Events`. Cała treść siedzi w `modes/conquest/`:

| plik | rola |
|---|---|
| `runtime_config.lua` | **19 tabel samych liczb** — timingi, fale, trudność, wagi. Zero logiki. |
| `runtime_state.lua`, `runtime_context.lua` | stan meczu, budowanie kontekstu |
| `purchase_profiles.lua` | losowanie „siły" (`infantry_force` / `armored_force`) i podział budżetu na **pasy** (`armored_body`, `anti_tank_force`, `artillery_support_force`, …) |
| `purchase_scoring.lua` | 60 funkcji: z tagów jednostki liczy dopasowanie do pasa, wagę i **losuje ważonym losowaniem** |
| `purchase.lua` | filtr `IsUnitAvailable`, wybór punktu spawnu garnizonu per klasa (piechota/MG/działo/pojazd) |
| `purchase_pressure.lua` | modyfikatory liczby zakupów: trudność, ryzyko, skala bitwy (CP), zaangażowanie gracza |
| `waves.lua` | ile fal, ile jednostek w fali, cooldowny |
| `attacker_pressure.lua`, `attacker_wave_off.lua`, `attacker_failure.lua` | kiedy puścić następną falę, kiedy uznać atak za przegrany |
| `defender_counterattack.lua` | kontratak po stracie flagi |
| `scene.lua`, `scene_memory.lua`, `combat_pressure.lua` | migawka sił obu stron przez scene-query |
| `orders.lua`, `orders_flags.lua` | wybór flagi i rozkazy dla oddziałów |
| `battle_result.lua` | rozstrzygnięcie bitwy |

Powierzchnia API: `BotApi.Instance` (playerId, army, difficulty, team, hostId),
`BotApi.Scene` (Flags, Squads, Waypoints, `GetVar`/`SetVar`, `QueryScene`,
`IsSquadTagged`), `BotApi.Commands` (`Spawn`, `SpawnAt`, `CaptureFlag`,
`SeekAndDestroy`, `IsUnitAvailable`, `Income`, `GameOver`), `BotApi.Conquest`
(`ArmyCP`, `ArmyCPLimit`, `Risk`, `FirstPlayerId`, `DefenderBotId`),
`BotApi.Events` (Subscribe, SetQuantTimer).

**`BotApi.Scene:SetVar` to most do skryptu misji** — tą samą drogą, którą
czytamy zmienne w `.mi`. Czyli bot i nasz `dcg_script.inc` rozmawiają zmiennymi.

## 2. Rostery

`units/<nacja>/{early,mid,late,conquest}.<nacja>.lua`. Jeden plik = jedna lista:

```lua
Purchases["conquest.ger"] = { {Repeat = 0, Units = {
  {availability = "1.4", base = {"Infantry","Squad"}, class = {}, grade = "Grade2",
   posture = {"Offensive"}, roles = {"Assault"}, effects = {"VsInfantry"},
   unit = "squad_sturmgren_con(ger)"},
```

Który plik się ładuje, wybiera `utility.lua`: `units/<army>/<tryb>.<army>`.
Znaczenie każdego pola jest opisane w `unit_roster_readme.md`
(kopia: [zrodla/unit_roster_readme.md](zrodla/unit_roster_readme.md)).
Osobno `.def` jednostki nosi **jeden** tag `sq_*` — to czym jest dla czujnika
zagrożenia ([zrodla/scene_query_readme.md](zrodla/scene_query_readme.md)).

**Horten nadpisuje wyłącznie rostery i `frontlines.lua`** — 31 plików, ani
jednego z mózgu konkwisty. Jego `conquest.ger.lua` ma 357 wpisów wobec 185
w stocku (nowy schemat `availability`/`grade`), ale pliki `*f.<nacja>.lua`
(frontlines) jedzie na **starym schemacie `priority` + `type={"Class2",…}`**.
Pierwszym wpisem jego rosteru jest `detect_error_vehicle` — jego własny kanarek
na zepsutą listę.

## 3. Co z tego wynika dla co-opa

**Bot liczy się po jednej stronie.** `utility.lua:329`:

```lua
math.randomseed(os.time() * BotApi.Instance.hostId)
```

Ziarno z zegara ściennego. Gdyby ten kod chodził równolegle u obu graczy
w symulacji lockstep, mecz rozjeżdżałby się w pierwszej sekundzie — a nie
rozjeżdża się. Czyli bot działa jak wirtualny gracz po stronie hosta i wysyła
rozkazy, a nie liczy się u każdego z osobna. **To nie znosi zasady, że pliki
muszą być identyczne** — tego nigdy nie sprawdziliśmy osobno i nie ma powodu
ryzykować meczem; traktujemy Lua jak każdy inny plik paczki.

**Nadpisanie luźnym plikiem działa** — mamy na to dowód z września: nasza
porzucona podmianka `conquest.lua` + `runtime_context.lua` (leży w
`HF_PATCH_PODMIANA/_KOPIA_ZAPASOWA_2026-09-20_…/`) była ładowana. W `game.log`
widać zresztą rozwiązane ścieżki:

```
[LUA] DBG: trying to load file resource/script/multiplayer/modes/conquest.lua
[LUA] DBG: Loading resource/script/multiplayer/modes/conquest.lua
```

**Detektor Hortena jest wyłączony.** `hf_check_compat$` nadal występuje
w `multi.pak → multi/HF-dcg_script.inc:185`, ale cały blok to
`{## "hf debugging/error 03"`, czyli **blok wyłączony** (`##` z dokumentacji SDL —
tu potwierdzony w prawdziwym pliku moda). Nie musimy już ustawiać tej zmiennej.

### Ryzyko wg rodzaju pliku

| plik | ryzyko podmianki | dlaczego |
|---|---|---|
| `modes/conquest/runtime_config.lua` | **niskie** | same liczby, Horten go nie wydaje, więc jego update tego nie cofnie |
| `modes/conquest/purchase_profiles.lua` | niskie-średnie | dane + trochę logiki losowania |
| `units/<nacja>/*.lua` | **wysokie** | Horten je wydaje i aktualizuje — każda nasza zmiana wymaga trójstronnego merge'u przy jego update'cie, dokładnie jak w [[horten-stale-overrides]] |
| `modes/conquest/*.lua` z logiką | średnie | nie cofnie ich update Hortena, ale błąd w Lua psuje bota po cichu |
| `utility.lua`, `bot.main.lua` | wysokie | wspólne dla wszystkich trybów |

### Gotowy kanał pomiarowy

`utility.lua:3` ma **`printDebug = true` już w stocku**, a wszystkie decyzje bota
lądują w `game.log` z prefiksem `[LUA] Print:`. Z ostatniego meczu:

```
purchasePressure defender_opening base= 8 pressureAdjusted= 12 risk= low riskDelta= -1
  difficulty= hard difficultyDelta= 1 cpStage= Stage5 battleScaleDelta= 3
  ArmyCP= 4294967295 ArmyCPLimit= 440 commitment= FullCommitment commitmentDelta= 1
purchasePlan phase= defender_opening targetBudget= 24 primary= armored_force
  secondary= anti_tank_force lanes= armored_body=7,armored_infantry_support=10,…
purchasePick phase= defender_opening lane= armored_body unit= bt2_da2 grade= Grade1
  platform= Tank cost= 1 weight= 0.4554
```

To jest sonda za darmo: widać pas, jednostkę, wagę i każdy składnik presji.
Nie trzeba niczego wstrzykiwać, wystarczy czytać log po meczu.

### Jedna rzecz do sprawdzenia, wygląda na usterkę

`ArmyCP= 4294967295` to `0xFFFFFFFF`, czyli −1 na niczym nieustawionym liczniku.
`GetPlayerBattleCommitmentBand` (`purchase_pressure.lua:86`) broni się tylko przed
`nil` i `cpLimit <= 0`, więc liczy `4294967295 / 440` i **zawsze** wychodzi
`FullCommitment` — w tym meczu +1 jednostka do garnizonu obrońcy. Jeżeli w DCG
ArmyCP nigdy nie jest ustawiane, to cały człon „zaangażowanie gracza" jest martwy
i zawsze dociska w jedną stronę. Do potwierdzenia: jedna bitwa konkwisty
i `grep purchasePressure game.log`.

## 4. Gdzie są realne pokrętła

Wszystko poniżej to zmiana liczby w `runtime_config.lua`, bez dotykania logiki:

- `AttackerWaves` — `MaxWavesMin/Max` (4–5), `MinUnits/MaxUnits` (5–6), kształt fali
  (`escalating`, `flat`, `frontloaded`, `last_push`);
- `AttackerDynamicWaveOff` — odstęp między falami (135/165/210 s wg stanu
  poprzedniej fali) i poprawka za postęp na flagach;
- `DefenderOpening` — garnizon 7–8 jednostek **na flagę**, `MaxDuration` 60 s,
  `UnitsHoldMovement`;
- `DefenderCounterattack` — 3–5 jednostek, `ResponseChance` 0.75, `MaxTotal` 3;
- `PurchasePressure.DifficultyPurchaseCountDelta` — ile dokłada każdy poziom
  trudności (heroic: +1/+2/+2);
- `CombatPressureWeights` / `AssaultWeights` / `PlayerDefenseWeights` — jak bot
  wycenia nasze siły (np. ciężki pancerz = 30 piechurów w presji, 18 w szturmie);
- `PurchaseScoring` (linie 390–630) — wagi `availability`, `grade`, klas i pasów.

Dla co-opa najciekawsze jest to, że **presja skaluje się liczbą i siłą graczy**
(`PlayerBattleScalePurchaseCountDelta` po progach CP, `commitment` po zużyciu CP).
Czyli „we dwóch jest za łatwo / za trudno" reguluje się tutaj, a nie w trudności.

---

**Zasada niezmieniona:** plik, który podmieniamy, trafia do paczki i do kolegi
([[hf-patch-package]]), a przy update'cie Hortena robimy trójstronne porównanie.
Roster zmieniamy tylko wtedy, gdy naprawdę musimy — to jego teren.
