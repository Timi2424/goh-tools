# Luźne pliki: dokładanie czy podmiana — co już wiemy i co trzeba zmierzyć

Pytanie nr 1 z [mapa-mozliwosci.md](mapa-mozliwosci.md). Okazało się, że w połowie
jest już rozstrzygnięte danymi, które mamy na dysku — poniżej najpierw to, potem
test na resztę.

---

## 1. Co rozstrzyga sam korpus (bez uruchamiania gry)

### Luźny plik **nie przesłania katalogu**. Scalanie idzie po ścieżce.

Sprzeczność, którą zapisałem w mapie, była moim błędem odczytu — obie obserwacje
mówią to samo. W `set/target` pak ma 17 plików, a luźnych leży 6 (nasze) i
**pozostałe 11 z paka nadal działa** — gdyby luźny plik zasłaniał katalog, gra
nie miałaby tabel trafień dla człowieka (`human.inc` jest tylko w paku) i byłoby
to widać w pierwszej minucie bitwy.

Wniosek: VFS scala warstwy **per ścieżka**, nie per katalog. Luźny plik wygrywa
dla swojej ścieżki i nie rusza sąsiadów.

### Nowa ścieżka **działa** — i to w dwóch niezależnych dowodach

1. **Nasze stuby z eksperymentu spadochronowego.** `entity/service/damage/artillery_barrage/conquest_paradrop_*.def`
   nie istnieją w żadnym paku gry, leżą luzem w folderze moda i `{spawn}` je znajduje
   (przed ich dołożeniem było `can't spawn entity` i crash).
2. **Mod „Panzergrenadier" (workshop 3495417827).** Z 1265 luźnych plików `set/breed`
   **360 nie ma odpowiednika w żadnym paku gry** — to czysto nowe ścieżki, np.
   `set/breed/mp/eng/late/para_piat.set`.

### Ale „dołożenie do katalogu" to nie jest mechanizm, który w ogóle istnieje

Silnik nie skanuje katalogów po to, by zbudować listę. Zasoby bierze **po nazwie
albo ścieżce, z pliku, który je wymienia**. Ten sam mod pokazuje to wprost —
nowy breed staje się kupowalną jednostką dopiero dlatego, że jest wpisany na listę:

```
set/multiplayer/units/conquest/inf_eng.set:525
{"mp/eng/late/para_piat"   ("inf_tier4" side(eng) lvl() r(9) rm(99) cost(60.0))}
```

Mod wiezie więc **jedno i drugie**: 360 nowych breedów **oraz** podmienione pliki
list w `set/multiplayer/units/`. Tak samo `set/breed/<nacja>/<okres>/` nie ma
żadnego pliku indeksowego — jest 462 plików `.set` i `ability.inc`, nic co by je
wyliczało. Tak samo `set/dynamic_campaign.set` trzyma jawną listę
`{GameModes "campaign_capture_the_flag"}`.

**Czyli odpowiedź brzmi: dokładać można, ale zawsze dwoma plikami — nowym zasobem
i podmienionym plikiem, który go wymienia.** A ten drugi to pełna kopia cudzego
pliku, z całym kosztem utrzymania, który już znamy z [proces.md](proces.md).

---

## 2. Co zostaje do zmierzenia

| # | pytanie | dlaczego warto |
|---|---|---|
| **P1** | Czy istnieje katalog, który silnik **wylicza** (a nie czyta po ścieżce)? Najlepszy kandydat: lista encji w edytorze i lista map. | Jeśli tak, w tych miejscach dokładanie jest darmowe — bez podmiany listy |
| **P2** | Czy luźny plik o ścieżce z paka **zastępuje go w całości**, czy treść się scala? | To jest ten kilogram: jeśli scala, przestajemy wozić 19 pełnych plików |
| **P3** | Czy luźny plik może `(include)` wersję z paka spod **tej samej ścieżki**? | Gdyby tak, mielibyśmy „dopisywanie" za darmo: include oryginału + nasze linijki |

P2 jest najważniejsze. Zakładamy „podmiana w całości", bo tak się zachowujemy od
początku, ale **nigdy tego nie sprawdziliśmy** — nosimy 229 linii zmian w 19 pełnych
plikach na podstawie założenia.

Dokumentacja Best Way dla następnej wersji silnika mówi: *pakiet może plik nadpisać
w całości **albo do niego dołożyć*** — co jest dokładnie tym, czego nie wiemy o naszym
buildzie. To nie dowód (inny silnik, patrz [zrodla-dokumentacji.md](zrodla-dokumentacji.md)),
ale powód, żeby sprawdzić, a nie zgadywać.

---

## 3. Test — jeden przebieg, cztery sondy

Wszystko w laboratorium ([testowanie.md](testowanie.md)), w **normalnej konfiguracji
z Hortenem**. Kolega nie jest potrzebny, co-op nie jest potrzebny.

### Przygotowanie — i dlaczego nie w osobnym modzie

Pierwsza wersja tego testu siedziała w czystym modzie `mods/lab_vfs`. Zrezygnowaliśmy,
bo odpowiadałby na inne pytanie niż nasze. Nasza paczka to **luźne pliki w folderze
Hortena, nad jego pakami**, a Horten wydaje własny `units_ger.set` (jego
`gamelogic.pak` ma 10 423 pliki `set/`). Czysty mod mówi, jak zachowuje się VFS
w ogóle; folder Hortena mówi, jak zachowuje się nasza paczka — i to jest pytanie,
które zadaliśmy.

Sondy leżą więc tam, gdzie od początku mieszkają nasze eksperymenty:
`workshop/content/400750/3359417100/resource/`. **Nie należą do paczki** —
`preflight.pl` ma je wypisywać jako „pliki poza paczką", a po teście znikają.

Koszt: gdyby wyszło „plik zignorowany", nie będziemy od razu wiedzieć, czy to
warstwy VFS, czy coś, co robi Horten. Wtedy dopiero wracamy do czystego moda
jako kontroli.

### Sonda A — nowa ścieżka, ktoś ją woła (kontrola dodatnia)

```
resource/entity/service/damage/artillery_barrage/lab_vfs_a.def
    {game_entity {Skeleton}}
```
Misja stawia ją przez `{Entity "lab_vfs_a" …}`, a trigger sprawdza selektorem,
czy encja jest na mapie, i wysyła dwóch ludzi na waypoint **900101** (jest) albo
**900102** (nie ma). Odczyt z `game.log`.

- **Oczekiwane:** spawn przechodzi, w logu brak `can't spawn entity lab_vfs_a`.
- **Po co:** kontrola, że mod w ogóle się montuje i że sonda B mierzy to, co trzeba.
  Gdyby A padła, reszta przebiegu jest bez wartości.

### Sonda B — czy katalog z paka jest wyliczany (P1)

```
resource/map/multi/dcg_d_uran/lab_vfs.mi
```

Sam plik misji jest sondą. Katalog `multi/dcg_d_uran/` istnieje **w dwóch pakach**
(gra: `resource/map/multi.pak`, Horten: jego `multi.pak` — ma tam `.mi` i `.info`),
a nasz plik leży obok nich luzem. W edytorze: **tytuł misji → Load other mission →
`multi` → `dcg_d_uran`**.

- **`lab_vfs` jest na liście** → katalog jest wyliczany, luźny plik się dokłada.
- **Nie ma go** → katalogi nie są wyliczane; zasób bez wpisu w jakimś pliku nie
  istnieje. Tego się spodziewam.
- Jeśli go nie ma, **wpisz ścieżkę ręcznie w pole `File:`**
  (`/map/multi/dcg_d_uran/lab_vfs.mi`). Wczyta się → silnik ścieżkę rozwiązuje,
  tylko katalogu nie wylicza. To dwie różne odpowiedzi i warto je rozróżnić.

Rezerwa: `lab_vfs_b.def` leży w `entity/service/damage/artillery_barrage/`
i nikt go nie woła — gdyby trzeba było sprawdzić to samo dla katalogu encji.

### Sonda C — podmiana vs scalanie (P2) ← najważniejsza

```
resource/set/multiplayer/units/conquest/units_ger.set
```

Oryginał to **wersja Hortena** (1625 linii, kilkadziesiąt jednostek). Nasz plik ma
jeden wpis, wycięty z niej skryptem — nie przepisywany ręcznie — z jedną celowo
wprowadzoną zmianą:

```
("squad_with6types_conquest" side(ger) period(early) min_stage(1) max_stage(9)
 name(squad_regular_early_con)  c1(nco:1) c2(nco_asst:1) c3(rifleman_1:2)
 c4(rifleman_2:13) c5(mg_26t:1) c6(mg_asst_26t:2))      ; u Hortena: rifleman_2:3
```

Oddział rośnie z 10 ludzi do 20 (i o tyle drożeje, bo cena squadu to suma cen
żołnierzy). Wchodzimy do bitwy konkwisty, strona niemiecka, zakładka piechoty:

- **tylko ten jeden oddział, 20 ludzi** → **podmiana w całości**. Potwierdza naszą
  praktykę i zamyka temat: dalej wozimy pełne pliki.
- **pełna lista, ten oddział 20 ludzi** → **scalanie**. Wtedy paczka chudnie z 19
  pełnych plików do 19 ogryzków po kilka linijek, a trójstronny merge przy
  update'ach przestaje być potrzebny — największa zmiana w procesie od początku.
- **pełna lista, ten oddział 10 ludzi** → **plik zignorowany**: containment include'ów
  dotyczy także `set/`, czyli część naszych nadpisań nigdy nie działała.

Trzeci odczyt jest po to, żeby „zignorowany" nie wyglądał identycznie jak
„scalanie" — bez zmiany liczebności nie dałoby się ich odróżnić.

### Sonda D — `(include)` samego siebie (P3), **ostatnia i osobno**

```
resource/set/target/tank_light.inc
    (include "/set/target/tank_light.inc")
    ; + jedna nasza linijka
```

- **Oczekiwane trzy wyniki:** (a) działa i mamy darmowe dopisywanie, (b) błąd
  parsowania w `log/minidumps/*.crash.mdmp.log`, (c) **rekurencja i zawieszenie gry**.
- Dlatego ta sonda idzie **jako ostatnia, w osobnym uruchomieniu**, po zgraniu logu
  z sond A–C. Jeśli gra zawiśnie — ubijamy proces i to też jest wynik.

### Procedura

```
1. perl test/lab.pl start --mody mod_3359417100     (sam Horten; --mody przestawia
                                                     blok {mods} w options.set)
2. edytor: mapa multi/dcg_d_uran
3. tytul misji -> Load other mission -> multi -> dcg_d_uran   <- SONDA B
4. wczytaj lab_vfs -> START -> zegar na HUD -> po ~5 s Stop   <- SONDA A (log)
5. perl test/lab.pl wynik                           (sondy z logu od znacznika)
6. gra: bitwa konkwisty, strona niemiecka, zakladka piechoty  <- SONDA C
7. ZGRAJ game.log  (kasuje sie przy nastepnym starcie!)
8. dopiero teraz dolóz sonde D i uruchom ponownie
```

`lab.pl mody <lista>` ustawia aktywne mody bez uruchamiania czegokolwiek. Obie
komendy odmawiaja pracy, gdy gra chodzi — zapisuje `options.set` przy wyjsciu
i nadpisalaby zmiane.

Czego szukać w logu: `can't spawn entity` (sonda A — porażka), `Remap actor_id`
(sonda A — sukces), `unexpected token` w minidumpach (sonda D).

### Czego ten test **nie** rozstrzyga

Nic o co-opie — to wszystko dzieje się u jednego gracza. Pytanie, czy gra porównuje
pliki między graczami, zostaje otwarte i wymaga drugiej osoby.

---

## 4. Co z tego wynika niezależnie od wyniku

Jedna rzecz jest już pewna i warto ją zapisać w praktyce: **każde „dodanie" to dwa
pliki — zasób i lista, która go wymienia.** Jeśli planujemy cokolwiek dokładać
(jednostkę, breeda, encję), koszt liczymy od razu jako podmianę pliku listy,
z merge'em przy każdym update'cie Hortena i gry.
