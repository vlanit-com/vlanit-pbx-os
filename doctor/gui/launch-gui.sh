#!/usr/bin/env bash
# Запуск doctor GUI: HTTP + netsurf-fb (issue #56 / #60).
set -Eeuo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_NSFB=""
for _cand in \
    "${DOCTOR_DIR}/../../installer/lib/netsurf-fb.sh" \
    /opt/vlanit/lib/netsurf-fb.sh \
    /opt/vlanit/installer/lib/netsurf-fb.sh
do
    if [ -f "$_cand" ]; then _NSFB="$_cand"; break; fi
done
[ -n "$_NSFB" ] || { echo "vlanit-doctor-gui: нет netsurf-fb.sh" >&2; exit 2; }
# shellcheck disable=SC1090
. "$_NSFB"

export VLANIT_DOCTOR_STATIC="${VLANIT_DOCTOR_STATIC:-$DOCTOR_DIR/static}"
export VLANIT_DOCTOR_PORT="${VLANIT_DOCTOR_PORT:-8766}"
export VLANIT_DOCTOR_DONE="${VLANIT_DOCTOR_DONE:-/run/vlanit/doctor-gui-done}"
RUN_DIR="$(dirname "$VLANIT_DOCTOR_DONE")"
export VLANIT_GUI_LOG_DIR="$RUN_DIR"
mkdir -p "$RUN_DIR" "$VLANIT_DOCTOR_STATIC"

SURFACE="$(vlanit_fb_pick_surface)" || {
    echo "vlanit-doctor-gui: нет /dev/fb0 — используйте CLI: vlanit-doctor" >&2
    echo "  (для стенда: VLANIT_FB_SURFACE=sdl)" >&2
    exit 2
}

if ! command -v netsurf-fb >/dev/null 2>&1; then
    echo "vlanit-doctor-gui: netsurf-fb не найден — CLI: vlanit-doctor" >&2
    exit 2
fi

rm -f "$VLANIT_DOCTOR_DONE"
python3 "$DOCTOR_DIR/server.py" &
SRV_PID=$!
NS_PID=""
cleanup() {
    kill "$NS_PID" 2>/dev/null || true
    kill "$SRV_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 50); do
    if python3 -c "import socket;s=socket.socket();s.settimeout(0.2);s.connect(('127.0.0.1',$VLANIT_DOCTOR_PORT))" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

URL="http://127.0.0.1:${VLANIT_DOCTOR_PORT}/"
if ! vlanit_fb_serve_browser "$URL" "$SURFACE" "$SRV_PID" "$VLANIT_DOCTOR_DONE"; then
    echo "vlanit-doctor-gui: netsurf-fb ($SURFACE) упал — CLI: vlanit-doctor" >&2
    exit 2
fi
NS_PID="${VLANIT_FB_LAST_NS_PID:-}"

kill "$NS_PID" 2>/dev/null || true
wait "$NS_PID" 2>/dev/null || true
kill "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true
trap - EXIT
exit 0
