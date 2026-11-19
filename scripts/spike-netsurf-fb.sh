#!/usr/bin/env bash
# scripts/spike-netsurf-fb.sh — спайк идеи #12: netsurf-fb на framebuffer.
# Запуск на live/QEMU или на железе флота (root).
# Не ставит пакеты в образ — только проверяет окружение и печатает факт.
set -Eeuo pipefail

echo "=== spike netsurf-fb ==="
echo "date: $(date -Is)"
echo "kernel: $(uname -r)"
echo "fb0: $(test -c /dev/fb0 && echo yes || echo NO)"
if [ -c /dev/fb0 ]; then
    cat /sys/class/graphics/fb0/name 2>/dev/null || true
    cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || true
fi

if ! command -v netsurf-fb >/dev/null 2>&1; then
    echo "netsurf-fb: NOT INSTALLED"
    echo "hint: apt-get install -y netsurf-fb fonts-dejavu-core"
    exit 2
fi
echo "netsurf-fb: $(command -v netsurf-fb)"
dpkg-query -W -f='${Package} ${Version} ${Installed-Size}KiB\n' netsurf-fb netsurf-common 2>/dev/null || true

# Минимальная HTML-страница с кириллицей (формы без JS)
SPIKE_DIR="${SPIKE_DIR:-/tmp/vlanit-netsurf-spike}"
mkdir -p "$SPIKE_DIR"
cat > "$SPIKE_DIR/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<title>VLANit spike</title>
<style>
body{font-family:DejaVu Sans,sans-serif;background:#111;color:#eee;margin:2em}
h1{color:#e6b800}
label{display:block;margin:0.8em 0 0.2em}
input,button{font-size:1.1em;padding:0.3em}
.err{color:#f66}
</style>
</head>
<body>
<h1>VLANit — спайк netsurf-fb</h1>
<p>Кириллица: проверка оборудования, диск, сеть.</p>
<form method="get" action="index.html">
<label>Hostname <input name="hostname" value="vlanit-pbx"></label>
<label>Пароль <input type="password" name="pass" value=""></label>
<button type="submit">Далее</button>
</form>
</body>
</html>
EOF

URL="file://$SPIKE_DIR/index.html"
echo "URL: $URL"
echo "launch: netsurf-fb -f linux '$URL'  (Ctrl-Q / Esc to quit)"
echo "alt:    netsurf-fb -f sdl -w 1024 -h 768 '$URL'"
if [ "${SPIKE_LAUNCH:-0}" = "1" ]; then
    # linux surface на реальном fb0; sdl — удобнее в QEMU без эксклюзива VT
    if [ -c /dev/fb0 ] && [ "${SPIKE_SURFACE:-linux}" = "linux" ]; then
        exec netsurf-fb -f linux "$URL"
    fi
    exec netsurf-fb -f sdl -w 1024 -h 768 "$URL"
fi
echo "OK: files ready; set SPIKE_LAUNCH=1 to open browser"
