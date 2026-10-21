#!/bin/bash
# instaluj-skille.sh - kopiuje skille Claude Code z repo do ~/.claude/skills
#
#   bash instaluj-skille.sh
#
# Repo jest zrodlem prawdy (wersjonowane, wspolne dla projektow); ~/.claude/skills
# to kopia, zeby skille dzialaly w sesji otwartej w dowolnym katalogu (np. w
# katalogu gry albo w repo projektu). Projekty maja wlasne instalatory, ktore
# wolaja ten skrypt - patrz README, sekcja "Claude Code".
#
# Straznik (hooks/straznik.pl) NIE jest tu instalowany: hook podpina projekt
# w swoich ustawieniach, z wlasna konfiguracja (straznik.conf).

set -e
export PATH=/usr/bin:/bin:$PATH
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CEL="$HOME/.claude/skills"
mkdir -p "$CEL"
for d in "$REPO"/.claude/skills/*/; do
    n=$(basename "$d")
    rm -rf "$CEL/$n" && cp -r "$d" "$CEL/$n"
    echo "skill: $n -> $CEL/$n"
done
