#!/usr/bin/env bash
# unit: doctor GUI — JSON→HTML + launcher без fb (issue #56)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUI="$ROOT/doctor/gui"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; kill $SRV_PID 2>/dev/null || true' EXIT

cat >"$TMP/fake-doctor.sh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{
  "host": "vlanit-test",
  "result": "FAIL",
  "checks": [
    {"group":"system","check":"hostname","status":"OK","desc":"hostname задан","hint":"hostnamectl ..."},
    {"group":"system","check":"timesyncd","status":"FAIL","desc":"синхронизация времени","hint":"systemctl enable --now systemd-timesyncd"},
    {"group":"network","check":"dns-resolve","status":"SKIP","desc":"DNS","hint":""}
  ]
}
JSON
EOF
chmod +x "$TMP/fake-doctor.sh"

export VLANIT_DOCTOR_CMD="$TMP/fake-doctor.sh"
export VLANIT_DOCTOR_PORT=18766
export VLANIT_DOCTOR_STATIC="$GUI/static"
export VLANIT_DOCTOR_DONE="$TMP/doctor-gui-done"

python3 "$GUI/server.py" &
SRV_PID=$!
for _ in $(seq 1 50); do
    if python3 -c "import socket;s=socket.socket();s.settimeout(0.2);s.connect(('127.0.0.1',$VLANIT_DOCTOR_PORT))" 2>/dev/null; then
        break
    fi
    sleep 0.05
done

OVERVIEW="$(curl -fsS "http://127.0.0.1:${VLANIT_DOCTOR_PORT}/")"
echo "$OVERVIEW" | grep -q 'Итог: FAIL'
echo "$OVERVIEW" | grep -q 'system'
echo "$OVERVIEW" | grep -q 'network'
echo "$OVERVIEW" | grep -q '/group/system'

GROUP="$(curl -fsS "http://127.0.0.1:${VLANIT_DOCTOR_PORT}/group/system")"
echo "$GROUP" | grep -q 'timesyncd'
echo "$GROUP" | grep -q 'FAIL'
echo "$GROUP" | grep -q 'systemctl enable --now systemd-timesyncd'
echo "$GROUP" | grep -q 'hostname'

# launcher без fb → exit 2
set +e
out="$(VLANIT_FB_SURFACE= bash "$GUI/launch-gui.sh" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 2 ]
echo "$out" | grep -q 'vlanit-doctor'

echo "PASS test-doctor-gui"
