#!/usr/bin/env bash
# Запуск doctor GUI: HTTP + netsurf-fb (issue #56).
set -Eeuo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VLANIT_DOCTOR_STATIC="${VLANIT_DOCTOR_STATIC:-$DOCTOR_DIR/static}"
export VLANIT_DOCTOR_PORT="${VLANIT_DOCTOR_PORT:-8766}"
export VLANIT_DOCTOR_DONE="${VLANIT_DOCTOR_DONE:-/run/vlanit/doctor-gui-done}"
RUN_DIR="$(dirname "$VLANIT_DOCTOR_DONE")"
mkdir -p "$RUN_DIR" "$VLANIT_DOCTOR_STATIC"

SURFACE="${VLANIT_FB_SURFACE:-}"
if [ -z "$SURFACE" ]; then
    if [ -c /dev/fb0 ]; then
        SURFACE=linux
    else
        echo "vlanit-doctor-gui: нет /dev/fb0 — используйте CLI: vlanit-doctor" >&2
        echo "  (для стенда: VLANIT_FB_SURFACE=sdl)" >&2
        exit 2
    fi
fi

if ! command -v netsurf-fb >/dev/null 2>&1; then
    echo "vlanit-doctor-gui: netsurf-fb не найден — CLI: vlanit-doctor" >&2
    exit 2
fi

rm -f "$VLANIT_DOCTOR_DONE"
python3 "$DOCTOR_DIR/server.py" &
SRV_PID=$!
cleanup() { kill "$SRV_PID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 50); do
    if python3 -c "import socket;s=socket.socket();s.settimeout(0.2);s.connect(('127.0.0.1',$VLANIT_DOCTOR_PORT))" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

URL="http://127.0.0.1:${VLANIT_DOCTOR_PORT}/"
if [ "$SURFACE" = "linux" ]; then
    netsurf-fb -f linux "$URL" &
else
    netsurf-fb -f sdl -w 1024 -h 768 "$URL" &
fi
NS_PID=$!

while kill -0 "$SRV_PID" 2>/dev/null; do
    if [ -f "$VLANIT_DOCTOR_DONE" ]; then
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
