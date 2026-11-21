#!/usr/bin/env bash
# scripts/shot-update-gui.sh — скрины OTA GUI + doctor с кнопкой (#58).
# Выход: docs/update-gui/shots/*.png и docs/doctor-gui/shots/05|06-*.png
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_UPD="${SHOT_OUT_UPDATE:-$PROJECT_ROOT/docs/update-gui/shots}"
OUT_DOC="${SHOT_OUT_DOCTOR:-$PROJECT_ROOT/docs/doctor-gui/shots}"
PORT_U="${VLANIT_UPDATE_PORT:-18767}"
PORT_D="${VLANIT_DOCTOR_PORT:-18766}"
WORKDIR="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$WORKDIR"' EXIT

mkdir -p "$OUT_UPD" "$OUT_DOC" "$WORKDIR"

PKG="$WORKDIR/vlanit-update-2026.9.5-amd64.tar"
dd if=/dev/zero of="$PKG" bs=1M count=2 status=none
touch "$PKG.asc"

cat >"$WORKDIR/fake-update-cli" <<'EOF'
#!/usr/bin/env bash
echo "[$(date +%H:%M:%S)] пакет: $1"
echo "[$(date +%H:%M:%S)] создание снапшота pre-update"
sleep 0.4
echo "[$(date +%H:%M:%S)] импорт образа АТС"
sleep 0.3
echo "[$(date +%H:%M:%S)] перезапуск контейнера АТС"
sleep 0.2
echo "OK: обновление АТС завершено. Откат при необходимости: vlanit-rollback"
exit 0
EOF
chmod +x "$WORKDIR/fake-update-cli"

cat >"$WORKDIR/fake-update" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--gui" ]; then
  echo "fake gui start"
  sleep 60
  exit 0
fi
exec "$WORKDIR/fake-update-cli" "\$@"
EOF
chmod +x "$WORKDIR/fake-update"

cat >"$WORKDIR/fake-doctor.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{
  "host": "vlanit-pbx-001",
  "result": "WARN",
  "checks": [
    {"group":"system","check":"ntp-synchronized","status":"WARN","desc":"часы синхронизированы с NTP","hint":"timedatectl status"},
    {"group":"updates","check":"ota-package-present","status":"OK","desc":"на USB есть пакет vlanit-update","hint":"vlanit-update --gui"},
    {"group":"updates","check":"mikopbx-image-pin","status":"OK","desc":"quadlet Image= совпадает с pin","hint":""},
    {"group":"updates","check":"apt-upgradable","status":"WARN","desc":"нет ожидающих security-обновлений","hint":"unattended-upgrades"},
    {"group":"mikopbx","check":"mikopbx-webui","status":"OK","desc":"веб-интерфейс отвечает","hint":""}
  ]
}
JSON
EOF
chmod +x "$WORKDIR/fake-doctor.sh"

export VLANIT_OTA_PACKAGES="$PKG"
export VLANIT_UPDATE_BIN="$WORKDIR/fake-update-cli"
export VLANIT_UPDATE_PORT="$PORT_U"
export VLANIT_UPDATE_STATIC="$WORKDIR/update-static"
export VLANIT_UPDATE_DONE="$WORKDIR/update-gui-done"
export VLANIT_UPDATE_STATE="$WORKDIR/update-state"
export VLANIT_UPDATE_PKG=""
mkdir -p "$VLANIT_UPDATE_STATIC"
cp -a "$PROJECT_ROOT/update/gui/static/." "$VLANIT_UPDATE_STATIC/"
if [ -f "$PROJECT_ROOT/installer/branding/default/logo.png" ]; then
  cp -f "$PROJECT_ROOT/installer/branding/default/logo.png" "$VLANIT_UPDATE_STATIC/logo.png"
fi

python3 "$PROJECT_ROOT/update/gui/server.py" &

export VLANIT_DOCTOR_CMD="$WORKDIR/fake-doctor.sh"
export VLANIT_DOCTOR_PORT="$PORT_D"
export VLANIT_DOCTOR_STATIC="$WORKDIR/doctor-static"
mkdir -p "$VLANIT_DOCTOR_STATIC"
cp -a "$PROJECT_ROOT/doctor/gui/static/." "$VLANIT_DOCTOR_STATIC/"
if [ -f "$PROJECT_ROOT/installer/branding/default/logo.png" ]; then
  cp -f "$PROJECT_ROOT/installer/branding/default/logo.png" "$VLANIT_DOCTOR_STATIC/logo.png"
fi
export VLANIT_DOCTOR_DONE="$WORKDIR/doctor-gui-done"
export VLANIT_DOCTOR_HANDOFF="$WORKDIR/doctor-update-handoff"
export VLANIT_UPDATE_BIN="$WORKDIR/fake-update"

python3 "$PROJECT_ROOT/doctor/gui/server.py" &

for port in "$PORT_U" "$PORT_D"; do
  for _ in $(seq 1 50); do
    python3 -c "import socket;s=socket.socket();s.settimeout(0.2);s.connect(('127.0.0.1',$port))" 2>/dev/null && break
    sleep 0.05
  done
done

python3 - "$PORT_U" "$PORT_D" "$OUT_UPD" "$OUT_DOC" "$PKG" <<'PY'
import sys, time, urllib.parse
from pathlib import Path
from playwright.sync_api import sync_playwright

port_u, port_d = int(sys.argv[1]), int(sys.argv[2])
out_u, out_d = Path(sys.argv[3]), Path(sys.argv[4])
pkg = sys.argv[5]
base_u = f"http://127.0.0.1:{port_u}"
base_d = f"http://127.0.0.1:{port_d}"
qpkg = urllib.parse.quote(pkg)

with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome")
    page = browser.new_page(viewport={"width": 1024, "height": 768})

    page.goto(base_u + "/")
    page.wait_for_selector("text=Выберите пакет")
    page.screenshot(path=str(out_u / "01-package.png"), full_page=True)

    page.goto(base_u + f"/confirm?pkg={qpkg}")
    page.wait_for_selector("text=YES")
    page.screenshot(path=str(out_u / "02-confirm.png"), full_page=True)

    page.goto(base_u + f"/apply?pkg={qpkg}&yes=1")
    time.sleep(0.25)
    page.screenshot(path=str(out_u / "03-progress.png"), full_page=True)

    for _ in range(40):
        page.goto(base_u + "/status")
        html = page.content()
        if "Обновление АТС завершено" in html:
            break
        time.sleep(0.25)
    page.screenshot(path=str(out_u / "04-done.png"), full_page=True)

    page.goto(base_d + "/")
    for _ in range(40):
        if "Обновить АТС" in page.content():
            break
        time.sleep(0.15)
        page.goto(base_d + "/")
    page.screenshot(path=str(out_d / "05-overview-update.png"), full_page=True)

    page.goto(base_d + f"/action/update?pkg={qpkg}")
    time.sleep(1.8)
    page.screenshot(path=str(out_d / "06-handoff.png"), full_page=True)

    browser.close()

print("OK", sorted(p.name for p in out_u.glob("*.png")))
PY
