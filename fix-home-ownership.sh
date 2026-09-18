#!/bin/bash
# Kors av upgrade-fedora-wsl.ps1 INUTI den nyimporterade distrot efter att
# /home aterstallts fran backup. Fixar agarskap per toppniva-katalog i
# /home mot den NYA imagens /etc/passwd - robust aven om UID/GID skulle
# skilja sig mellan den gamla och nya imagen.
set -euo pipefail

shopt -s nullglob
for dir in /home/*/; do
  user="$(basename "$dir")"
  if id "$user" >/dev/null 2>&1; then
    uid="$(id -u "$user")"
    gid="$(id -g "$user")"
    chown -R "${uid}:${gid}" "$dir"
    echo "OK: $dir -> ${user} (${uid}:${gid})"
  else
    echo "VARNING: ingen matchande anvandare for $dir - agarskap ej andrat" >&2
  fi
done
