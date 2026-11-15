# Развёртывание системы на целевой диск: LVM (linear или raid1-зеркало),
# subvolumes, golden image, fstab, загрузчик, импорт MikoPBX,
# firstboot-конфигурация.
# Все деструктивные операции — только после confirm_install() в основном скрипте.

SYS_MNT="/mnt/vlanit-target"
VG_NAME="vg0"
LV_ROOT="/dev/${VG_NAME}/root"
LV_DATA="/dev/${VG_NAME}/data"

# Создание хранилища: PV на каждом диске (p2), VG vg0, LV root/data.
# Один диск — linear, два диска — raid1-зеркало (по легу на диск).
# $1 — основной диск, $2 — (опционально) второй диск зеркала.
create_storage() {
    local disk_a="$1" disk_b="${2:-}"
    local sys_mib data_mib
    sys_mib="$(yaml_get "$PAYLOAD/build.yaml" installer.system_size_mib 40960)"

    log "PV: $(partition_device "$disk_a" 2)"
    pvcreate -y "$(partition_device "$disk_a" 2)" || die "pvcreate не выполнен"
    if [ -n "$disk_b" ]; then
        log "PV (зеркало): $(partition_device "$disk_b" 2)"
        pvcreate -y "$(partition_device "$disk_b" 2)" || die "pvcreate (зеркало) не выполнен"
        vgcreate -y "$VG_NAME" \
            "$(partition_device "$disk_a" 2)" "$(partition_device "$disk_b" 2)" \
            || die "vgcreate не выполнен"
        data_mib="$(lv_data_mib "$(disk_size_bytes "$disk_a")" "$(disk_size_bytes "$disk_b")")"
        [ "$data_mib" -gt 0 ] || die "зеркало: диски слишком малы для root ${sys_mib}MiB"
        log "LV: root ${sys_mib}MiB, data ${data_mib}MiB (raid1, мин. диск)"
        lvcreate -y --type raid1 -m 1 -n root -L "${sys_mib}M" "$VG_NAME" || die "lvcreate root (raid1) не выполнен"
        lvcreate -y --type raid1 -m 1 -n data -L "${data_mib}M" "$VG_NAME" || die "lvcreate data (raid1) не выполнен"
    else
        vgcreate -y "$VG_NAME" "$(partition_device "$disk_a" 2)" || die "vgcreate не выполнен"
        log "LV: root ${sys_mib}MiB, data — остаток (linear)"
        lvcreate -y -n root -L "${sys_mib}M" "$VG_NAME" || die "lvcreate root не выполнен"
        lvcreate -y -n data -l 100%FREE "$VG_NAME" || die "lvcreate data не выполнен"
    fi

    log "mkfs.vfat $(partition_device "$disk_a" 1) (EFI)"
    mkfs.vfat -F 32 -n VLANIT_EFI "$(partition_device "$disk_a" 1)" || die "mkfs.vfat EFI не выполнен"
    if [ -n "$disk_b" ]; then
        # метка ≤11 символов (ограничение mkfs.vfat; «VLANIT_EFI_B» молча
        # роняла установщик через set -e — полевой дефект найден стендом)
        log "mkfs.vfat $(partition_device "$disk_b" 1) (EFI-B)"
        mkfs.vfat -F 32 -n VLANIT-ESPB "$(partition_device "$disk_b" 1)" || die "mkfs.vfat EFI-B не выполнен"
    fi
    log "mkfs.btrfs $LV_ROOT (System)"
    mkfs.btrfs -f -L vlanit-system "$LV_ROOT" || die "mkfs.btrfs System не выполнен"
    log "mkfs.btrfs $LV_DATA (Data)"
    mkfs.btrfs -f -L vlanit-data "$LV_DATA" || die "mkfs.btrfs Data не выполнен"

    log "создание subvolumes"
    mount "$LV_ROOT" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@var_log
    btrfs subvolume create /mnt/@snapshots
    umount /mnt

    mount "$LV_DATA" /mnt
    btrfs subvolume create /mnt/mikopbx-cf
    btrfs subvolume create /mnt/mikopbx-storage
    btrfs subvolume create /mnt/.snapshots
    umount /mnt
}

deploy_golden() {
    local disk_a="$1"
    local efi
    efi="$(partition_device "$disk_a" 1)"

    mkdir -p "$SYS_MNT"
    mount -o subvol=@,compress=zstd,noatime "$LV_ROOT" "$SYS_MNT"
    mkdir -p "$SYS_MNT/boot/efi" "$SYS_MNT/var/log" "$SYS_MNT/.snapshots" \
             "$SYS_MNT/var/spool/mikopbx/cf" "$SYS_MNT/var/spool/mikopbx/storage"

    log "развёртывание Golden Image (tar.zst)"
    tar -C "$SYS_MNT" --zstd -xpf "$PAYLOAD/golden.tar.zst"

    local sys_uuid data_uuid efi_uuid
    sys_uuid="$(blkid -s UUID -o value "$LV_ROOT")"
    data_uuid="$(blkid -s UUID -o value "$LV_DATA")"
    efi_uuid="$(blkid -s UUID -o value "$efi")"
    [ -n "$sys_uuid" ] && [ -n "$data_uuid" ] || die "не удалось получить UUID файловых систем"

    log "fstab (UUID)"
    cat > "$SYS_MNT/etc/fstab" <<EOF
UUID=$efi_uuid /boot/efi vfat umask=0077 0 2
UUID=$sys_uuid / btrfs subvol=@,compress=zstd,noatime 0 1
UUID=$sys_uuid /var/log btrfs subvol=@var_log,noatime 0 2
UUID=$sys_uuid /.snapshots btrfs subvol=@snapshots,noatime 0 2
UUID=$data_uuid /var/spool/mikopbx/cf btrfs subvol=mikopbx-cf,compress=zstd,noatime 0 2
UUID=$data_uuid /var/spool/mikopbx/storage btrfs subvol=mikopbx-storage,compress=zstd,noatime 0 2
EOF

    # EFI-раздел монтируется для grub-install
    mount "$efi" "$SYS_MNT/boot/efi"
}

# Системная конфигурация целевой системы (без chroot там, где возможно)
configure_target_system() {
    local hostname="$1" admin_user="$2" admin_pass="$3" ssh_enabled="$4" tz="$5"
    local kernel_args="${6:-}"

    echo "$hostname" > "$SYS_MNT/etc/hostname"
    echo "$tz" > "$SYS_MNT/etc/timezone"
    cat > "$SYS_MNT/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	$hostname
::1	localhost ip6-localhost ip6-loopback
EOF
    ln -sf "/usr/share/zoneinfo/$tz" "$SYS_MNT/etc/localtime"

    # GRUB defaults: uuid корня определяется через fstab/grub-probe
    cat > "$SYS_MNT/etc/default/grub" <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="VLANit PBX OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash console=tty0 console=ttyS0,115200"
GRUB_CMDLINE_LINUX="$kernel_args"
GRUB_DISABLE_OS_PROBER=true
GRUB_COLOR_NORMAL="white/black"
GRUB_COLOR_HIGHLIGHT="black/yellow"
EOF

    # локальный администратор (chroot)
    local encrypted
    encrypted="$(openssl passwd -6 "$admin_pass")"
    chroot "$SYS_MNT" /bin/sh -c "
        useradd -m -s /bin/bash '$admin_user' 2>/dev/null || true
        usermod -aG sudo '$admin_user'
        echo '$admin_user:$encrypted' | chpasswd -e
    " || die "не удалось создать администратора"

    # SSH host keys — генерируем ПРИ УСТАНОВКЕ (уникальны на устройстве,
    # в Golden Image их нет): sshd стартует с первой загрузки без падений
    # (issue #17). Drop-in 00-keygen остаётся подстраховкой.
    chroot "$SYS_MNT" /usr/bin/ssh-keygen -A || die "не удалось сгенерировать SSH host keys"

    if [ "$ssh_enabled" = "yes" ]; then
        chroot "$SYS_MNT" systemctl enable ssh.service || true
    else
        chroot "$SYS_MNT" systemctl disable ssh.service || true
    fi
}

configure_target_mikopbx() {
    local pbx_name="$1" admin_login="$2" admin_pass="$3" tz="${4:-Europe/Moscow}"
    local quadlet="$SYS_MNT/etc/containers/systemd/mikopbx.container"
    [ -f "$quadlet" ] || die "quadlet-файл отсутствует в Golden Image"
    # блок VLANIT-ENV (идемпотентно, маркеры совместимы с vlanit-provision).
    # ВАЖНО: блок должен быть в секции [Container] — Quadlet передаёт
    # Environment= в контейнер (--env) только оттуда; из [Service] переменная
    # остаётся окружением systemd-юнита, контейнер её не видит (дефект 1.2.4:
    # пароль веб-админа «из мастера» не доходил до MikoPBX).
    if ! grep -q "# VLANIT-ENV-BEGIN" "$quadlet"; then
        sed -i 's/^\[Container\]$/[Container]\n# VLANIT-ENV-BEGIN\n# VLANIT-ENV-END/' "$quadlet"
    fi
    # параметры контейнера из настройки устройства (issue #16):
    # /etc/vlanit/mikopbx-container.conf (STOP_TIMEOUT, PIDS_LIMIT)
    local stop_timeout=120 pids_limit=8192
    if [ -f "$SYS_MNT/etc/vlanit/mikopbx-container.conf" ]; then
        stop_timeout="$(sed -n 's/^STOP_TIMEOUT=//p' "$SYS_MNT/etc/vlanit/mikopbx-container.conf" | head -1)"
        pids_limit="$(sed -n 's/^PIDS_LIMIT=//p' "$SYS_MNT/etc/vlanit/mikopbx-container.conf" | head -1)"
    fi
    case "$stop_timeout" in ''|*[!0-9]*) stop_timeout=120 ;; esac
    case "$pids_limit"   in ''|*[!0-9]*) pids_limit=8192  ;; esac
    sed -i -E "s/^StopTimeout=.*/StopTimeout=$stop_timeout/" "$quadlet"
    sed -i -E "s/^PidsLimit=.*/PidsLimit=$pids_limit/" "$quadlet"
    python3 - "$quadlet" "$pbx_name" "$admin_login" "$admin_pass" "$tz" <<'PYEOF'
import sys
sys.path.insert(0, "/opt/vlanit/provisioning")  # live-среда: общий модуль
import vlanit_quadlet

path, name, login, passwd, tz = sys.argv[1:6]
# общая реализация блока VLANIT-ENV с vlanit-provision (ponytail #25).
# Пароль НЕ пишем в quadlet — он уезжает в Podman secret (см. Secret= в
# шаблоне); firstboot создаёт секрет из /etc/vlanit/atc-admin-password.
vlanit_quadlet.write_env_block(path, [
    ("PBX_NAME", name),
    ("WEB_ADMIN_LOGIN", login),
    # часовой пояс АТС = пояс устройства (issue #18; /etc/localtime тоже
    # проброшен в контейнер — TZ задаёт системный пояс внутри)
    ("TZ", tz),
])
PYEOF
    chmod 600 "$quadlet"
    # пароль веб-админа: root-600 файл -> Podman secret (firstboot создаст)
    install -d -m 0700 "$SYS_MNT/etc/vlanit"
    printf '%s' "$admin_pass" > "$SYS_MNT/etc/vlanit/atc-admin-password"
    chmod 600 "$SYS_MNT/etc/vlanit/atc-admin-password"
}

# chroot-операции: initramfs + загрузчик.
# $1 — (опционально) второй диск зеркала: ESP-B + UEFI-запись на него.
install_bootloader() {
    local disk_b="${1:-}"
    log "подготовка initramfs и GRUB (chroot)"
    mount_chroot_fs
    chroot "$SYS_MNT" /bin/sh -c "
        export DEBIAN_FRONTEND=noninteractive
        update-initramfs -u -k all
        grub-install --target=x86_64-efi --efi-directory=/boot/efi \
            --bootloader-id=VLANIT --recheck
        # fallback-загрузка (слабые firmware без надёжного NVRAM)
        mkdir -p /boot/efi/EFI/BOOT
        cp /boot/efi/EFI/VLANIT/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.efi
        grub-mkconfig -o /boot/grub/grub.cfg
    " || die "сбой установки загрузчика"

    if [ -n "$disk_b" ]; then
        # ESP-B: байт-в-байт копия ESP-A — диск B самодостаточен
        # (firmware грузит его при пропаже диска A). NVRAM-запись — бонус,
        # firmware без неё найдёт fallback BOOTX64.EFI.
        local esp_b
        esp_b="$(partition_device "$disk_b" 1)"
        log "ESP-B: копирование $esp_b"
        mkdir -p /mnt/vlanit-esp-b
        mount "$esp_b" /mnt/vlanit-esp-b || die "не удалось смонтировать $esp_b"
        cp -a "$SYS_MNT/boot/efi/." /mnt/vlanit-esp-b/
        chroot "$SYS_MNT" efibootmgr -c -d "$disk_b" -p 1 \
            -L "VLANIT-B" -l '\EFI\VLANIT\grubx64.efi' 2>/dev/null \
            || log "WARN: UEFI-запись для диска B не создана (fallback BOOTX64 всё равно есть)"
        umount /mnt/vlanit-esp-b
    fi
}

# chroot-окружение: bind /proc /sys /dev /run (нужны podman и grub)
mount_chroot_fs() {
    for d in proc sys dev dev/pts run; do
        mountpoint -q "$SYS_MNT/$d" 2>/dev/null && continue
        mount --rbind "/$d" "$SYS_MNT/$d" 2>/dev/null || true
    done
}

# Импорт образа MikoPBX в rootful Podman целевой системы (офлайн)
import_mikopbx_image() {
    local target_image="localhost/vlanit/mikopbx:2026.6.99-amd64"
    mkdir -p "$SYS_MNT/var/lib/vlanit/payload"
    log "копирование payload MikoPBX в целевую систему"
    cp "$PAYLOAD/mikopbx-2026.6.99-amd64.tar.zst" "$SYS_MNT/var/lib/vlanit/payload/"

    log "импорт образа MikoPBX в Podman (chroot)"
    mount_chroot_fs
    chroot "$SYS_MNT" /bin/sh -c "
        if ! podman image exists '$target_image'; then
            zstd -dc /var/lib/vlanit/payload/mikopbx-2026.6.99-amd64.tar.zst | podman load
            src_tag=\$(podman images --format '{{.Repository}}:{{.Tag}}' | grep mikopbx | head -1)
            [ -n \"\$src_tag\" ] && podman tag \"\$src_tag\" '$target_image'
        fi
        podman image exists '$target_image'
    " || die "импорт образа MikoPBX не выполнен"
}

unmount_target() {
    umount -R "$SYS_MNT" 2>/dev/null || umount -l "$SYS_MNT" 2>/dev/null || true
}

# Диагностика после установки (работает и в autoinstall)
post_install_report() {
    local disk="$1"
    log "post-install report: разметка $disk"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID "$disk" 2>/dev/null | while read -r line; do log "  $line"; done
    log "fstab целевой системы:"
    sed 's/^/  /' "$SYS_MNT/etc/fstab" 2>/dev/null | while read -r line; do log "$line"; done
    log "post-install report: конец"
}
