#!/usr/bin/env bash
# Запуск vlanit-update GUI: HTTP + netsurf-fb (issue #58).
set -Eeuo pipefail

UPDATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VLANIT_UPDATE_STATIC="${VLANIT_UPDATE_STATIC:-$UPDATE_DIR/static}"
export VLANIT_UPDATE_PORT="${VLANIT_UPDATE_PORT:-8767}"
export VLANIT_UPDATE_DONE="${VLANIT_UPDATE_DONE:-/run/vlanit/update-gui-done}"
# пакет из argv (handoff из doctor) или пусто → сканирование USB в server
export VLANIT_UPDATE_PKG="${VLANIT_UPDATE_PKG:-${1:-}}"
RUN_DIR="$(dirname "$VLANIT_UPDATE_DONE")"
mkdir -p "$RUN_DIR" "$VLANIT_UPDATE_STATIC"

SURFACE="${VLANIT_FB_SURFACE:-}"
if [ -z "$SURFACE" ]; then
    if [ -c /dev/fb0 ]; then
        SURFACE=linux
    else
        echo "vlanit-update-gui: нет /dev/fb0 — используйте CLI: vlanit-update" >&2
        echo "  (для стенда: VLANIT_FB_SURFACE=sdl)" >&2
        exit 2
    fi
fi

if ! command -v netsurf-fb >/dev/null 2>&1; then
    echo "vlanit-update-gui: netsurf-fb не найден — CLI: vlanit-update" >&2
    exit 2
fi

rm -f "$VLANIT_UPDATE_DONE"
python3 "$UPDATE_DIR/server.py" &
SRV_PID=$!
cleanup() { kill "$SRV_PID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 50); do
    if python3 -c "import socket;s=socket.socket();s.settimeout(0.2);s.connect(('127.0.0.1',$VLANIT_UPDATE_PORT))" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

URL="http://127.0.0.1:${VLANIT_UPDATE_PORT}/"
if [ "$SURFACE" = "linux" ]; then
    netsurf-fb -f linux "$URL" &
else
    netsurf-fb -f sdl -w 1024 -h 768 "$URL" &
fi
NS_PID=$!

while kill -0 "$SRV_PID" 2>/dev/null; do
    if [ -f "$VLANIT_UPDATE_DONE" ]; then
        break
    fi
    sleep 0.3
done

kill "$NS_PID" 2>/dev/null || true
wait "$NS_PID" 2>/dev/null || true
kill "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true
trap - EXIT
exit 0
