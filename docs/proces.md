# Jak to utrzymywać

## Co właściwie utrzymujemy

Nie 19 plików. **229 linii zmian** rozsianych po 19 plikach, z których reszta to
przepisana treść Hortena i bazowej gry, noszona tylko dlatego, że silnik nadpisuje
całymi plikami, nie fragmentami.

```bash
perl test/snapshot-upstream.pl      # zrzuca wersje zrodlowe do upstream/
diff -r upstream hf-patch/resource  # nasza delta, nic wiecej
```

Rozkład na 2026-10-19:

| plik | linii |
|---|---:|
| `set/registry/obstacles.reg` | 58 |
| `set/dynamic_campaign/resources_low.set` | 54 |
| `properties/human.ext` | 26 |
| `set/target/*.inc` ×5 | 41 |
| `map/multi/dcg_script.inc` | 9 |
| `sound/sound.set` | 8 |
| `set/interaction_entity/construction/fence.inc` | 6 |
| `unit_research_*.set` ×5 | 20 |
| `set/target/ammo.set` | 3 |
| pozostałe | 4 |

---

## Gdy wyjdzie patch gry albo moda

To się zdarzyło 25.09 (beta) i 04.10 (Horten) i kosztowało cały dzień, bo nie było
`upstream/`. Z nim jest mechanicznie:

**1. Zapisz, co mamy teraz**
```bash
git add -A && git commit -m "stan przed update"
```

**2. Zaktualizuj grę i moda, zamknij grę**

**3. Policz dwie delty**
```bash
cp -r upstream upstream-stary
perl test/snapshot-upstream.pl            # nowe zrodla

diff -r upstream-stary upstream           # CO ZMIENIL ON
diff -r upstream-stary hf-patch/resource  # CO ZMIENILISMY MY
```

**4. Dla każdego pliku zdecyduj**

- jego zmiana a naszej nie dotyczy → **weź jego wersję, nanieś naszą deltę**
- nasza zmiana a on nie ruszał → **zostaw jak jest**
- obaj ruszali te same linie → **decyzja ręczna**, zanotuj w `zmiany.md`
- on sam naprawił to, co my → **wyrzuć nasz plik z patcha**

Po 04.10 czwarty przypadek objął **140 ze 158 plików**. Patch schudł do 19.
Dlatego najpierw licz delty, a dopiero potem kopiuj.

**5. Sprawdź i zmierz**
```bash
perl test/preflight.pl                    # musi dac "mozesz testowac"
diff -r upstream hf-patch/resource | grep -c '^[<>]'   # czy delta ma sensowny rozmiar
```

---

## Dokumentowanie zmian

Każda modyfikacja ma issue na GitHubie, a w nim:

1. **Problem** — co jest nie tak, z dowodem (linia z logu, cytat z pliku, zrzut)
2. **Spec** — które pliki, jakie wartości, czym to weryfikujemy
3. **Implementacja** — commit odwołujący się do issue
4. **Weryfikacja** — co pokazał test w grze

Commit zawsze odwołuje się do issue (`#12`), żeby po pół roku dało się odtworzyć
**dlaczego** dana wartość jest taka, a nie inna. Dziś przy `StageCP` uratowała nas
tylko moja pamięć rozmowy, że odrzuciłeś `60 80 100 120 140`.

---

## Podział pracy w repo

```
upstream/            wersje zrodlowe - NIE EDYTOWAC RECZNIE, generowane skryptem
hf-patch/resource/   nasze wersje tych samych plikow
hf-patch/*.md,*.bat  dokumentacja i weryfikator dla drugiego gracza
pe/                  harness do binarki
test/                preflight + snapshot
docs/                lekcje, plan, ten plik
patch/               jednorazowki do edycji plikow gry
```

Eksperymenty **nigdy** nie trafiają do `hf-patch/`. Leżą luzem w modzie, a `preflight.pl`
wypisuje je jako „pliki poza paczką". Dzięki temu dwa crashe i kilkanaście nieudanych
prób przy zrzucie spadochronowym nie tknęły tego, w co gracie.

---

## Kolejność przy nowej modyfikacji

1. **Issue** — problem i dowód
2. **Rozpoznanie** — `grep` po prawdziwych plikach gry, nigdy składnia z głowy
3. **Spec w issue** — pliki, wartości, sposób weryfikacji
4. **Implementacja** — na gałęzi, nie na `main`
5. **`perl test/preflight.pl`** — musi przejść
6. **Test w grze** — jedna zmienna naraz
7. **Log** — zgrać przed ponownym uruchomieniem, bo się kasuje
8. **Merge + zamknięcie issue** z wynikiem weryfikacji
