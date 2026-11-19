#!/usr/bin/env bash
# scripts/slim-rootfs.sh — вычистить лишний вес из golden/live rootfs (#29/#30/#32).
# Вызывать после установки пакетов и фирменного Plymouth.
#   $1 — путь к rootfs
set -Eeuo pipefail

ROOTFS="${1:?usage: slim-rootfs.sh <rootfs>}"
log() { printf '[slim-rootfs] %s\n' "$*"; }

[ -d "$ROOTFS" ] || { echo "нет rootfs: $ROOTFS" >&2; exit 1; }

# --- #29 locale: только en* и ru* ---
if [ -d "$ROOTFS/usr/share/locale" ]; then
    find "$ROOTFS/usr/share/locale" -mindepth 1 -maxdepth 1 \
        ! -name 'en*' ! -name 'ru*' -exec rm -rf {} +
    log "locale: оставлены en*/ru*"
fi

# --- #30 doc + man ---
rm -rf "$ROOTFS/usr/share/doc" "$ROOTFS/usr/share/man"
# часть пакетов кладёт info/lintian — тоже не нужны на appliance
rm -rf "$ROOTFS/usr/share/info" "$ROOTFS/usr/share/lintian" 2>/dev/null || true
log "удалены share/doc, share/man (+info/lintian)"

# --- #32 plymouth: оставить vlanit + text (fallback) ---
PLY="$ROOTFS/usr/share/plymouth/themes"
if [ -d "$PLY" ]; then
    find "$PLY" -mindepth 1 -maxdepth 1 -type d \
        ! -name vlanit ! -name text \
        -exec rm -rf {} +
    # обломки .plymouth вне vlanit/text
    find "$PLY" -maxdepth 1 -type f -name '*.plymouth' ! -name 'default.plymouth' \
        -delete 2>/dev/null || true
    log "plymouth themes: vlanit + text"
fi

# --- #32 consolefonts: только CyrSlav-DejaVu30x16 (+ зависимости имени) ---
CF="$ROOTFS/usr/share/consolefonts"
if [ -d "$CF" ]; then
    # оставить файлы, в имени которых есть CyrSlav-DejaVu30x16
    find "$CF" -type f ! -name '*CyrSlav-DejaVu30x16*' -delete
    # пустые каталоги
    find "$CF" -type d -empty -delete 2>/dev/null || true
    log "consolefonts: CyrSlav-DejaVu30x16"
fi

log "готово"
