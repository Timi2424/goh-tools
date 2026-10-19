# Praca z binarką

```bash
perl pe/goh.pl <exe> info                naglowki, sekcje, liczba funkcji
perl pe/goh.pl <exe> fn    <rva>         ktora funkcja zawiera adres
perl pe/goh.pl <exe> near  <rva> [okno]  stringi wokol adresu -> modul
perl pe/goh.pl <exe> str   <regex>       stringi pasujace do wzorca
perl pe/goh.pl <exe> xref  <rva|regex>   kto odwoluje sie do stringa
perl pe/goh.pl <exe> calls <rva>         kto wywoluje funkcje
perl pe/goh.pl <exe> cpp                 pliki zrodlowe silnika
perl pe/goh.pl <exe> rtti  [regex]       klasy z RTTI
perl pe/goh.pl <exe> dump  <rva> [n]     hexdump
```

Ścieżka do exe zwykle:
`...\steamapps\common\Call to Arms - Gates of Hell\binaries\x64\call_to_arms.exe`

---

## Dlaczego to w ogóle działa

Binarka jest nietypowo przyjaznym celem:

| | |
|---|---|
| symbole PDB | brak |
| RTTI | ~2900 klas z pełnymi przestrzeniami nazw, np. `Device::Sound::eManager` |
| `.pdata` | ~85 000 wpisów RUNTIME_FUNCTION → **dokładne granice każdej funkcji** |
| nazwy źródeł | ~540 plików `.cpp` w komunikatach asercji |
| skrypty | LuaBridge + Lua 5.2.3 |
| DRM / anti-cheat | brak |

Bez symboli nie wiadomo, jak nazywa się funkcja — ale wiadomo, **gdzie się zaczyna
i kończy**, bo tablica wyjątków w `.pdata` to wylicza. To wystarcza, żeby izolować kod.

Identyfikacja modułu: silnik przy asercjach podaje nazwę pliku źródłowego. Te nazwy
leżą w `.rdata`, a kod sięga po nie instrukcją `LEA` rip-względną. Skanując `.text`
po wzorcu `48 8D 05` + przesunięcie i dopasowując cel do stringów, dostaje się mapę
„ten obszar kodu to `eGameEntityPhysics.cpp`".

**Offsetów nie przenosi się między buildami.** Gra aktualizuje się co kilka tygodni
i wszystko się przesuwa — ten sam adres w nowszym exe wypada w zupełnie innej funkcji.
Dlatego harness liczy granice za każdym razem, zamiast trzymać zapisane adresy.

---

## Przykład: czy predykat istnieje

Spór o to, czy `threating` jest prawdziwym predykatem selektora celu, czy czymś
wymyślonym. Silnik parsuje nazwy termów po stringach i zgłasza `Invalid term name`,
więc tablica musi być w binarce:

```bash
perl pe/goh.pl $EXE str "out_of_range|time_to_aim"
```

Wyszła pełna lista: `unit class threating invisible out_of_range in_ik_range in_range time_to_aim`.
Koniec dyskusji.

---

## Przykład: diagnoza crasha

Z Podglądu zdarzeń wiadomo tylko tyle: wyjątek `0xc0000005`, moduł `call_to_arms.exe`,
offset `0x72673a`.

```bash
perl pe/goh.pl $EXE fn   0x72673a      # funkcja 180 B, crash na +0xa
perl pe/goh.pl $EXE dump 0x72673a 16   # mov eax,[rcx+0x1C0]  -> odczyt pola z NULL-a
perl pe/goh.pl $EXE near 0x72673a      # sasiedztwo: eGameEntityPhysics.cpp
```

Potem pytanie, skąd wziął się null. W logu było `Entity::Load(): Can't find entity with ID=`:

```bash
perl pe/goh.pl $EXE xref "Can't find entity"
```

Jedna funkcja, w `eEntityTypes.cpp`:

```bash
perl pe/goh.pl $EXE calls <adres tej funkcji>    # 116 wywolan
```

Prawie wszystkie w bloku deserializacji komend. Wniosek: przychodząca komenda symulacji
wskazywała encję, której lokalnie nie było, resolver zwrócił nulla, a fizyka go nie
sprawdziła.

---

## Czego to nie umie

**Nie dezasembluje.** `dump` daje hex, instrukcje trzeba czytać ręcznie. Do szukania
nazw akcji, termów i enumów to wystarcza, bo one są stringami. Do analizy przepływu
sterowania potrzebna byłaby Ghidra, a do niej Java.

---

## Trzy komendy dołożone później

```bash
perl pe/goh.pl <exe> dis      <rva> [n]   czesciowy dezasembler
perl pe/goh.pl <exe> pattern  <hex>       szukanie po bajtach, ?? = dowolny
perl pe/goh.pl <exe> strblock <rva>       ciagly blok stringow
```

### `dis`

Dekoduje podzbiór x86-64, który realnie występuje w prologach i wokół crashy:
push/pop, mov, lea, arytmetyka, test, call, skoki, movzx/movsx, podstawowe SSE.
Przy nieznanym opkodzie wypisuje `db XX` i idzie dalej o bajt — nie zapętla się,
ale od tego miejsca może zgubić synchronizację.

**To nie jest pełny dezasembler.** Do analizy przepływu sterowania w większej skali
lepiej postawić Ghidrę. Tu chodzi o szybkie „co jest pod tym adresem", bez odpalania
czegokolwiek.

Adres w środku instrukcji da bzdurę w pierwszej linii i wyprostuje się w kolejnych —
tak wygląda próba czytania adresu z innego builda.

### `pattern`

Szukanie po bajtach z maską. Kluczowe przy patchowaniu binarki: **offsety zmieniają się
przy każdym update gry**, więc patch nie może być przypięty do adresu. Musi szukać
unikalnego wzorca bajtów i dopiero wtedy wiedzieć, gdzie jest.

```bash
perl pe/goh.pl <exe> pattern "48895c2408 57"     # dokladne bajty
perl pe/goh.pl <exe> pattern "4889??2408"        # ?? = dowolny bajt
```

Jedno trafienie = wzorzec nadaje się na kotwicę patcha. Czterdzieści = szukaj dłuższego.

### `strblock`

Wypisuje stringi leżące obok siebie, zaznaczając większe przerwy. Ciągły blok bez przerw
to zwykle **tablica nazw** — a tak właśnie silnik trzyma listy akcji, termów warunków
i enumów.

Przykład: `strblock` wokół `eTargetSelectAmmo.cpp` daje od razu komplet flag amunicji —
`in_bush`, `enable_for_ai`, `enable_for_user`, `enable_for_human_user`, `check_grenade`,
`ready_for_shot`, `charging`, `ignore`.

Metoda na szukanie takich tablic: znajdź `str` nazwę pliku `.cpp` odpowiedzialnego
za dany system, potem `strblock` na jej adres.
