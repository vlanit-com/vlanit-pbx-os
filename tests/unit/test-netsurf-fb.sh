#!/usr/bin/env bash
# unit: выбор surface + смерть netsurf → fallback (#60)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../installer/lib/netsurf-fb.sh
. "$ROOT/installer/lib/netsurf-fb.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# явный override
got="$(VLANIT_FB_SURFACE=ram vlanit_fb_pick_surface)"
[ "$got" = "ram" ]

# без fb0 и без override → fail
unset VLANIT_FB_SURFACE || true
if [ -c /dev/fb0 ]; then
    got="$(vlanit_fb_pick_surface)"
    # Debian: не linux
    [ "$got" = "sdl" ]
else
    if vlanit_fb_pick_surface >/dev/null; then
        echo "FAIL: pick без fb0 должен падать" >&2
        exit 1
    fi
fi

# wait_done: мёртвый ns → 1
donef="$TMP/done"
: >"$TMP/alive"
# fake srv держим, ns уже мёртв
sleep 30 &
SRV=$!
# ns pid несуществующий
if vlanit_fb_wait_done "$SRV" 999999 "$donef"; then
    kill "$SRV" 2>/dev/null || true
    echo "FAIL: wait_done должен вернуть 1 на мёртвом ns" >&2
    exit 1
fi
kill "$SRV" 2>/dev/null || true
wait "$SRV" 2>/dev/null || true

# wait_done: done-файл → 0
sleep 30 &
SRV=$!
sleep 30 &
NS=$!
( sleep 0.2; : >"$donef" ) &
vlanit_fb_wait_done "$SRV" "$NS" "$donef"
kill "$SRV" "$NS" 2>/dev/null || true
wait "$SRV" "$NS" 2>/dev/null || true

echo "PASS test-netsurf-fb"
