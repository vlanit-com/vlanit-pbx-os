# Выбор surface и запуск netsurf-fb (issue #60; HTML primary).
# Debian netsurf-fb 3.11: surface `linux` НЕ собран (valid: ram sdl x vnc wld).
# На /dev/fb0 без X — sdl + SDL_VIDEODRIVER=fbcon.

vlanit_fb_log_dir() {
    printf '%s\n' "${VLANIT_GUI_LOG_DIR:-/run/vlanit}"
}

vlanit_fb_netsurf_log() {
    printf '%s\n' "${VLANIT_NETSURF_LOG:-$(vlanit_fb_log_dir)/gui-netsurf.log}"
}

# VT + SDL env для fbcon (tty1 после plymouth).
vlanit_fb_prepare_console() {
    if command -v chvt >/dev/null 2>&1; then
        chvt 1 2>/dev/null || true
    fi
    if [ -c /dev/fb0 ]; then
        export FRAMEBUFFER="${FRAMEBUFFER:-/dev/fb0}"
        export SDL_FBDEV="${SDL_FBDEV:-/dev/fb0}"
    fi
}

vlanit_fb_pick_surface() {
    if [ -n "${VLANIT_FB_SURFACE:-}" ]; then
        printf '%s\n' "$VLANIT_FB_SURFACE"
        return 0
    fi
    if [ -c /dev/fb0 ]; then
        printf 'sdl\n'
        return 0
    fi
    return 1
}

# vlanit_fb_start_netsurf <url> <surface> → печатает PID
vlanit_fb_start_netsurf() {
    local url="$1" surface="$2"
    local log
    mkdir -p "$(vlanit_fb_log_dir)"
    log="$(vlanit_fb_netsurf_log)"
    : >"$log"
    vlanit_fb_prepare_console
    if [ "$surface" = "sdl" ] && [ -c /dev/fb0 ] && [ -z "${DISPLAY:-}" ]; then
        export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-fbcon}"
    fi
    {
        echo "[vlanit-fb] $(date -Is) surface=$surface url=$url"
        echo "[vlanit-fb] FRAMEBUFFER=${FRAMEBUFFER:-} SDL_FBDEV=${SDL_FBDEV:-} SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-} DISPLAY=${DISPLAY:-}"
    } >>"$log"
    case "$surface" in
        sdl|ram)
            netsurf-fb -f "$surface" -w "${VLANIT_FB_WIDTH:-1024}" -h "${VLANIT_FB_HEIGHT:-768}" "$url" >>"$log" 2>&1 &
            ;;
        *)
            netsurf-fb -f "$surface" "$url" >>"$log" 2>&1 &
            ;;
    esac
    printf '%s\n' "$!"
}

# Ждать done-файл или смерть netsurf/сервера.
# 0 = done; 1 = netsurf умер / сбой.
vlanit_fb_wait_done() {
    local srv_pid="$1" ns_pid="$2" done_file="$3"
    local grace
    grace="${VLANIT_NETSURF_GRACE:-1.2}"
    sleep "$grace"
    if ! kill -0 "$ns_pid" 2>/dev/null; then
        wait "$ns_pid" 2>/dev/null || true
        return 1
    fi
    while kill -0 "$srv_pid" 2>/dev/null; do
        if [ -f "$done_file" ]; then
            return 0
        fi
        if ! kill -0 "$ns_pid" 2>/dev/null; then
            wait "$ns_pid" 2>/dev/null || true
            return 1
        fi
        sleep 0.3
    done
    return 1
}

# Старт netsurf с одним повтором при ранней смерти (VT после plymouth).
# vlanit_fb_serve_browser <url> <surface> <srv_pid> <done_file>
# 0 = done-файл появился (netsurf ещё может жить — убить снаружи);
# печатает PID последнего netsurf в VLANIT_FB_LAST_NS_PID.
vlanit_fb_serve_browser() {
    local url="$1" surface="$2" srv_pid="$3" done_file="$4"
    local ns_pid attempt log
    log="$(vlanit_fb_netsurf_log)"
    VLANIT_FB_LAST_NS_PID=""
    for attempt in 1 2; do
        if [ "$attempt" -eq 2 ]; then
            echo "vlanit-fb: netsurf retry (attempt $attempt)" >&2
            sleep 0.5
            vlanit_fb_prepare_console
        fi
        ns_pid="$(vlanit_fb_start_netsurf "$url" "$surface")"
        VLANIT_FB_LAST_NS_PID="$ns_pid"
        if vlanit_fb_wait_done "$srv_pid" "$ns_pid" "$done_file"; then
            return 0
        fi
        kill "$ns_pid" 2>/dev/null || true
        wait "$ns_pid" 2>/dev/null || true
        echo "vlanit-fb: netsurf attempt $attempt failed (log: $log)" >&2
        if [ -f "$log" ]; then
            tail -n 8 "$log" >&2 || true
        fi
    done
    return 1
}
