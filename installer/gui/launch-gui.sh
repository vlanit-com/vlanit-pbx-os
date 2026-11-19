#!/usr/bin/env bash
# Запуск HTML-UI: HTTP + netsurf-fb. Конфиг → /run/vlanit/install-config.json.
set -Eeuo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

rm -f "$RUN_DIR/gui-done"
python3 "$INSTALLER_DIR/gui/server.py" &
SRV_PID=$!
cleanup() { kill "$SRV_PID" 2>/dev/null || true; }
trap cleanup EXIT

# ждём порт
for _ in $(seq 1 50); do
    if python3 -c "import socket;s=socket.socket();s.settimeout(0.2);s.connect(('127.0.0.1',$VLANIT_GUI_PORT))" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

URL="http://127.0.0.1:${VLANIT_GUI_PORT}/"
SURFACE="${VLANIT_FB_SURFACE:-}"
if [ -z "$SURFACE" ]; then
    if [ -c /dev/fb0 ]; then SURFACE=linux; else SURFACE=sdl; fi
fi

if [ "$SURFACE" = "linux" ]; then
    netsurf-fb -f linux "$URL" &
else
    netsurf-fb -f sdl -w 1024 -h 768 "$URL" &
fi
NS_PID=$!

# ждём gui-done (ok) или смерть сервера
while kill -0 "$SRV_PID" 2>/dev/null; do
    if [ -f "$RUN_DIR/gui-done" ]; then
        break
    fi
    sleep 0.3
done

kill "$NS_PID" 2>/dev/null || true
wait "$NS_PID" 2>/dev/null || true
kill "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true
trap - EXIT

[ -f "$RUN_DIR/install-config.json" ] || exit 1
exit 0
