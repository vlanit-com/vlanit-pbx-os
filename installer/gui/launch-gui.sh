#!/usr/bin/env bash
# Запуск HTML-UI: HTTP + netsurf-fb. Конфиг → /run/vlanit/install-config.json.
set -Eeuo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/netsurf-fb.sh
. "$INSTALLER_DIR/lib/netsurf-fb.sh"
export INSTALLER_DIR
export VLANIT_GUI_STATIC="$INSTALLER_DIR/gui/static"
export VLANIT_GUI_PORT="${VLANIT_GUI_PORT:-8765}"
export VLANIT_GUI_MODE="${VLANIT_GUI_MODE:-collect}"
RUN_DIR=/run/vlanit
mkdir -p "$RUN_DIR" "$VLANIT_GUI_STATIC"

# логотип PNG из SVG (если есть cairosvg/PIL в live — опционально)
if [ ! -f "$VLANIT_GUI_STATIC/logo.png" ] && [ -f /usr/share/vlanit/branding/vlanit-logo-on-dark.svg ]; then
    python3 - <<'PY' 2>/dev/null || true
import os
from pathlib import Path
src = Path("/usr/share/vlanit/branding/vlanit-logo-on-dark.svg")
dst = Path(os.environ["VLANIT_GUI_STATIC"]) / "logo.png"
try:
    import cairosvg
    cairosvg.svg2png(url=str(src), write_to=str(dst), output_width=320)
except Exception:
    pass
PY
fi

SURFACE="$(vlanit_fb_pick_surface)" || {
    echo "vlanit-gui: нет /dev/fb0 и VLANIT_FB_SURFACE — fallback TUI/dialog" >&2
    exit 1
}

rm -f "$RUN_DIR/gui-done"
python3 "$INSTALLER_DIR/gui/server.py" &
SRV_PID=$!
NS_PID=""
cleanup() {
    kill "$NS_PID" 2>/dev/null || true
    kill "$SRV_PID" 2>/dev/null || true
}
trap cleanup EXIT

# ждём порт
for _ in $(seq 1 50); do
    if python3 -c "import socket;s=socket.socket();s.settimeout(0.2);s.connect(('127.0.0.1',$VLANIT_GUI_PORT))" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

URL="http://127.0.0.1:${VLANIT_GUI_PORT}/"
NS_PID="$(vlanit_fb_start_netsurf "$URL" "$SURFACE")"

if ! vlanit_fb_wait_done "$SRV_PID" "$NS_PID" "$RUN_DIR/gui-done"; then
    echo "vlanit-gui: netsurf-fb ($SURFACE) не стартовал/упал — fallback" >&2
    exit 1
fi

kill "$NS_PID" 2>/dev/null || true
wait "$NS_PID" 2>/dev/null || true
kill "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true
trap - EXIT

[ -f "$RUN_DIR/install-config.json" ] || exit 1
exit 0
