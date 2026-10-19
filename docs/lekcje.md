# Lekcje z moddowania GEM2

Spisane po sesji 2026-10-19, w której próba dodania rozkazu zrzutu spadochronowego
zajęła kilkanaście podejść, dwa crashe i parę straconych bitew. Prawie wszystkie
porażki miały tę samą przyczynę.

---

## 1. Nie wnioskuj składni z analogii. Sprawdź w prawdziwym pliku.

To jest ta jedna lekcja, z której wynika reszta.

Każda wpadka tego dnia to była wymyślona składnia, nigdy zły pomysł:

| co założyłem | jak jest |
|---|---|
| warunek `{"1.time"} {time 5}` | **nie istnieje** — natychmiastowy trigger to pusty `{condition}`, opóźnienie przez `{"delay"}` w akcjach |
| `offset X Y Z`, gdzie Z to wysokość | **wszystkie trzy przesuwają w poziomie** |
| `{mode passengers}` wysadzi załogę | załoga i pasażerowie to osobne byty — potrzebny `{mode crew}` |
| luźny plik w `set/breed/` przesłoni katalog | **nie przesłania** — Horten sam ma 6 luźnych w `set/target` przy 17 w paku |
| nazwa encji zadziała jak tag w selektorze | działa dla `conquest_spawn_helper`, **nie zadziałało** dla `c47_d` |

Wzorzec: za każdym razem, gdy najpierw czytałem prawdziwy plik, wychodziło za pierwszym
podejściem — stuby encji, wpis kosztowy samolotu, `vehicle()` w zakupie. Za każdym razem,
gdy zgadywałem, trzeba było cofać.

```bash
grep -rhoE '\{spawn "[^"]+"[^{}]*' <katalog z plikami gry>   # co naprawdę przyjmuje spawn
grep -rhoE '\{mode [a-z_]+\}' <skrypty misji>                # jakie tryby istnieją
```

## 2. Mierz, nie wnioskuj

Gdy trzy podejścia pod rząd nie trafiły w to, która wartość `offset` jest wysokością,
rozwiązaniem nie było czwarte zgadywanie, tylko **eksperyment**: cztery czasze, każda
z przesunięciem na innej osi, w odstępach po trzy sekundy. Jedno uruchomienie, jednoznaczna
odpowiedź.

Jedna zmienna na test. Jeśli test ma sprawdzić wysokość, usuń z niego żołnierzy.

## 3. Silnik albo milczy, albo wywala grę. Nie ma nic pomiędzy.

```
{spawn "mp/ger/mid/fallsch_para_drop"}   → cisza, zero w logu, nic się nie dzieje
{spawn "conquest_paradrop_ger"}          → can't spawn entity → null → CRASH
```

Brakująca encja to crash, bo silnik **nie sprawdza wyniku spawnu**. Ten sam wzorzec
siedzi za wrześniowym crashem z `Entity::Load`.

Praktycznie: zanim użyjesz nazwy w `{spawn}`, upewnij się, że istnieje jako `.def`.
Stub wystarczy, 30 bajtów:

```
{game_entity
	{Skeleton}
}
```
w `entity/service/damage/artillery_barrage/<nazwa>.def`.

## 4. Encja, breed i blok interaction to trzy różne rzeczy

Najdroższe nieporozumienie dnia.

- **encja** — `.def` w pakach `entity/*`, to ją tworzy `{spawn}`
- **breed** — `set/breed/mp/<nacja>/<okres>/<nazwa>.set`, definiuje człowieka: skin, ekwipunek, tagi.
  `{spawn}` **nie tworzy ludzi z breeda** — milczy. Ludzie powstają tylko przez ścieżkę zakupu.
- **blok interaction** — `{"nazwa"}` w `set/interaction_entity/*.inc`, dokleja zachowanie
  do istniejącej encji. Sam z siebie niczego nie tworzy.

Breed może nieść tagi (`{tags "soldier eject"}`) i to jest czysty sposób na uchwyt dla
selektora, bez łapania cudzych jednostek.

## 5. Makra wymagają kompletu parametrów

`squad_vehicleN` ma dokładnie N slotów `crewN`. Podanie siedmiu do `squad_vehicle10`
wysłało do silnika dosłowny `%crew8` jako nazwę breeda:

```
> gui2:lre:spawn(mp/ger/mid/%crew8)
EXCEPTION_ACCESS_VIOLATION read at 0x00000000
```

Po każdej edycji wpisu zakupowego: `grep -c '%crew' <plik>` musi dać **0**.

## 6. Offsetów nie przenosi się między buildami

Crash z sierpnia pod `0x721fda` w buildzie 1.0.6.6 wypada w zupełnie innej funkcji.
Gra aktualizuje się co kilka tygodni. Dlatego harness liczy granice funkcji z `.pdata`
przy każdym uruchomieniu, zamiast trzymać zapisane adresy.

## 7. Trzymaj produkcję z dala od eksperymentów

Patch co-op (19 plików) i pliki eksperymentu leżały obok siebie w tym samym modzie,
ale **nigdy się nie przecięły**. Dzięki temu dwa crashe i kilkanaście nieudanych prób
nie tknęły tego, w co faktycznie gracie.

Po każdej zmianie: lista plików w modzie minus lista plików w paczce = tylko eksperymenty.

## 8. Log kasuje się przy starcie gry

`Documents\My Games\gates of hell\log\game.log` jest nadpisywany przy **każdym**
uruchomieniu. Po nieudanej próbie: najpierw zgraj log, dopiero potem odpalaj ponownie.

Mody montują się raz, w ~6 sekundzie od startu procesu (`Mod: activate`). Zmiana
plików moda **wymaga restartu gry** — wyjście do menu nie wystarczy.

## 9. Czego szukać w logu

| wpis | znaczenie |
|---|---|
| `can't spawn entity X` | brak `.def` — za chwilę będzie crash |
| `no breed found` + `Undefined skin "skeleton"` | **szum, nie nasza wina** — 280 sztuk przy starcie każdej misji |
| `not registerd in unit manager` | wisząca referencja, zwykle nieszkodliwa |
| `Remap actor_id X to N` | encja powstała poprawnie — **tego szukaj, żeby potwierdzić sukces** |
| `***** Exception *****` | pełny stos z nazwą funkcji na dole, np. `scene:quant:vehicle:buq` |

## 10. Cisza w logu nie znaczy sukcesu

Udane spawny nic nie logują. Brak błędu znaczy tylko tyle, że nie było błędu — nie że
coś zadziałało. Potwierdzenia szukaj w `Remap actor_id` albo na ekranie.
