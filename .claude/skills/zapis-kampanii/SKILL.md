---
name: zapis-kampanii
description: Bezpieczna edycja zapisu dynamicznej kampanii Gates of Hell (.sav = zip z campaign.scn i status) - gwiazdki, punkty badan, kupione ordery, wyposazenie zolnierzy, stan samolotow. Uzyj, gdy test wymaga zmiany zapisu albo gracz prosi o zasoby lub ordery w kampanii.
---

# Edycja zapisu kampanii

Zapisy: `%USERPROFILE%/Documents/My Games/gates of hell/profiles/<id>/campaign/*.sav`.
Plik to ZIP: `campaign.scn` (armia, kupione jednostki z PELNYM stanem) i
`status` (`mp`/`sp`/`ap`/`rp` - zasoby, `unlockedResearch`). Oba CRLF.

## Zasady

- **Gra zamknieta** - gra nadpisuje zapis przy wyjsciu z bitwy i kampanii.
- **Kopia przed edycja tylko poza katalogami gry** (np. scratchpad sesji),
  nigdy obok pliku: kopie w katalogach gry wracaly ze Steam Cloud i psuly gre.
- Edycja perlem w rozpakowanej kopii, pakowanie `perl <goh-tools>/test/mkpak.pl
  <katalog> <wyjscie.sav>` (zip bez kompresji - gra go przyjmuje), weryfikacja
  `unzip -l` i grep.
- Edycja zapisu zmienia warunki testu - odnotuj ja w dzienniku projektu (co,
  dlaczego, gdzie kopia), inaczej wyniki sa nieporownywalne.

## Co gdzie siedzi

- Kupione ordery/jednostki: `{CampaignSquads {"<jednostka>" "<slot>" ids...}}`;
  slot `"stage_specials"` = wybrany do misji, `""` = rezerwa.
- **Zapis trzyma wyposazenie kazdego zolnierza**
  (`{item "..." {cell x y}{user "head"}}`). Zmiana breeda dziala tylko na NOWE
  zakupy - juz kupionych trzeba poprawic w zapisie.
- **Samolot kupionego orderu**: `{Chassis "airborne" {Altitude N}}` =
  `MaxAirborneAltitude` z jego .def w chwili zapisu.
- Kazda encja z zapisu musi istniec w grze - `can't spawn entity X` przy
  wczytaniu konczy sie crashem. Usunieta encja wymaga zaslepki .def.

## Przepis

```bash
S=<katalog roboczy poza gra>; D="<katalog campaign>"; F="<nazwa>.sav"
mkdir -p $S/kopia-<powod> && cp "$D/$F" $S/kopia-<powod>/
rm -rf $S/sav && mkdir -p $S/sav/in && cd $S/sav/in && unzip -q "$D/$F"
perl -pi -e 's/<stare>/<nowe>/g' campaign.scn     # zachowuje CRLF
grep -c '<nowe>' campaign.scn
perl <goh-tools>/test/mkpak.pl $S/sav/in $S/sav/out.sav
unzip -l $S/sav/out.sav && cp $S/sav/out.sav "$D/$F"
```
