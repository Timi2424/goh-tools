# Panel

Mały panel do codziennej pętli moddowania. WinForms w PowerShellu — zero zależności,
działa na czystym Windowsie.

```
gui\panel.bat
```

## Co umie

**Sprawdz pliki** — `preflight.pl`, werdykt „można testować" albo „nie odpalaj".
**Delta** — ile własnych linii mamy w każdym pliku, względem wersji z paków.
**Snapshot zrodel** — odtwarza `upstream/` po update gry albo moda.
**Wdroz do moda** — kopiuje patch do katalogu moda i od razu uruchamia kontrolę.
**Co jest w modzie** — wypisuje pliki eksperymentalne, których nie ma w patchu.
**Log: podsumowanie** — liczy crashe, nieudane spawny i szum; przy crashu pokazuje stos.
**Log: nasze encje** — `Remap actor_id` i błędy dotyczące naszych rzeczy.
**Zachowaj log** — kopiuje `game.log` do `data/logi/` ze znacznikiem czasu.
**Binarka: info** — nagłówki PE, liczba funkcji i stringów.

Pasek na dole pokazuje, czy gra chodzi. Jeśli chodzi, wdrożenie jest zablokowane —
mody montują się przy starcie procesu, więc zmiany i tak by nie weszły.

## Ścieżki

Panel zakłada standardowy układ:

```
goh-tools\       to repo
goh-hf-patch\    obok, prywatne repo z patchem
```

Jeśli masz inaczej, popraw `$PATCH`, `$MOD`, `$LOG` i `$EXE` na górze `panel.ps1`.
