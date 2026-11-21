#!/usr/bin/env bash
# unit: update GUI — нет пакета / confirm / no-fb launcher (issue #58)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUI="$ROOT/update/gui"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; kill $SRV_PID 2>/dev/null || true' EXIT

# fake vlanit-update (не применять)
cat >"$TMP/fake-update" <<'EOF'
#!/usr/bin/env bash
echo "fake-update $*"
exit 0
EOF
chmod +x "$TMP/fake-update"

export VLANIT_UPDATE_BIN="$TMP/fake-update"
export VLANIT_UPDATE_PORT=18767
export VLANIT_UPDATE_STATIC="$GUI/static"
export VLANIT_UPDATE_DONE="$TMP/update-gui-done"
export VLANIT_UPDATE_STATE="$TMP/state"
export VLANIT_UPDATE_PKG=""
# пустой список USB
export PATH="$TMP/bin:$PATH"
mkdir -p "$TMP/bin"
cat >"$TMP/bin/lsblk" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TMP/bin/lsblk"

python3 "$GUI/server.py" &
SRV_PID=$!
for _ in $(seq 1 50); do
    if python3 -c "import socket;s=socket.socket();s.settimeout(0.2);s.connect(('127.0.0.1',$VLANIT_UPDATE_PORT))" 2>/dev/null; then
        break
    fi
    sleep 0.05
done

page="$(curl -fsS "http://127.0.0.1:${VLANIT_UPDATE_PORT}/")"
echo "$page" | grep -q 'Пакет не найден'

# confirm с фиктивным файлом
touch "$TMP/vlanit-update-test.tar"
page="$(curl -fsS "http://127.0.0.1:${VLANIT_UPDATE_PORT}/confirm?pkg=$TMP/vlanit-update-test.tar")"
echo "$page" | grep -q 'YES — применить'

# launcher без fb / без netsurf
unset VLANIT_FB_SURFACE || true
out="$(bash "$GUI/launch-gui.sh" 2>&1)" && rc=0 || rc=$?
[ "$rc" = "2" ] || { echo "FAIL launch no-fb rc=$rc"; echo "$out"; exit 1; }
echo "$out" | grep -qE 'нет /dev/fb0|netsurf-fb не найден'

echo "PASS test-update-gui"
