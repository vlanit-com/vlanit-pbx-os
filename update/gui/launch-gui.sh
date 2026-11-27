#!/usr/bin/env bash
# Запуск vlanit-update GUI: HTTP + netsurf-fb (issue #58 / #60).
set -Eeuo pipefail

UPDATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_NSFB=""
for _cand in \
    "${UPDATE_DIR}/../../installer/lib/netsurf-fb.sh" \
    /opt/vlanit/lib/netsurf-fb.sh \
    /opt/vlanit/installer/lib/netsurf-fb.sh
do
    if [ -f "$_cand" ]; then _NSFB="$_cand"; break; fi
done
[ -n "$_NSFB" ] || { echo "vlanit-update-gui: нет netsurf-fb.sh" >&2; exit 2; }
# shellcheck disable=SC1090
. "$_NSFB"

export VLANIT_UPDATE_STATIC="${VLANIT_UPDATE_STATIC:-$UPDATE_DIR/static}"
export VLANIT_UPDATE_PORT="${VLANIT_UPDATE_PORT:-8767}"
export VLANIT_UPDATE_DONE="${VLANIT_UPDATE_DONE:-/run/vlanit/update-gui-done}"
# пакет из argv (handoff из doctor) или пусто → сканирование USB в server
export VLANIT_UPDATE_PKG="${VLANIT_UPDATE_PKG:-${1:-}}"
RUN_DIR="$(dirname "$VLANIT_UPDATE_DONE")"
export VLANIT_GUI_LOG_DIR="$RUN_DIR"
mkdir -p "$RUN_DIR" "$VLANIT_UPDATE_STATIC"

SURFACE="$(vlanit_fb_pick_surface)" || {
    echo "vlanit-update-gui: нет /dev/fb0 — используйте CLI: vlanit-update" >&2
    echo "  (для стенда: VLANIT_FB_SURFACE=sdl)" >&2
    exit 2
}

if ! command -v netsurf-fb >/dev/null 2>&1; then
    echo "vlanit-update-gui: netsurf-fb не найден — CLI: vlanit-update" >&2
    exit 2
fi

rm -f "$VLANIT_UPDATE_DONE"
python3 "$UPDATE_DIR/server.py" &
SRV_PID=$!
NS_PID=""
cleanup() {
    kill "$NS_PID" 2>/dev/null || true
    kill "$SRV_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 50); do
    if python3 -c "import socket;s=socket.socket();s.settimeout(0.2);s.connect(('127.0.0.1',$VLANIT_UPDATE_PORT))" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

URL="http://127.0.0.1:${VLANIT_UPDATE_PORT}/"
if ! vlanit_fb_serve_browser "$URL" "$SURFACE" "$SRV_PID" "$VLANIT_UPDATE_DONE"; then
    echo "vlanit-update-gui: netsurf-fb ($SURFACE) упал — CLI: vlanit-update" >&2
    exit 2
fi
NS_PID="${VLANIT_FB_LAST_NS_PID:-}"

kill "$NS_PID" 2>/dev/null || true
wait "$NS_PID" 2>/dev/null || true
kill "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true
trap - EXIT
exit 0
