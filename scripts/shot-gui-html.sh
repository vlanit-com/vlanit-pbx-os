#!/usr/bin/env bash
# scripts/shot-gui-html.sh — скрины HTML-мастера (mock probe, без ISO).
# Выход: build/release-shots/gui-installer/*.png
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SHOT_OUT:-$PROJECT_ROOT/build/release-shots/gui-installer}"
PORT="${VLANIT_GUI_PORT:-8765}"
WORKDIR="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$WORKDIR"' EXIT

mkdir -p "$OUT" "$WORKDIR/bin" "$WORKDIR/gui"
cp -a "$PROJECT_ROOT/installer/gui/." "$WORKDIR/gui/"
cp -a "$PROJECT_ROOT/installer/screens.yaml" "$WORKDIR/screens.yaml"
cp -a "$PROJECT_ROOT/installer/branding" "$WORKDIR/branding"
# mock probe
cat > "$WORKDIR/bin/vlanit-probe" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
hardware)
  printf '%s\n' '{"cpu":"Intel(R) Core(TM) i5-10400 CPU @ 2.90GHz","cores":6,"ram_mb":8192,"boot_mode":"UEFI","interfaces":["enp1s0","enp2s0"],"warnings":""}'
  ;;
disks)
  printf '%s\n' '{"warn_disk_gb":64,"disks":[{"dev":"/dev/sda","size_bytes":512110190592,"size_gib":476.9,"tran":"sata","model":"Samsung SSD 870"},{"dev":"/dev/sdb","size_bytes":512110190592,"size_gib":476.9,"tran":"sata","model":"Samsung SSD 870"}]}'
  ;;
ifaces)
  printf '%s\n' '{"interfaces":[{"name":"enp1s0","mac":"52:54:00:12:34:56"},{"name":"enp2s0","mac":"52:54:00:65:43:21"}]}'
  ;;
version)
  printf '%s\n' '{"version":"1.4.0"}'
  ;;
*) echo "usage: $0 hardware|disks|ifaces|version" >&2; exit 2 ;;
esac
EOF
chmod +x "$WORKDIR/bin/vlanit-probe"

# finish/progress fixtures for late screens
mkdir -p /run/vlanit 2>/dev/null || mkdir -p "$WORKDIR/run"
RUNDIR="${VLANIT_RUN_DIR:-/run/vlanit}"
if [ ! -w "$(dirname "$RUNDIR")" ] 2>/dev/null; then
  RUNDIR="$WORKDIR/run"
fi
mkdir -p "$RUNDIR"
# server hardcodes /run/vlanit — use sudo or patch via bind. Prefer env override.
# Temporary: symlink if possible, else patch copy of server for shot.
if [ "$RUNDIR" != "/run/vlanit" ]; then
  sed -i "s|/run/vlanit|$RUNDIR|g" "$WORKDIR/gui/server.py"
fi

export INSTALLER_DIR="$WORKDIR"
export VLANIT_GUI_STATIC="$WORKDIR/gui/static"
export VLANIT_GUI_PORT="$PORT"
export VLANIT_GUI_MODE=collect

python3 "$WORKDIR/gui/server.py" &
SRV=$!
for _ in $(seq 1 50); do
  python3 -c "import socket;s=socket.socket();s.settimeout(0.2);s.connect(('127.0.0.1',$PORT))" 2>/dev/null && break
  sleep 0.1
done

python3 - "$PORT" "$OUT" <<'PY'
import json, sys, time, urllib.parse, urllib.request
from pathlib import Path

port = int(sys.argv[1])
out = Path(sys.argv[2])
base = f"http://127.0.0.1:{port}"

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("need: pip install playwright && playwright install chromium", file=sys.stderr)
    sys.exit(2)

def get(path="/"):
    with urllib.request.urlopen(base + path) as r:
        return r.read()

def post(form: dict):
    data = urllib.parse.urlencode(form, doseq=True).encode()
    req = urllib.request.Request(base + "/", data=data, method="POST")
    with urllib.request.urlopen(req) as r:
        return r.read()

shots = []

with sync_playwright() as p:
    browser = p.chromium.launch(args=["--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"])
    page = browser.new_page(viewport={"width": 1024, "height": 768})
    page.goto(base + "/")
    page.wait_for_load_state("domcontentloaded")
    page.screenshot(path=str(out / "01-hardware.png"), full_page=True)
    shots.append("01-hardware.png")

    page.click('button[value="next"]')
    page.wait_for_load_state("networkidle")
    page.screenshot(path=str(out / "02-disk.png"), full_page=True)
    shots.append("02-disk.png")

    # кадр RAID (ещё на экране диска), потом выбрать второй диск и Далее
    page.select_option('select[name="mirror_mode"]', "raid1")
    page.select_option('select[name="mirror_disk"]', "/dev/sdb")
    page.screenshot(path=str(out / "02b-disk-raid.png"), full_page=True)
    shots.append("02b-disk-raid.png")

    page.click('button[value="next"]')
    page.wait_for_load_state("networkidle")
    page.screenshot(path=str(out / "03-network.png"), full_page=True)
    shots.append("03-network.png")

    page.click('button[value="next"]')
    page.wait_for_load_state("networkidle")
    page.wait_for_selector('input[name="admin_pass"]', timeout=10000)
    page.fill('input[name="admin_pass"]', "secret12345")
    page.screenshot(path=str(out / "04-system.png"), full_page=True)
    shots.append("04-system.png")

    page.click('button[value="next"]')
    page.wait_for_load_state("networkidle")
    page.wait_for_selector('select[name="wg"]', timeout=10000)
    page.screenshot(path=str(out / "05-wireguard.png"), full_page=True)
    shots.append("05-wireguard.png")

    page.click('button[value="next"]')
    page.wait_for_load_state("networkidle")
    page.screenshot(path=str(out / "06-confirm.png"), full_page=True)
    shots.append("06-confirm.png")

    # не жмём «Начать» — сервер уйдёт в shutdown; progress/finish — отдельно
    browser.close()

print(json.dumps({"shots": shots, "out": str(out)}))
PY

# progress + finish screens (отдельный MODE)
kill "$SRV" 2>/dev/null || true
wait "$SRV" 2>/dev/null || true

printf '%s\n' '{"percent":42,"text":"Развёртывание системы · осталось ~4 мин"}' > "$RUNDIR/progress.json"
export VLANIT_GUI_MODE=progress
python3 "$WORKDIR/gui/server.py" &
SRV=$!
sleep 0.5
python3 - "$PORT" "$OUT" <<'PY'
from pathlib import Path
import sys
from playwright.sync_api import sync_playwright
port, out = int(sys.argv[1]), Path(sys.argv[2])
with sync_playwright() as p:
    browser = p.chromium.launch(args=["--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"])
    page = browser.new_page(viewport={"width": 1024, "height": 768})
    page.goto(f"http://127.0.0.1:{port}/")
    page.wait_for_load_state("networkidle")
    page.screenshot(path=str(out / "07-progress.png"), full_page=True)
    browser.close()
print("07-progress.png")
PY
kill "$SRV" 2>/dev/null || true
wait "$SRV" 2>/dev/null || true

cat > "$RUNDIR/finish.txt" <<'EOF'
VLANit PBX OS 1.4.0
Debian: 13
Podman: (в образе)
MikoPBX: 2026.6.99
Hostname: vlanit-pbx
IP-адрес: 192.168.1.50
Статус MikoPBX: будет запущена автоматически при первой загрузке
Веб-интерфейс: https://192.168.1.50 (логин: admin)
Зеркало дисков: RAID1 активно (/dev/sda + /dev/sdb)

Извлеките установочный USB и перезагрузите устройство.
EOF
export VLANIT_GUI_MODE=finish
python3 "$WORKDIR/gui/server.py" &
SRV=$!
sleep 0.5
python3 - "$PORT" "$OUT" <<'PY'
from pathlib import Path
import sys
from playwright.sync_api import sync_playwright
port, out = int(sys.argv[1]), Path(sys.argv[2])
with sync_playwright() as p:
    browser = p.chromium.launch(args=["--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"])
    page = browser.new_page(viewport={"width": 1024, "height": 768})
    page.goto(f"http://127.0.0.1:{port}/")
    page.wait_for_load_state("networkidle")
    page.screenshot(path=str(out / "08-finish.png"), full_page=True)
    browser.close()
print("08-finish.png")
PY

echo "shots → $OUT"
ls -la "$OUT"
