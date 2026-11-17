#!/usr/bin/env bash
# tests/unit/test-disk-lib.sh — unit-тесты installer/lib/disk.sh.
# usable_mib: диск − ESP 1024 − запас 128 (MiB).
# lv_data_mib: usable − root-LV, где root = system_size_pct % usable
# (pct из build.yaml; переопределение — SYS_SIZE_PCT_OVERRIDE).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

# изолированный PAYLOAD с build.yaml (pct 25)
mkdir -p "$WORK/payload"
cat > "$WORK/payload/build.yaml" <<'EOF'
installer:
  system_size_pct: 25
EOF
PAYLOAD="$WORK/payload"

# shellcheck source=../../installer/lib/common.sh
source "$ROOT/installer/lib/common.sh"
# shellcheck source=../../installer/lib/disk.sh
source "$ROOT/installer/lib/disk.sh"

# 50 GiB: usable = 51200 − 1152 = 50048; root = 12512; data = 37536
got="$(lv_data_mib $((50 * 1024**3)))"
[ "$got" -eq 37536 ] && ok "lv_data_mib: 50=37536" || bad "lv_data_mib: ожидалось 37536, получено $got"

# зеркало 50 + 64 GiB → usable по минимуму (50), тот же результат
got="$(lv_data_mib $((50 * 1024**3)) $((64 * 1024**3)))"
[ "$got" -eq 37536 ] && ok "lv_data_mib: min(50,64)=37536" || bad "lv_data_mib: ожидалось 37536, получено $got"

# порядок аргументов не важен (min)
got="$(lv_data_mib $((64 * 1024**3)) $((50 * 1024**3)))"
[ "$got" -eq 37536 ] && ok "lv_data_mib: min независимо от порядка" || bad "lv_data_mib: ожидалось 37536, получено $got"

# равные 256 GiB: usable = 262144 − 1152 = 260992; root = 65248; data = 195744
got="$(lv_data_mib $((256 * 1024**3)) $((256 * 1024**3)))"
[ "$got" -eq 195744 ] && ok "lv_data_mib: 256+256=195744" || bad "lv_data_mib: ожидалось 195744, получено $got"

# usable_mib напрямую: 64 GiB → 64384
got="$(usable_mib $((64 * 1024**3)))"
[ "$got" -eq 64384 ] && ok "usable_mib: 64=64384" || bad "usable_mib: ожидалось 64384, получено $got"

# installer_root_mib: 25 % от 50048 = 12512; округление вниз
got="$(installer_root_mib 50048)"
[ "$got" -eq 12512 ] && ok "installer_root_mib: 25% от 50048 = 12512" || bad "installer_root_mib: ожидалось 12512, получено $got"
got="$(installer_root_mib 10001)"
[ "$got" -eq 2500 ] && ok "installer_root_mib: округление вниз 2500" || bad "installer_root_mib: ожидалось 2500, получено $got"

# малый профиль стенда: 13 ГиБ, pct 25 → usable 12160, root 3040, data 9120
got="$(lv_data_mib $((13 * 1024**3)))"
[ "$got" -eq 9120 ] && ok "lv_data_mib: 13=9120 (малый профиль)" || bad "lv_data_mib: ожидалось 9120, получено $got"

# переопределение процента (autoinstall): pct 50 на 13 ГиБ → data 6080
SYS_SIZE_PCT_OVERRIDE=50
got="$(lv_data_mib $((13 * 1024**3)))"
[ "$got" -eq 6080 ] && ok "lv_data_mib: override pct 50, 13=6080" || bad "lv_data_mib: ожидалось 6080, получено $got"
SYS_SIZE_PCT_OVERRIDE=

exit "$fail"
