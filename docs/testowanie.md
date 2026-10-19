# Pętla testowania

Jedna iteracja to: edycja → kontrola → restart gry → jedna bitwa → log.
Trwa kilka minut, więc każdy błąd złapany **przed** uruchomieniem jest wart dziesięciu
złapanych po.

```bash
perl test/preflight.pl
```

Kończy werdyktem `>>> mozesz testowac` albo `>>> NIE ODPALAJ`.

---

## Co sprawdza

| kontrola | dlaczego |
|---|---|
| nawiasy `{}` i `()` | literówka cicho psuje parsowanie całego pliku |
| niepodstawione `%param` | dosłowny `%crew8` poleciał jako nazwa jednostki i **wywalił grę** |
| arność `squad_vehicleN` | makro na 10 załóg z siedmioma to ten sam crash |
| `{spawn "X"}` bez encji | brak `.def` → null → **crash**, najczęstsza przyczyna |
| nazwy akcji i termów warunków | nieznana nazwa to cisza albo **crash** — sprawdzane względem `data/slownik/tablice.txt` wyciągniętego z binarki (bez słownika kontrola się pomija z ostrzeżeniem) |
| końce linii vs oryginał | część plików silnika wymaga CRLF |
| pliki spoza patcha | eksperymenty nie mogą wyciec do wersji produkcyjnej |
| czy gra chodzi | mody montują się przy starcie, zmiany w trakcie nie wejdą |

Dwie kontrole mają **znane fałszywe alarmy** i zgłaszają ostrzeżenie zamiast błędu:
indeks encji bywa niepełny (nie widzi wszystkiego, co jest w pakach), a porównanie
końców linii przez shell zawodzi, bo backticki normalizują znaki.

Przy ostrzeżeniu o brakującej encji **sprawdź ręcznie** — to jedyny błąd, który
gwarantuje crash.

---

## Kolejność, która się sprawdza

1. **Kontrola** — musi dać „można testować"
2. **Zamknij grę** przed kopiowaniem plików
3. **Wdróż**
4. **Jedna bitwa, jedna zmienna** — jeśli test dotyczy wysokości, wywal z niego
   wszystko inne
5. **Zachowaj log przed ponownym uruchomieniem** — `game.log` kasuje się przy
   każdym starcie gry
6. **Przeczytaj log**

---

## Co znaczą wpisy w logu

| wpis | znaczenie |
|---|---|
| `can't spawn entity X` | brak `.def` — za chwilę crash |
| `Remap actor_id X to N` | encja powstała poprawnie — **tego szukaj jako potwierdzenia** |
| `***** Exception *****` | pełny stos, na dole nazwa podsystemu |
| `no breed found` + `Undefined skin "skeleton"` | szum, setki przy starcie każdej misji |
| `not registerd in unit manager` | wisząca referencja, zwykle nieszkodliwa |

**Cisza nie znaczy sukcesu.** Udane spawny nic nie logują. Brak błędu znaczy tylko tyle,
że nie było błędu — potwierdzenia szukaj w `Remap actor_id` albo na ekranie.

---

## Mierzyć, nie wnioskować

Gdy trzy podejścia pod rząd nie trafiły w to, która wartość `offset` jest wysokością,
rozwiązaniem nie było czwarte zgadywanie, tylko eksperyment: cztery obiekty, każdy
z przesunięciem na innej osi, w odstępach po trzy sekundy. Jedno uruchomienie,
jednoznaczna odpowiedź.

Jeśli nie wiesz, jak zachowa się parametr — zrób test, który pokaże wszystkie warianty naraz.

---

## Raport dla drugiej osoby

Gdy nad czyms pracujesz z kims, kto nie siedzi przy tym komputerze
(albo z asystentem), wyniki trzeba jakos przekazac. Opisywanie z pamieci
gubi szczegoly, a przeklejanie konsoli jest upierdliwe.

```
raport.bat        (dwuklik)
```

Jedno polecenie zbiera wszystko do `data/raport.txt`: wersje gry i moda, kontrole
plikow, delte, triage logu i slady naszych encji. Dodatkowo archiwizuje `game.log`
do `data/logi/`, zanim skasuje go nastepny start gry.

Potem wystarczy wskazac plik.
## Raport dla drugiej osoby

Gdy pracujesz z kimś, kto nie siedzi przy tym komputerze, wyniki trzeba jakoś
przekazać. Opisywanie z pamięci gubi szczegóły, przeklejanie konsoli jest upierdliwe.

```
raport.bat
```

Jedno polecenie zbiera wszystko do `data/raport.txt`: wersje gry i moda, kontrolę
plików, deltę, triage logu i ślady naszych encji. Dodatkowo archiwizuje `game.log`
do `data/logi/`, zanim skasuje go następny start gry.

Potem wystarczy wskazać plik.
