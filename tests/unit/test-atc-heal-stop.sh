#!/usr/bin/env bash
# unit: vlanit-atc-password-heal — stop mikopbx → exit 0 (issue #45)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HEAL_SRC="$ROOT/rootfs/vlanit-atc-password-heal.sh"
[ -f "$HEAL_SRC" ] || { echo "FAIL: нет $HEAL_SRC"; exit 1; }

# fake bin: mikopbx никогда не running, логи без баннера
mkdir -p "$TMP/bin" "$TMP/etc/vlanit" "$TMP/var/lib/vlanit"
printf 'testpass' >"$TMP/etc/vlanit/atc-admin-password"
chmod 600 "$TMP/etc/vlanit/atc-admin-password"
echo Asia/Dubai >"$TMP/etc/timezone"

cat >"$TMP/bin/systemctl" <<'EOF'
#!/bin/sh
# is-active mikopbx → всегда inactive
exit 1
EOF
chmod +x "$TMP/bin/systemctl"

cat >"$TMP/bin/podman" <<'EOF'
#!/bin/sh
# inspect Running=false; logs пустые
case "$1" in
  inspect) echo false; exit 0 ;;
  logs) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TMP/bin/podman"

cat >"$TMP/bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TMP/bin/logger"

cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
echo '{}'
exit 0
EOF
chmod +x "$TMP/bin/curl"

# подмена путей: скрипт хардкодит /etc/vlanit — chroot-подобно через
# sed во временную копию
sed \
  -e "s|/etc/vlanit/atc-admin-password|$TMP/etc/vlanit/atc-admin-password|g" \
  -e "s|/etc/timezone|$TMP/etc/timezone|g" \
  -e "s|/var/lib/vlanit/|$TMP/var/lib/vlanit/|g" \
  "$HEAL_SRC" >"$TMP/heal.sh"
chmod +x "$TMP/heal.sh"

export PATH="$TMP/bin:$PATH"
# без sleep-цикла 10 мин: подменяем seq/sleep — готовый скрипт сам
# выйдет на первой итерации (mikopbx_running=false)
start=$(date +%s)
set +e
out="$("$TMP/heal.sh" 2>&1)"
rc=$?
set -e
end=$(date +%s)
elapsed=$((end - start))

echo "$out" | grep -q 'остановлен\|не запущен' \
  || { echo "FAIL: нет сообщения об остановке"; echo "$out"; exit 1; }
[ "$rc" = "0" ] || { echo "FAIL: rc=$rc (ожидали 0)"; echo "$out"; exit 1; }
[ "$elapsed" -lt 30 ] || { echo "FAIL: слишком долго ${elapsed}s"; exit 1; }

echo "PASS test-atc-heal-stop (${elapsed}s)"
