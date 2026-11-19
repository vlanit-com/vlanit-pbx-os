#!/usr/bin/env bash
# Smoke для scripts/check-iso-size.sh без полной сборки ISO.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCR="${ROOT}/scripts/check-iso-size.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

dd if=/dev/zero of="$TMP/ok.iso" bs=1M count=1 status=none
"$SCR" "$TMP/ok.iso" >/tmp/iso-size-ok.log
grep -q 'check-iso-size: OK' /tmp/iso-size-ok.log

# Файл больше порога: подменяем конфиг через крошечный baseline в копии —
# скрипт читает только ROOT/config/build.yaml, поэтому гоняем over через
# python-подсчёт: создаём «ISO» размером baseline*1.05+1 используя env-обход.
# Проще: временно патчим порог, вызывая python для размера > threshold из
# текущего yaml.
THRESH="$(python3 - <<PY
import re
text=open("${ROOT}/config/build.yaml",encoding="utf-8").read()
m=re.search(r"(?m)^output:\n((?:[ \t]+.*\n)*)", text)
block=m.group(1)
b=float(re.search(r"iso_baseline_mib:\s*([0-9.]+)", block).group(1))
pct=float(re.search(r"iso_size_margin_pct:\s*([0-9.]+)", block).group(1))
print(int(b*(100+pct)/100*1024*1024)+1)
PY
)"
# Не создаём гигабайтный файл: подменяем ROOT через копирование скрипта-обёртки
# с CFG на tmp build.yaml где baseline=1.
mkdir -p "$TMP/repo/config" "$TMP/repo/scripts" "$TMP/repo/dist"
cp "$SCR" "$TMP/repo/scripts/check-iso-size.sh"
cat > "$TMP/repo/config/build.yaml" <<'YAML'
output:
  iso_name: fake.iso
  iso_baseline_mib: 1
  iso_size_margin_pct: 5
YAML
# 2 MiB > 1 MiB * 1.05
dd if=/dev/zero of="$TMP/repo/dist/fake.iso" bs=1M count=2 status=none
if bash "$TMP/repo/scripts/check-iso-size.sh" "$TMP/repo/dist/fake.iso" >/tmp/iso-size-fail.log 2>&1; then
    echo "expected FAIL for oversized ISO" >&2
    exit 1
fi
grep -q 'FAIL' /tmp/iso-size-fail.log

echo "PASS test-iso-size-guard"
