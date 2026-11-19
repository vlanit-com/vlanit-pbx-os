# Выполнение этапов установки из уже выставленных переменных окружения.
# Вызывается после collect (dialog / HTML / Cursive / autoinstall).
# Требует: TARGET_DISK, NET_*, SYS_*, ADMIN_*, PBX_*, WG_* (опц.), AUTOMODE.

# install_validate_preflight — проверки до деструктивных операций
install_validate_preflight() {
    [ "$HW_BOOT_MODE" = "UEFI" ] || die "требуется UEFI"
    [ -n "$TARGET_DISK" ] || die "не выбран целевой диск"
    echo "$TARGET_DISK" | grep -q "^/dev/" || die "некорректный диск: $TARGET_DISK"
    disk_is_clean_target "$TARGET_DISK" || die "на $TARGET_DISK есть смонтированные разделы"
    if [ -n "${MIRROR_DISK:-}" ]; then
        [ "$MIRROR_DISK" != "$TARGET_DISK" ] || die "mirror_disk совпадает с disk"
        disk_is_clean_target "$MIRROR_DISK" || die "на $MIRROR_DISK есть смонтированные разделы"
    fi
    [ -n "$ADMIN_PASS" ] || die "задайте пароль администратора"
    [ "${#ADMIN_PASS}" -ge 8 ] || die "пароль короче 8 символов"
    [ -f "/usr/share/zoneinfo/$TZ_NAME" ] || die "неизвестный часовой пояс: $TZ_NAME"
    [ -n "$NET_IFACE" ] || die "не выбран сетевой интерфейс"
    for d in "$TARGET_DISK" ${MIRROR_DISK:-}; do
        [ -n "$d" ] || continue
        size_bytes="$(disk_size_bytes "$d")"
        usable="$(usable_mib "$size_bytes")"
        sys_mib="$(installer_root_mib "$usable")"
        data_mib=$(( usable - sys_mib ))
        min_data_mib=$(( DATA_MIN_GIB * 1024 ))
        [ "$data_mib" -ge "$min_data_mib" ] || \
            die "диск $(human_gb "$size_bytes") GiB слишком мал (нужно Data ≥ $DATA_MIN_GIB ГиБ)"
    done
}

# install_ensure_pbx_password — пустой → автоген
install_ensure_pbx_password() {
    PBX_PASS_GENERATED="${PBX_PASS_GENERATED:-0}"
    if [ -z "${PBX_ADMIN_PASS:-}" ]; then
        PBX_ADMIN_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)"
        PBX_PASS_GENERATED=1
    fi
    export PBX_ADMIN_PASS PBX_PASS_GENERATED
}

# install_run_stages — разметка, deploy, bootloader, …
install_run_stages() {
    local progress_file="${PROGRESS_FILE:-/run/vlanit/progress.json}"
    mkdir -p "$(dirname "$progress_file")"
    log "=== начало установки на $TARGET_DISK ==="

    # PROGRESS_UI=dialog|json|none — dialog gauge только для dialog-фронта
    : "${PROGRESS_UI:=dialog}"
    if [ -n "${AUTOMODE:-}" ]; then
        PROGRESS_UI=none
        echo "VLANit Installer — журнал: $LOG_FILE"
    elif [ "$PROGRESS_UI" = "dialog" ]; then
        progress_begin "Установка VLANit PBX OS"
    else
        PROGRESS_START="$(date +%s)"
        progress_init_calibration
    fi

    # Пишем progress.json для HTML poll (и при dialog gauge)
    _progress_json() {
        local pct="$1" text="$2"
        printf '{"percent":%s,"text":%s}\n' "$pct" "$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$text")" \
            > "$progress_file" 2>/dev/null || true
    }

    verify_payload() {
        ( cd "$PAYLOAD" && sha256sum -c golden.tar.zst.sha256 ) || \
            die "контрольная сумма golden.tar.zst не соответствует манифесту"
        ( cd "$PAYLOAD" && sha256sum -c mikopbx-2026.6.99-amd64.tar.zst.sha256 ) || \
            die "контрольная сумма mikopbx.tar.zst не соответствует манифесту"
        log "payload корректен"
    }
    stage_partitions() {
        partition_disk "$TARGET_DISK"
        [ -z "${MIRROR_DISK:-}" ] || partition_disk "$MIRROR_DISK"
    }
    stage_deploy() { deploy_golden "$TARGET_DISK"; }
    stage_mikopbx_env() { configure_target_mikopbx "$PBX_NAME" "$PBX_ADMIN_LOGIN" "$PBX_ADMIN_PASS" "$TZ_NAME"; }

    # обёртка: тик JSON + run_stage
    run_stage_ui() {
        local pct="$1" text="$2"
        shift 2
        _progress_json "$pct" "$text"
        if [ "$PROGRESS_UI" = "dialog" ]; then
            run_stage "$pct" "$text" "$@"
        elif [ -n "${AUTOMODE:-}" ]; then
            progress_stage "$pct" "$text"
            "$@"
        else
            # json UI: без gauge; лог в файл, тик в progress.json
            progress_stage "$pct" "$text"
            { "$@" >> "$LOG_FILE" 2>&1; } </dev/null || die "сбой этапа: $text"
        fi
    }

    run_stage_ui 3 "Проверка контрольных сумм" verify_payload
    run_stage_ui 8 "Разметка дисков" stage_partitions
    run_stage_ui 13 "Хранилище (LVM, Btrfs)" create_storage "$TARGET_DISK" ${MIRROR_DISK:-}
    run_stage_ui 60 "Развёртывание системы" stage_deploy
    run_stage_ui 65 "Конфигурация системы" \
        configure_target_system "$SYS_HOSTNAME" "$ADMIN_USER" "$ADMIN_PASS" "$SSH_ENABLED" "$TZ_NAME" "${KERNEL_ARGS:-}"
    run_stage_ui 68 "Настройка сети" \
        write_target_network "$SYS_MNT" "$NET_IFACE" "$NET_MODE" "$NET_ADDR" "$NET_GW" "$NET_DNS"
    if [ "${WG_ENABLED:-no}" = "yes" ]; then
        run_stage_ui 70 "Настройка WireGuard" \
            configure_target_wireguard "$WG_ADDR" "$WG_PORT" "${WG_PEERS_FILE:-}"
    fi
    run_stage_ui 72 "Настройка MikoPBX" stage_mikopbx_env
    run_stage_ui 85 "Импорт образа MikoPBX" import_mikopbx_image
    run_stage_ui 95 "Загрузчик (initramfs, GRUB)" install_bootloader ${MIRROR_DISK:-}

    stage_finalize() {
        post_install_report "$TARGET_DISK"
        mount -o subvolid=5 LABEL=vlanit-system /mnt 2>/dev/null && {
            btrfs subvolume snapshot -r /mnt/@ /mnt/@snapshots/post-install-@ 2>/dev/null || true
            umount /mnt
        } || true
    }
    run_stage_ui 98 "Финальные операции" stage_finalize

    WG_PUBKEY=""
    [ "${WG_ENABLED:-no}" = "yes" ] && WG_PUBKEY="$(wireguard_pubkey)"
    export WG_PUBKEY
    unmount_target

    _progress_json 100 "Готово"
    if [ "$PROGRESS_UI" = "dialog" ]; then
        progress_end
    else
        log "=== установка завершена ==="
    fi
}

# install_finish_text — текст экрана 7 (stdout)
install_finish_text() {
    local IP_ADDR="" podman_v
    for _ in $(seq 1 15); do
        IP_ADDR="$(ip -4 -o addr show dev "$NET_IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
        [ -n "$IP_ADDR" ] && break
        sleep 1
    done
    [ -n "$IP_ADDR" ] || IP_ADDR="<адрес будет назначен при загрузке>"
    podman_v="$(yaml_get "$PAYLOAD/release-manifest.yaml" podman "")"
    [ -n "$podman_v" ] || podman_v="(в образе)"
    local ver
    ver="$(yaml_get "$PAYLOAD/release-manifest.yaml" distro.version 1.0)"
    local text
    text="VLANit PBX OS $ver
Debian: $(yaml_get "$PAYLOAD/release-manifest.yaml" debian.version 13)
Podman: $podman_v
MikoPBX: 2026.6.99
Hostname: $SYS_HOSTNAME
IP-адрес: $IP_ADDR
Статус MikoPBX: будет запущена автоматически при первой загрузке
Веб-интерфейс: https://$IP_ADDR (логин: $PBX_ADMIN_LOGIN)"
    [ -n "${MIRROR_DISK:-}" ] && text="$text
Зеркало дисков: RAID1 активно ($TARGET_DISK + $MIRROR_DISK)"
    [ "${PBX_PASS_GENERATED:-0}" = "1" ] && text="$text
Пароль веб-админа сгенерирован автоматически, сохраните:
$PBX_ADMIN_PASS"
    [ -n "${WG_PUBKEY:-}" ] && text="$text
WireGuard: включён ($WG_ADDR, порт $WG_PORT)
Публичный ключ устройства (добавьте на пир):
$WG_PUBKEY"
    text="$text

Извлеките установочный USB и перезагрузите устройство."
    printf '%s\n' "$text"
}
