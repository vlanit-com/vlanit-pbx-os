#!/usr/bin/env bash
# tests/unit/test-disk-lib.sh — unit-тесты installer/lib/disk.sh.
# lv_data_mib: расчёт размера LV data по меньшему диску зеркала
# (min − ESP 1024 − root LV − запас 128; system_size_mib из build.yaml).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

# изолированный PAYLOAD с build.yaml
mkdir -p "$WORK/payload"
cat > "$WORK/payload/build.yaml" <<'EOF'
installer:
  system_size_mib: 40960
EOF
PAYLOAD="$WORK/payload"

# shellcheck source=../../installer/lib/common.sh
source "$ROOT/installer/lib/common.sh"
# shellcheck source=../../installer/lib/disk.sh
source "$ROOT/installer/lib/disk.sh"

# 50 GiB и 64 GiB → min 50: 51200 - 1024 - 40960 - 128 = 9088
got="$(lv_data_mib $((50 * 1024**3)) $((64 * 1024**3)))"
[ "$got" -eq 9088 ] && ok "lv_data_mib: min(50,64)=9088" || bad "lv_data_mib: ожидалось 9088, получено $got"

# один диск 50 GiB → тот же результат
got="$(lv_data_mib $((50 * 1024**3)))"
[ "$got" -eq 9088 ] && ok "lv_data_mib: один диск 50=9088" || bad "lv_data_mib: ожидалось 9088, получено $got"

# равные 256 GiB → 262144 - 1024 - 40960 - 128 = 220032
got="$(lv_data_mib $((256 * 1024**3)) $((256 * 1024**3)))"
[ "$got" -eq 220032 ] && ok "lv_data_mib: 256+256=220032" || bad "lv_data_mib: ожидалось 220032, получено $got"

# минимально допустимый (50 GiB) — положительный остаток; 40 GiB — отрицательный
got="$(lv_data_mib $((40 * 1024**3)))"
[ "$got" -lt 0 ] && ok "lv_data_mib: 40 GiB < 0 (отказ)" || bad "lv_data_mib: 40 GiB должен давать отрицательный размер"

# порядок аргументов не важен (min)
got="$(lv_data_mib $((64 * 1024**3)) $((50 * 1024**3)))"
[ "$got" -eq 9088 ] && ok "lv_data_mib: min независимо от порядка" || bad "lv_data_mib: ожидалось 9088, получено $got"

exit "$fail"
