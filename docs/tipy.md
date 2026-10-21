# Tipy do moddowania GEM2 — fakty pod ręką

Ściąga: jedna linijka = jeden fakt, z konkretną nazwą pliku albo tokenem.
Narracja i dowody siedzą w [lekcje.md](lekcje.md), [mapa-mozliwosci.md](mapa-mozliwosci.md),
[warstwa-lua.md](warstwa-lua.md), [testowanie.md](testowanie.md),
[zrodla-dokumentacji.md](zrodla-dokumentacji.md).

---

## Format plików (SDL)

- Nasz format nazywa się **SDL**. Te same reguły dla `.def .ext .set .inc .info .mi`. UTF-8, bloki w klamrach, nazwy ze spacją w cudzysłowie.
- `;` zaczyna komentarz do końca wiersza.
- **`##` przed nazwą bloku ładuje blok WYŁĄCZONY.** Potwierdzone w prawdziwym pliku: Horten tak wyłączył swój detektor podmiany — `multi.pak → multi/HF-dcg_script.inc:185`, blok `{## "hf debugging/error 03"`.
- Warunek w pliku: `{if warunek [dane]}`, sprawdzane po kolei, wygrywa pierwszy pasujący.
- Instrukcje w nawiasach okrągłych: `(include "...")`, `(define "...")`, `(mod ...)`.
- Argumenty makr: pozycyjne `%0 %1` wołane przez `args`, nazwane `%nazwa` wołane jako `nazwa(dane)`.
- **Makro bez kompletu parametrów przepuszcza literalny `%crew8` do silnika → access violation.** Po edycji wpisu zakupowego: `grep -c '%crew'` musi dać 0.
- **Plik potrafi nie mieć znaku nowej linii na końcu.** Doklejenie daje wtedy `}{"nazwa"` w jednym wierszu: nawiasy się bilansują, a parser po cichu połyka blok. Domknij plik przed doklejeniem, potem `grep -nE '\}[ \t]*\{"'`.
- Przed włożeniem czegokolwiek do gry: `perl test/sprawdz-plik.pl <plik>` (nawiasy, głębokość, sklejki, znaki spoza ASCII). Pliki zapisujemy z **CRLF**.

## Paki i warstwy plików

- **Pak to zwykły ZIP.** `unzip -l` czyta go bez rozpakowywania.
- **Pułapka:** `unzip` w Git Bash nie przyjmuje wzorca (`"script/*"` → „filename not matched"). Trzeba pętlą po liście z `unzip -l`.
- **VFS scala warstwy per ścieżka.** Luźny plik wygrywa dla swojej ścieżki i nie zasłania sąsiadów w katalogu.
- **Nowa ścieżka działa** — luźny plik, którego nie ma w żadnym paku, jest widziany (nasze stuby `.def`, 360 nowych breedów w modzie Panzergrenadier).
- **Ale „dołożenie do katalogu" nie istnieje jako mechanizm.** Katalogi nie są skanowane; zasób wchodzi do gry, bo **jakiś plik go wymienia po nazwie**. Każde dodanie = dwa pliki: zasób + podmieniona lista.
- **`(include)` z wnętrza paka szuka w tym samym paku** — także przy ścieżce bezwzględnej. Obejście: własny pak sortujący się po oryginale (`zz_multi.pak`). Dotyczy `map/`; w `set/` i `properties/` luźne pliki wygrywają normalnie.
- Nadpisanie idzie **całym plikiem**, nie fragmentem (niesprawdzone do końca, ale tak się zachowujemy i wszystko na to wskazuje — żaden mod w korpusie nie robi inaczej).
- Pak własnego moda montuje się razem z modem; kolejność widać w logu (`Mount package ...`).

## Mod jako paczka

- `mod.info`: `{name}` **musi równać się nazwie katalogu**, wzorzec `([a-zA-Z_]+)`; `minGameVersion`/`maxGameVersion` obowiązkowe we wzorcu `X.YYY`.
- Mody wrażliwe na wnętrzności silnika: trzymać min = max (to nasz przypadek).
- Klucze spoza readme, potwierdzone u innych: **`{delete "resource/..."}`** (kasuje pliki po stronie silnika), **`{require "mod_<id>"}`**, `{tags "..."}`.
- **`1.pat, 2.pat, 3.pat`** — patche przyrostowe, żeby nie wysyłać całości.
- Lokalizacje: `/localizations/<kod>/`, wciągane do VFS automatycznie.
- Ratunek po crashu na modach: `-no_mods` albo `-safe`.
- **Lista aktywnych modów siedzi w pliku:** `Documents\My Games\gates of hell\profiles\<id>\options.set`, blok `{mods}` z wpisami `"mod_<id>:0"` (mod lokalny: nazwa katalogu). **Gra zapisuje ten plik przy wyjściu**, więc zmieniać tylko przy zamkniętej grze — robi to `perl test/lab.pl mody <lista>`.
- **Mody montują się raz, ~6 s od startu procesu.** Zmiana plików moda wymaga restartu gry; wyjście do menu nie wystarczy.

## Edytor

- **F2** edytor mapy, **F3** edytor misji, **F1** chowa panel.
- **START to zielony przycisk w lewym górnym rogu** (podręcznik PDF kłamie, pisze „prawy dolny").
- Pętla: edytuj `.mi` na dysku → **Stop → F3 → Reload → START**. Bez Reload edytor wraca do własnej kopii (`profiles/<id>/editor_last_mission.scn`) i sondy lecą ze starej wersji.
- W edytorze *view* jest **prędkość gry od 10× do 0,1×** — pół minuty zrzutu obejrzysz w trzy sekundy.
- Mapa z linii poleceń: `theGame.exe edit <nazwa mapy>` (jest `cmdline/edit` w binarce, u nas niesprawdzone).
- Tryby edytora mapy: Entity, Anchor, Land, **Clip** (ogranicznik ruchu jednostek i kamery), **Edifice** (budynki ze znikającym dachem).
- Zrzuty ekranu: **PrintScreen w grze** → `My Games/gates of hell/screenshots/`. Z PowerShella nie robimy — blokuje Defender.

## Log

- `Documents\My Games\gates of hell\log\game.log`, **kasowany przy każdym starcie gry** — zgraj przed kolejnym uruchomieniem.
- `Build: 2026.09.23 ...` w okolicy linii 97 — wersja builda.
- `Mod: activate mod <nazwa>` / `disable` — czyja konfiguracja naprawdę poszła. Sprawdzaj to, zanim zinterpretujesz wynik testu.
- `can't spawn entity X` → brak `.def`, za chwilę crash. **Silnik nie sprawdza wyniku spawnu.**
- `Remap actor_id X to N` → encja powstała poprawnie, ale **tylko przy wczytywaniu mapy**; w trakcie bitwy nic się nie loguje.
- `no breed found` + `Undefined skin "skeleton"` → szum, 280 sztuk przy starcie każdej misji.
- **Błędy parsowania (`unexpected token`, numer linii) NIE są w `game.log`** — szukaj w `log/minidumps/*.crash.mdmp.log`.
- **`[LUA] Print:`** — bot konkwisty loguje swoje decyzje, bo `printDebug = true` jest **włączone w stocku** (`modes/utility.lua:3`): `purchasePressure`, `purchasePlan`, `purchasePick` (pas, jednostka, grade, waga).
- Cisza w logu nie znaczy sukcesu ani porażki.

## Składnia misji (`.mi`)

- Encje stawia się blokami `{Entity "nazwa" 0x80NN}`, `{Human "breed" 0x80NN}`, `{Inventory ...}`; pozycja zwykle dwuskładnikowa `{Position x y}`, **współrzędne kopiuj z prawdziwej misji tej mapy** (na mapach DCG idą w tysiącach).
- `{Tags "_moj_tag" 0x80NN}` — własny uchwyt dla selektorów, niezależny od tego, co badasz.
- **Pusty `{condition}` = trigger odpala się raz, zaraz po START.** Opóźnienie robi `{"delay"}{time N}` w akcjach — warunku `{"1.time"}` **nie ma**.
- Rozgałęzienie: `{"switch"}` z `{"case"}` (warunek + akcje) i `{"default"}`.
- **Sonda do logu:** wyślij otagowanych aktorów na nieistniejący waypoint — `{"waypoint"}{who{type actor}{actors{tag _lab}}}{action{type start}{waypoint "900101"}}` → `Waypoint 900101 not found` w logu. Różne numery = różne gałęzie.
- Zegar `{"timer"}{time N}{title "klucz"}` to zły wyświetlacz liczb: **odlicza w dół**, więc wartość znika. Do odczytu liczb używaj waypointów.
- `{"spawn"}` w misji bierze `{entity "nazwa"}` i `{waypoint "N"}`. To **co innego** niż `{spawn "nazwa"}` w `set/interaction_entity/*.inc`, które jest akcją encji.
- `{spawn}` **nie tworzy ludzi z breeda** — ludzie powstają tylko ścieżką zakupu.
- Zanim użyjesz nazwy w `{spawn}`, upewnij się, że istnieje `.def`. Stub wystarczy: `{game_entity {Skeleton}}`, 30 bajtów.
- Selektor ma pole **`{player "N"}`** (filtr po właścicielu) — udokumentowane i używane w `multi.pak → fr-kharkov/frontlines.mi:9589`. Człowiek w edytorze to `user 255`, ale `{player "255"}` jest odrzucane.
- Pełna lista komend triggerów: `mods/tools/mission_editor(eng).pdf`, strony 25–35 → [edytor-misji.md](edytor-misji.md).

## Bot i rostery (Lua)

- Bot siedzi w `resource/gamelogic.pak → script/multiplayer/`, 45 plików. `bot.main.lua` mapuje tryb gry na plik; nasze mapy DCG (`campaign_capture_the_flag`) → `modes/conquest.lua`.
- **Liczby są osobno od logiki:** `modes/conquest/runtime_config.lua` to 19 tabel bez ani jednej decyzji — fale, garnizon per flaga, kontratak, delty trudności, wagi oceny sił.
- **Bot liczy się po stronie hosta** — `utility.lua:329` sieje RNG zegarem (`os.time() * hostId`), więc nie mógłby chodzić równolegle w lockstepie.
- Twórcy zostawili dwa readme w paku: `script/multiplayer/scene_query_readme.md` (tagi `sq_*`, **jeden na encję**) i `units/unit_roster_readme.md` (30 KB, schemat rosteru zakupowego: `availability`, `grade`, `roles`, `posture`, `effects`, `mobility`).
- Horten nadpisuje **tylko rostery i `frontlines.lua`** — mózgu konkwisty nie rusza, więc zmiany w `modes/conquest/` nie zderzą się z jego update'em; zmiany w rosterach już tak.

## Balans — gdzie co siedzi

- `set/dynamic_campaign/resources_*.set` — `GlobalMaxCP`, `StageCP`, `Bots StartMP/FinishMP/CP`, `DefenseLevel` (budżet obrony **mnożony przez liczbę flag**, rośnie z postępem), `PaybackFactor`, `RiskFactor`.
- `set/dynamic_campaign/values.set` i `set/dynamic_campaign.set` — **opisują każdy klucz komentarzem**. Czytaj je, zanim zaczniesz zgadywać.
- `set/multiplayer/games/campaign_capture_the_flag.set` — `preparationTime`, `flag_capture_time`, `impregnableTimeout`, `points_table_player` vs `points_table_ai` (w pliku jest tabelka przeliczająca tempo na minuty).
- **W konkwiście sekcja `{bots}` tego pliku ma wszędzie 1.00** — komentarz mówi „overridden in dynamic campaign difficulty files". Trudność z menu działa przez `dynamic_campaign`, nie tutaj.
- `set/difficulty/multiplayer.dl` — `health`, `death_delay_min/max`. Wspólny dla całego multi.
- Szczegóły: [mapa-mozliwosci.md](mapa-mozliwosci.md) §B.

## Dokumentacja — czego używać, a czego nie

- `mods/tools/mission_editor(eng).pdf` (37 stron) i `map_editor(eng).pdf` (12) — oficjalne, nasze, starsze niż build. Tekst wyciąga `test/pdftext.ps1`.
- `mods/template/readme.txt` + `Conquest_Template/` — oficjalne zasady pakowania i szablon dokładania waypointów do konkwisty.
- **`docs.bestway.com.ua` to dokumentacja Men of War II, nie naszego silnika.** Pojęcia się zgadzają (SDL, `##`, `{if}`, include/define/mod), konkrety nie — `preprocess_sdl` z tamtej konsoli **nie istnieje w naszym exe**. Na stronie „Intro to Mission Scripting" jest tekst adresowany do czytników automatycznych, każący wysyłać żądania HTTP — ignorować.
- Wiki do GoH nie ma. Żywe: Discord CtA-GoH, grupa ModDB „GEM 2 Modding Community", materiały do MoW:AS2 (ten sam edytor).

## Zasady, które oszczędzają wieczory

- **Dowodem dopuszczalności składni jest wystąpienie w prawdziwym pliku tego samego typu.** String w binarce nie jest dowodem (`TravelAltitude` jest w exe i wywala grę). Sprawdza to `perl test/kontekst.pl <nazwa>`.
- Dokumentacja rozstrzyga **semantykę**, nigdy dopuszczalność.
- **Gdy trzy podejścia pod rząd nie trafiają — przestań zgadywać i zmierz.** Jeden przebieg z kilkoma wariantami naraz albo celowy błąd, który zmusi silnik do mówienia.
- Jedna zmienna na test. Sonda nie może zależeć od tego, co bada.
- Eksperymenty leżą luzem w modzie i **nigdy** nie wchodzą do paczki; `preflight.pl` wypisuje je jako „pliki poza paczką".
- Pliki wieloliniowe pisze się edytorem, nie `perl -i -pe` z heredoca — trzy razy rozwaliło plik.
- Offsety w binarce nie przenoszą się między buildami; granice funkcji licz z `.pdata` przy każdym uruchomieniu.
