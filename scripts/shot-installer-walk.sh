#!/usr/bin/env bash
# scripts/shot-installer-walk.sh — интерактивный проход TUI-мастера в QEMU
# со screendump в build/release-shots/<version>/. Без autoinstall.
# Виджеты: msgbox, menu, yesno, inputbox, passwordbox, gauge (+ зеркало).
set -Eeuo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="$(sed -n 's/^  version: //p' config/build.yaml | head -1 | tr -d '"')"
# абсолютный путь: usb-storage у QEMU открывает ISO read-write —
# root-owned 644 из make iso даёт Permission denied для пользователя.
ISO="${ISO:-$PROJECT_ROOT/dist/VLANit-PBX-$VERSION-amd64.iso}"
OUT="build/release-shots/$VERSION"
TESTDIR="build/qemu/walk-theme_$$"
OVMF_DIR="tools/root/usr/share/OVMF"
OVMF_CODE="$OVMF_DIR/OVMF_CODE_4M.fd"
OVMF_VARS_SRC="$OVMF_DIR/OVMF_VARS_4M.fd"

[ -f "$ISO" ] || { echo "Нет $ISO — make iso"; exit 1; }
[ -r "$ISO" ] || { echo "ISO не читается: $ISO"; exit 1; }
[ -f "$OVMF_CODE" ] || { echo "Нет OVMF"; exit 1; }
mkdir -p "$OUT" "$TESTDIR"
rm -f "$OUT"/*.png
OUT="$(realpath "$OUT")"
TESTDIR="$(realpath "$TESTDIR")"

MON="$TESTDIR/vm.monitor"
PIDF="$TESTDIR/vm.pid"
VARS="$TESTDIR/OVMF_VARS.fd"
DISK1="$TESTDIR/d1.qcow2"
DISK2="$TESTDIR/d2.qcow2"
cp "$OVMF_VARS_SRC" "$VARS"
qemu-img create -f qcow2 "$DISK1" 40G >/dev/null
qemu-img create -f qcow2 "$DISK2" 40G >/dev/null

mon() {
    local i=0
    while [ ! -S "$MON" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
    python3 -c '
import socket,sys,time
s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
s.sendall((sys.argv[2]+"\n").encode())
time.sleep(0.2)
' "$MON" "$1"
}
sendkeys() {
    local k
    for k in $1; do
        mon "sendkey $k"
        sleep 0.08
    done
}
shot() {
    local name="$1"
    local ppm="$TESTDIR/$name.ppm"
    mon "screendump $ppm"
    local j=0
    while [ ! -f "$ppm" ] && [ "$j" -lt 30 ]; do sleep 0.2; j=$((j+1)); done
    [ -f "$ppm" ] || { echo "WARN: нет $ppm"; return 1; }
    python3 "$PROJECT_ROOT/scripts/ppm2png.py" "$ppm" "$OUT/$name.png" >/dev/null
    echo "shot $OUT/$name.png"
}

cleanup() { [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null || true; }
trap cleanup EXIT

qemu-system-x86_64 \
    -name vlanit-walk-theme \
    -machine q35 -enable-kvm -m 4096 -smp 2 \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=$VARS" \
    -drive "file=$DISK1,if=virtio,format=qcow2" \
    -drive "file=$DISK2,if=virtio,format=qcow2" \
    -device qemu-xhci,id=xhci \
    -drive "file=$ISO,if=none,id=instiso,format=raw" \
    -device "usb-storage,drive=instiso" \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -serial "file:$TESTDIR/serial.log" \
    -monitor "unix:$MON,server,nowait" \
    -display none -pidfile "$PIDF" -daemonize

sleep 4; shot "01-grub-menu"
sleep 40; shot "02-hardware"
sendkeys "ret"; sleep 2

shot "03-disk-select"
sendkeys "ret"; sleep 1.5
shot "03b-disk-confirm"
sendkeys "ret"; sleep 2

sendkeys "down"; sleep 0.5                  # зеркало (до кадра)
shot "04-disk-mode"
sendkeys "ret"; sleep 2
shot "04b-mirror-disk2"
sendkeys "ret"; sleep 1.5                   # второй диск = vdb
shot "05-mirror-confirm"
sendkeys "ret"; sleep 2

shot "06-network"
sendkeys "ret"; sleep 1.5
sendkeys "ret"; sleep 2                     # DHCP

shot "07-system-params"                     # hostname
sendkeys "ret"; sleep 1.5
sendkeys "ret"; sleep 1.5                   # admin user
# пароль ≥8
sendkeys "p a s s w 0 r d"; sendkeys "ret"; sleep 1.5
sendkeys "ret"; sleep 1.5                   # SSH вкл
sendkeys "ret"; sleep 1.5                   # TZ default
sendkeys "down"; sendkeys "ret"; sleep 1.5  # WG выкл
sendkeys "ret"; sleep 1.5                   # PBX name
sendkeys "ret"; sleep 2                     # PBX pass empty

shot "08-summary"
sendkeys "ret"; sleep 4

shot "09-gauge-early"
sleep 40; shot "10-gauge-mid"
# зеркало дольше — ждём финал до ~25 мин
for i in $(seq 1 40); do
    sleep 30
    if grep -qE 'VLANIT_INSTALL_DONE|Установка завершена' "$TESTDIR/serial.log" 2>/dev/null; then
        break
    fi
    if (( i % 4 == 0 )); then shot "11-gauge-bootloader" || true; fi
done
sleep 3
shot "12-finish" || true

echo "готово: $OUT ($(ls -1 "$OUT"/*.png 2>/dev/null | wc -l) png)"
ls -1 "$OUT"
