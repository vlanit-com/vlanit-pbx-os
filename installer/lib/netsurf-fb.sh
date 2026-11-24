# Выбор surface и запуск netsurf-fb (issue #60).
# Debian netsurf-fb 3.11: surface `linux` НЕ собран (valid: ram sdl x vnc wld).
# На /dev/fb0 без X — sdl + SDL_VIDEODRIVER=fbcon.

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
    if [ "$surface" = "sdl" ] && [ -c /dev/fb0 ] && [ -z "${DISPLAY:-}" ]; then
        export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-fbcon}"
    fi
    case "$surface" in
        sdl|ram)
            netsurf-fb -f "$surface" -w "${VLANIT_FB_WIDTH:-1024}" -h "${VLANIT_FB_HEIGHT:-768}" "$url" &
            ;;
        *)
            netsurf-fb -f "$surface" "$url" &
            ;;
    esac
    printf '%s\n' "$!"
}

# Ждать done-файл или смерть netsurf/сервера.
# 0 = done; 1 = netsurf умер / сбой; вызывает cleanup снаружи через trap.
vlanit_fb_wait_done() {
    local srv_pid="$1" ns_pid="$2" done_file="$3"
    # быстрый fail: unknown surface / сразу exit
    sleep 0.4
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
