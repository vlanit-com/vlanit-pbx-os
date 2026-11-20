#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCR="$ROOT/scripts/slim-rootfs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/usr/share/locale/"{de,en_US,ru_RU,fr} \
         "$TMP/usr/share/doc/foo" \
         "$TMP/usr/share/man/man1" \
         "$TMP/usr/share/plymouth/themes/"{vlanit,spinner,text,glow,details} \
         "$TMP/usr/share/consolefonts"
touch "$TMP/usr/share/doc/foo/README" \
      "$TMP/usr/share/man/man1/ls.1" \
      "$TMP/usr/share/consolefonts/CyrSlav-DejaVu30x16.psf.gz" \
      "$TMP/usr/share/consolefonts/Lat15-Terminus16.psf.gz" \
      "$TMP/usr/share/plymouth/themes/vlanit/x" \
      "$TMP/usr/share/plymouth/themes/spinner/x" \
      "$TMP/usr/share/plymouth/themes/text/x" \
      "$TMP/usr/share/plymouth/themes/details/x" \
      "$TMP/usr/share/plymouth/themes/glow/x"

bash "$SCR" "$TMP"

[ ! -d "$TMP/usr/share/locale/de" ]
[ ! -d "$TMP/usr/share/locale/fr" ]
[ -d "$TMP/usr/share/locale/en_US" ]
[ -d "$TMP/usr/share/locale/ru_RU" ]
[ ! -e "$TMP/usr/share/doc/foo/README" ]
[ ! -e "$TMP/usr/share/man/man1/ls.1" ]
[ -d "$TMP/usr/share/plymouth/themes/vlanit" ]
[ -d "$TMP/usr/share/plymouth/themes/text" ]
[ -d "$TMP/usr/share/plymouth/themes/details" ]
[ ! -d "$TMP/usr/share/plymouth/themes/spinner" ]
[ ! -d "$TMP/usr/share/plymouth/themes/glow" ]
[ -f "$TMP/usr/share/consolefonts/CyrSlav-DejaVu30x16.psf.gz" ]
[ ! -f "$TMP/usr/share/consolefonts/Lat15-Terminus16.psf.gz" ]

echo "PASS test-slim-rootfs"
