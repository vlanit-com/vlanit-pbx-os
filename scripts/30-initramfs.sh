#!/usr/bin/env bash
# scripts/30-initramfs.sh — ядро + initramfs для Live-загрузки.
# Выполняется внутри build-контейнера от root.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS="$BUILD_DIR/rootfs/live"
STAGING="$BUILD_DIR/iso-staging"
mkdir -p "$STAGING/live"

log() { printf '[initramfs] %s\n' "$*"; }

KERNEL_VERSION="$(basename "$(ls -d "$ROOTFS"/lib/modules/* | head -1)")"
log "ядро: $KERNEL_VERSION"

# синхронизация актуальных live-файлов (hook, init) в rootfs
install -D -m 0755 "$PROJECT_ROOT/live/vlanit-init" "$ROOTFS/opt/vlanit/vlanit-init"
install -D -m 0755 "$PROJECT_ROOT/live/initramfs-hook-vlanit-live" \
    "$ROOTFS/etc/initramfs-tools/hooks/vlanit-live"
# полная синхронизация installer (GUI/Cursive/libs) — cp, не частичный список
rm -rf "$ROOTFS/opt/vlanit/installer"
cp -a "$PROJECT_ROOT/installer/." "$ROOTFS/opt/vlanit/installer/"
rm -rf "$ROOTFS/opt/vlanit/installer/tui-cursive/target"
chown -R root:root "$ROOTFS/opt/vlanit/installer"
chmod 0755 "$ROOTFS/opt/vlanit/installer/vlanit-installer"
chmod 0755 "$ROOTFS/opt/vlanit/installer/bin/"* 2>/dev/null || true
chmod 0755 "$ROOTFS/opt/vlanit/installer/gui/"*.sh 2>/dev/null || true
chmod 0755 "$ROOTFS/opt/vlanit/installer/gui/server.py"

log "сборка initramfs (chroot live rootfs)"
chroot "$ROOTFS" sh -c "
    export DEBIAN_FRONTEND=noninteractive
    mkinitramfs -o /boot/initrd-vlanit '$KERNEL_VERSION'
"

VMLINUZ="$ROOTFS/boot/vmlinuz-$KERNEL_VERSION"
INITRD="$ROOTFS/boot/initrd-vlanit"
[ -f "$VMLINUZ" ] || { echo "нет $VMLINUZ"; exit 1; }
[ -f "$INITRD" ] || { echo "нет $INITRD"; exit 1; }

cp "$VMLINUZ" "$STAGING/live/vmlinuz"
cp "$INITRD"  "$STAGING/live/initrd"
log "готово: live/vmlinuz ($(du -h "$STAGING/live/vmlinuz" | cut -f1)), live/initrd ($(du -h "$STAGING/live/initrd" | cut -f1))"
