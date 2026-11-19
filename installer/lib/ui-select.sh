# Выбор фронтенда: HTML (netsurf-fb) → Cursive → dialog.

ui_gui_available() {
    command -v netsurf-fb >/dev/null 2>&1 || return 1
    [ -f "$INSTALLER_DIR/gui/server.py" ] || return 1
    [ -f "$INSTALLER_DIR/gui/launch-gui.sh" ] || return 1
    # fb0 или sdl-поверхность (QEMU)
    [ -c /dev/fb0 ] && return 0
    # без fb — можно sdl, если явно разрешено
    [ "${VLANIT_ALLOW_SDL:-0}" = "1" ] && return 0
    return 1
}

ui_cursive_available() {
    local bin="$INSTALLER_DIR/bin/vlanit-tui"
    [ -x "$bin" ] || return 1
    return 0
}

# ui_force from cmdline: vlanit.ui=gui|tui|dialog
ui_from_cmdline() {
    local arg
    for arg in $(cat /proc/cmdline 2>/dev/null); do
        case "$arg" in
            vlanit.ui=*) echo "${arg#vlanit.ui=}"; return 0 ;;
        esac
    done
    echo ""
}

# UI_FRONTEND=gui|tui|dialog — фактический фронт после collect
UI_FRONTEND=""

# ui_collect_config — заполняет /run/vlanit/install-config.json; 0=ok
# return 2 → вызвать dialog collect
ui_collect_config() {
    local force mode
    force="$(ui_from_cmdline)"
    mkdir -p /run/vlanit
    rm -f /run/vlanit/install-config.json /run/vlanit/gui-done
    UI_FRONTEND=""

    mode=""
    case "$force" in
        gui|tui|dialog) mode="$force" ;;
        *)
            if ui_gui_available; then mode=gui
            elif ui_cursive_available; then mode=tui
            else mode=dialog
            fi
            ;;
    esac
    log "UI frontend: $mode"

    case "$mode" in
        gui)
            if bash "$INSTALLER_DIR/gui/launch-gui.sh"; then
                UI_FRONTEND=gui
            else
                log "GUI недоступен — fallback"
                if ui_cursive_available; then
                    "$INSTALLER_DIR/bin/vlanit-tui" || return 1
                    UI_FRONTEND=tui
                else
                    return 2
                fi
            fi
            ;;
        tui)
            "$INSTALLER_DIR/bin/vlanit-tui" || return 1
            UI_FRONTEND=tui
            ;;
        dialog)
            return 2
            ;;
    esac
    export UI_FRONTEND
    [ -f /run/vlanit/install-config.json ] || return 1
    return 0
}
