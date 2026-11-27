#!/usr/bin/env bash
# unit: выбор surface + смерть netsurf → fallback (#60) + harden helpers
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

# log path helpers (без реального fb)
export VLANIT_GUI_LOG_DIR="$TMP/run"
[ "$(vlanit_fb_log_dir)" = "$TMP/run" ]
[ "$(vlanit_fb_netsurf_log)" = "$TMP/run/gui-netsurf.log" ]
export VLANIT_NETSURF_LOG="$TMP/custom-ns.log"
[ "$(vlanit_fb_netsurf_log)" = "$TMP/custom-ns.log" ]
unset VLANIT_NETSURF_LOG

# prepare_console: не падает; при fb0 выставляет SDL_FBDEV
unset FRAMEBUFFER SDL_FBDEV || true
vlanit_fb_prepare_console
if [ -c /dev/fb0 ]; then
    [ "${FRAMEBUFFER:-}" = "/dev/fb0" ]
    [ "${SDL_FBDEV:-}" = "/dev/fb0" ]
fi

# wait_done: мёртвый ns → 1 (grace короткий для unit)
export VLANIT_NETSURF_GRACE=0.2
donef="$TMP/done"
sleep 30 &
SRV=$!
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
( sleep 0.05; : >"$donef" ) &
vlanit_fb_wait_done "$SRV" "$NS" "$donef"
kill "$SRV" "$NS" 2>/dev/null || true
wait "$SRV" "$NS" 2>/dev/null || true

echo "PASS test-netsurf-fb"
