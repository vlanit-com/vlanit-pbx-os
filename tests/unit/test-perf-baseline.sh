#!/usr/bin/env bash
# unit: scripts/perf-baseline.sh (Т11)
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCR="$ROOT/scripts/perf-baseline.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
pass() { echo "PASS: $*"; }
bad()  { echo "FAIL: $*"; fail=$((fail+1)); }

row="$("$SCR" record --out "$TMP/p.txt" --version 9.9.9 --date 2026-01-01 \
    --install-sec 100 --agent-sec 50 --iso-to-web-sec 200 --note smoke)"
echo "$row" | grep -q '| 2026-01-01 | 9.9.9 |' && pass "record row" || bad "record row: $row"
grep -q 'install_sec=100' "$TMP/p.txt" && pass "record file" || bad "record file"
[ "$("$SCR" format "$TMP/p.txt")" = "$row" ] && pass "format idempotent" || bad "format"

cat > "$TMP/testing.md" <<'EOF'
# t
<!-- T11-BASELINE-START -->
| дата | версия | ISO МиБ | install_sec | agent_sec | iso_to_web_sec | заметка |
|---|---|---|---|---|---|---|
| 2026-01-01 | 9.9.8 | 700 | 80 | 50 | 180 | prev |
<!-- T11-BASELINE-END -->
EOF
sed "s|^DOCS=.*|DOCS=\"$TMP/testing.md\"|" "$SCR" > "$TMP/perf.sh"
chmod +x "$TMP/perf.sh"
"$TMP/perf.sh" record --out "$TMP/p2.txt" --version 9.9.9 --date 2026-01-02 \
    --install-sec 120 --agent-sec 50 --iso-to-web-sec 200 --note next >/dev/null
warn="$("$TMP/perf.sh" append-docs "$TMP/p2.txt" 2>&1 >/dev/null || true)"
grep -q '| 2026-01-02 | 9.9.9 |' "$TMP/testing.md" && pass "append-docs" || bad "append-docs"
echo "$warn" | grep -q 'WARN Т11: install_sec' && pass "warn >20%" || bad "warn missing: $warn"

[ "$fail" -eq 0 ] && echo "ALL PASS" && exit 0
echo "FAILED: $fail"; exit 1
