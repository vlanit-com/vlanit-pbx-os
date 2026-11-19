#!/usr/bin/env bash
# check-iso-size.sh — сравнить размер ISO с baseline×(1+margin) из config/build.yaml.
# Usage: check-iso-size.sh [path-to.iso]
# Exit: 0 OK · 1 over limit · 2 usage/config error
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${ROOT}/config/build.yaml"
TOP_N="${ISO_SIZE_TOP_N:-5}"

die() { echo "check-iso-size: ERROR: $*" >&2; exit 2; }

ISO="${1:-}"
if [ -z "$ISO" ]; then
    mapfile -t ISOS < <(find "${ROOT}/dist" -maxdepth 1 -type f -name '*.iso' 2>/dev/null | sort)
    [ "${#ISOS[@]}" -ge 1 ] || die "нет ISO (укажите путь или соберите dist/*.iso)"
    [ "${#ISOS[@]}" -eq 1 ] || die "несколько ISO в dist/: укажите путь явно"
    ISO="${ISOS[0]}"
fi
[ -f "$ISO" ] || die "файл не найден: $ISO"
[ -f "$CFG" ] || die "нет $CFG"

# Читаем baseline/margin (PyYAML не обязателен — простой парсер output-секции).
read -r BASELINE_MIB MARGIN_PCT < <(python3 - "$CFG" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
# секция output: до следующего ключа верхнего уровня
m = re.search(r"(?m)^output:\n((?:[ \t]+.*\n)*)", text)
if not m:
    raise SystemExit("output: section missing")
block = m.group(1)
def grab(key, default=None):
    mm = re.search(rf"(?m)^[ \t]+{re.escape(key)}:\s*([0-9.]+)\s*$", block)
    if not mm:
        if default is None:
            raise SystemExit(f"missing output.{key}")
        return default
    return mm.group(1)
print(grab("iso_baseline_mib"), grab("iso_size_margin_pct", "5"))
PY
) || die "не удалось прочитать iso_baseline_mib / iso_size_margin_pct из build.yaml"

python3 -c "import sys; float(sys.argv[1]); float(sys.argv[2])" \
    "$BASELINE_MIB" "$MARGIN_PCT" 2>/dev/null \
    || die "нечисловые baseline/margin: $BASELINE_MIB / $MARGIN_PCT"

BYTES="$(stat -c%s "$ISO")"
# порог в байтах: baseline_mib * (100+margin)/100 * 1024^2
THRESH="$(python3 -c "b=float('$BASELINE_MIB'); m=float('$MARGIN_PCT'); print(int(b * (100.0+m) / 100.0 * 1024 * 1024))")"
MIB="$(python3 -c "print(round(int('$BYTES')/1024/1024, 2))")"
THRESH_MIB="$(python3 -c "print(round(int('$THRESH')/1024/1024, 2))")"

echo "check-iso-size: ISO=$ISO"
echo "check-iso-size: size=${BYTES} B (${MIB} MiB)"
echo "check-iso-size: baseline=${BASELINE_MIB} MiB margin=${MARGIN_PCT}% threshold=${THRESH} B (${THRESH_MIB} MiB)"

# Диагностика: топ элементов внутри ISO (best-effort).
top_members() {
    if command -v 7z >/dev/null 2>&1; then
        echo "check-iso-size: top-${TOP_N} (7z):"
        # Size Date Time Attr Name — берём строки с размером, сортируем
        7z l -ba "$ISO" 2>/dev/null \
            | awk '/^[0-9]{4}-/ && $3 ~ /^\.+$/ && $4 ~ /^[0-9]+$/ {
                   sz=$4; n=$6; for(i=7;i<=NF;i++) n=n" "$i;
                   if (sz+0>0) print sz, n
                 }' \
            | sort -nr \
            | head -n "$TOP_N" \
            | awk '{printf "  %10s  ", $1; $1=""; sub(/^ /,""); print}' \
            && return 0
    fi
    if command -v xorriso >/dev/null 2>&1; then
        echo "check-iso-size: member list via xorriso (sizes limited; listing paths):"
        xorriso -indev "$ISO" -find / -type f 2>/dev/null | head -n "$TOP_N" \
            | sed 's/^/  /' || true
        return 0
    fi
    echo "check-iso-size: WARN: нет 7z/xorriso — топ файлов внутри ISO пропущен"
}
top_members || true

if [ "$BYTES" -gt "$THRESH" ]; then
    echo "check-iso-size: FAIL: ISO больше порога (регрессия размера). Поднимите output.iso_baseline_mib осознанно или уменьшите образ." >&2
    exit 1
fi
echo "check-iso-size: OK"
exit 0
