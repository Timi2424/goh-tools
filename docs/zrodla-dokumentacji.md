# Źródła dokumentacji — co istnieje, co z tego wynika

Przegląd zrobiony 2026-10-22 (build 1.067/1.068). Wszystko, co dało się znaleźć
lokalnie i w sieci, z oceną: **czy to opisuje NASZ silnik**, czy sąsiedni.

Teksty źródłowe wyciągnięte do `docs/zrodla/` — można je grepować bez otwierania
PDF-ów. **Tego katalogu nie ma w repo** (`.gitignore`, tak samo jak `data/korpus/`):
to pliki Barbedwire, a repo jest publiczne. Odtworzenie u siebie:

```bash
powershell test/pdftext.ps1 -Path "<gra>/mods/tools/mission_editor(eng).pdf" -Out docs/zrodla/mission_editor.txt
unzip -o -j "<gra>/resource/gamelogic.pak" script/multiplayer/scene_query_readme.md \
    script/multiplayer/units/unit_roster_readme.md -d docs/zrodla
```

---

## 1. Lokalnie w grze (najpewniejsze)

| plik | co opisuje | stan |
|---|---|---|
| `mods/tools/mission_editor(eng).pdf` | 37 stron: 9 edytorów, **selektory, warunki, ~30 komend triggerów** | przerobione → [edytor-misji.md](edytor-misji.md), tekst w [zrodla/mission_editor.txt](zrodla/mission_editor.txt) |
| `mods/tools/map_editor(eng).pdf` | 12 stron: edytor mapy (F2), tryby Entity/Anchor/Land/Clip/Edifice, mapy bazowe | **nieprzerobione**, tekst w [zrodla/map_editor.txt](zrodla/map_editor.txt) |
| `mods/template/readme.txt` | oficjalne zasady pakowania moda | przeczytane, patrz §3 |
| `mods/template/resource/map/multi/Conquest_Template/` | `dcg_new_waypoints_template.inc` + `dcg_new_template_additions.txt` — **szablon dokładania waypointów do konkwisty** | niesprawdzone, a dotyka wprost naszej roboty |
| `mods/tools/plug-ins/`, `ExampleFiles3dsMax/` | eksporter GEM do 3ds Max 2011–2020 + przykładowe modele (T-62, dom) | nie dotyczy nas (nie robimy modeli) |

Z podręcznika mapy, czego jeszcze nie mieliśmy: **F2 edytor mapy, F1 chowa panel**,
uruchomienie z linii poleceń `theGame.exe edit <nazwa mapy>`, mapy bazowe
200x200 … 400x600 (siatka orto- albo heksagonalna, bok 3 lub 4 m), tryb **Clip**
(ogranicznik ruchu jednostek i kamery) i **Edifice** (budynki ze znikającym dachem).

## 2. Dokumentacja deweloperska **wewnątrz paków** — tego nie znaliśmy

`resource/gamelogic.pak` zawiera dwa pliki `.md` pisane przez twórców:

- `script/multiplayer/scene_query_readme.md` → [zrodla/scene_query_readme.md](zrodla/scene_query_readme.md)
  Schemat tagów `sq_*` w `.def` jednostek: jak bot ma widzieć zagrożenie
  (`sq_armor_heavy`, `sq_at_gun`, `sq_he_large`, `sq_flame`, `sq_ammo_supply`…).
  **Jedna encja = jeden tag `sq_`**, bo funkcja scene-query w Lua dopasowuje tylko jeden.
- `script/multiplayer/units/unit_roster_readme.md` (30 KB) → [zrodla/unit_roster_readme.md](zrodla/unit_roster_readme.md)
  Pełny schemat rosteru zakupowego bota konkwisty: pola `availability`, `base`,
  `class`, `roles`, `posture`, `effects`, `mobility`, `identity`, `grade`,
  tabela konwersji starego `priority` → `availability`, zasady tagowania piechoty.

Obok nich siedzi **warstwa Lua, 43 pliki** (`script/multiplayer/`):
`bot.main.lua`, tryby `conquest.lua`, `frontlines.lua`, `battlezones.lua`,
`laststand.lua`, a pod konkwistą 18 plików logiki bota (`purchase*.lua`,
`waves.lua`, `orders*.lua`, `scene*.lua`, `runtime_*.lua`) i rostery
`units/<nacja>/{early,mid,late,conquest}.lua`.

Innych readme w pakach nie ma — przeszukane `dlc1–5`, `_dlc7`, `properties`,
`entity`, `map`.

## 3. Zasady pakowania moda (`mods/template/readme.txt`)

- nazwa folderu i `{name}` muszą być równe, wzorzec `([a-zA-Z_]+)`;
- `minGameVersion` / `maxGameVersion` obowiązkowe, wzorzec `X.YYY`; przy modach
  wrażliwych na wnętrzności silnika **trzymać równe** (to nasz przypadek);
- `1.pat, 2.pat, 3.pat` — **patche przyrostowe**, żeby nie wysyłać całości;
- lokalizacje: `/localizations/<kod języka>/`, wciągane do VFS automatycznie;
- ratunek po crashu na modach: `-no_mods` albo `-safe`.

W `mod.info` zainstalowanych modów widać klucze spoza readme, potwierdzone w praktyce:
`{delete "resource/..."}` (Horten kasuje nim mapy), `{require "mod_3562631215"}`
(patch WAVE), `{tags "Animations, Visual"}`.

## 4. docs.bestway.com.ua — oficjalna, ale **następnej wersji silnika**

Best Way wystawił dokumentację „GEM RTS", pisaną na **Men of War II**. Adresy,
foldery `packages/`, konsola i tryb symulacji są stamtąd, nie z naszego builda —
sprawdzone: `preprocess_sdl` **nie występuje w naszym `call_to_arms.exe`**.
Traktować jak słownik pojęć, nie jak instrukcję.

Co się przenosi (zgadza się z naszymi plikami):

- **SDL** to nazwa naszego formatu: `.def .ext .set .inc .info .mi`, UTF-8, bloki
  w klamrach, nazwy ze spacją w cudzysłowie;
- `;` zaczyna komentarz do końca linii;
- **`##` przed blokiem = blok ładuje się wyłączony** (do sprawdzenia u nas);
- `{if warunek [dane]}` — warunki sprawdzane po kolei, wygrywa pierwszy pasujący;
- instrukcje w nawiasach okrągłych: **`include`, `define`, `mod`** (zmiana treści
  zależnie od trybu gry), argumenty pozycyjne `%0 %1` wołane przez `args`
  albo nazwane `%nazwa` wołane jako `nazwa(dane)`;
- pakiet może plik **nadpisać w całości albo dołożyć do niego** — plik w złym
  miejscu bywa po cichu ignorowany (nasze [[pak-include-containment]] to ta sama rodzina problemów).

Strony warte przeczytania w całości, jeśli wejdziemy w modele/animacje:
`foundational-knowledge/`, `editor/`, `animation.md` (automat skończony selektora
animacji), `textures-and-materials.md`, `localization.md`. Indeks:
`https://docs.bestway.com.ua/llms.txt`.

⚠️ Na stronie „Intro to Mission Scripting" siedzi tekst adresowany do czytników
automatycznych, każący wysyłać żądania HTTP do tej witryny. Zignorowane —
odnotowane, żeby nikt się nie zdziwił.

## 5. Społeczność — niewiele i stare

- **ModDB, grupa „GEM 2 Modding Community"** (~449 osób) + sekcja tutoriali silnika
  GEM 2: eksport modeli, animacje, głosy jednostek, skiny. Głównie MoW:AS2.
- **Oficjalny Discord CtA – Gates of Hell** (~39 tys. osób, Barbedwire/Digitalmindsoft) —
  wszyscy odsyłają tam po modding; jedyne żywe miejsce.
- **Poradnik Steam 2807056750** polecany przez dewelopera na forum — strona nie
  chciała się otworzyć z naszej strony, warto spróbować z przeglądarki.
- Poradniki typu „wypakuj `0.mi` z `map.pak`, edytuj w Notepad++" — poziom, który
  mamy dawno za sobą.
- Wiki do GoH **nie istnieje**. Materiały do MoW:AS2 są w większości przenośne,
  bo to ten sam edytor.

---

## Co z tego wynika dla nas

1. **Warstwa Lua to niesprawdzony ląd z własną dokumentacją.** Zachowanie bota
   w konkwiście — zakupy, fale, rozkazy — siedzi w zwykłych plikach `.lua`
   w `gamelogic.pak`, a twórcy zostawili do tego dwa readme. To największa
   nieruszona powierzchnia, jaką mamy. Uwaga: w co-opie musi być **bit w bit
   identyczna u obu graczy**, tak samo jak reszta ([[hf-patch-package]]).
2. **`{delete}` w `mod.info` robi to, co dziś robi ręczna lista w `SPRAWDZ.bat`.**
   Jeśli paczka dla kolegi byłaby lokalnym modem, a nie luźnymi plikami na
   Hortenie, kasowanie starych plików załatwiałby silnik ([[copy-does-not-delete]]).
   Do przemyślenia, nie do zrobienia od ręki — luźne pliki mają inną kolejność
   ładowania niż mod.
3. **`.pat` to gotowy mechanizm przyrostowych aktualizacji** paczki — dziś wysyłamy
   całe `resource.zip`.
4. **Podręcznik mapy nie jest przerobiony**, a zawiera tryb `Clip` i `Edifice`
   oraz uruchamianie edytora z linii poleceń — to drugie skróciłoby pętlę
   laboratoryjną ([[laboratorium-i-sondy]]).
5. **`Conquest_Template` w `mods/template`** to oficjalny szablon dokładania
   waypointów do konkwisty — dokładnie typ pliku, przy którym się męczyliśmy.
6. Zasada bez zmian: dokumentacja rozstrzyga **semantykę**, nigdy
   **dopuszczalność**. Składnię nadal potwierdza wystąpienie w prawdziwym pliku
   tego samego typu ([[binarka-nie-rowna-sie-skladnia]]).
