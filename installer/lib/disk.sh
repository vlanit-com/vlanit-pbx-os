# Операции с дисками: обнаружение (с защитными проверками) и разметка.
# Никаких фиксированных /dev/sda — всё определяется динамически.

# Устройство, с которого загружена Live-среда (установочный USB/ISO)
live_source_device() {
    local src
    src="$(findmnt -n -o SOURCE "$ISO_MOUNT" 2>/dev/null || true)"
    # /dev/sr0 напрямую; для /dev/mapper/* берём родителя не требуется
    echo "$src"
}

# Список кандидатов: внутренние непереносные диски, не занятые системой
list_candidate_disks() {
    local src
    src="$(live_source_device)"
    lsblk -b -d -n -o NAME,TYPE,RM,RO,SIZE,MODEL,TRAN 2>/dev/null | \
    awk -v src="$src" '
        $2 == "disk" && $3 == "0" && $4 == "0" {
            dev = "/dev/" $1
            if (dev == src || src ~ ("^" dev "[0-9p]")) next
            printf "%s|%s|%s|%s\n", dev, $5, $7, $6
        }'
}

# Защита: диск не должен иметь смонтированных разделов
disk_is_clean_target() {
    local disk="$1"
    findmnt -S "$disk" >/dev/null 2>&1 && return 1
    lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -q '[^[:space:]]' && return 1
    return 0
}

disk_size_bytes() {
    blockdev --getsize64 "$1" 2>/dev/null || lsblk -b -n -o SIZE "$1"
}

# Разметка GPT: EFI 1GiB (ESP) + остаток под LVM PV.
# System/Data — это LV vg0 (см. deploy.sh), а не разделы.
# Вызывается ТОЛЬКО после явного подтверждения пользователя.
partition_disk() {
    local disk="$1"

    log "разметка $disk (GPT): EFI 1024MiB, LVM PV — остаток"
    wipefs -a "$disk"
    sgdisk --zap-all "$disk"
    sgdisk -n1:1MiB:+1024MiB -t1:EF00 -c1:"VLANIT_EFI" "$disk"
    sgdisk -n2:0:0 -t2:8E00 -c2:"VLANIT_LVM" "$disk"
    sgdisk -p "$disk"
    partprobe "$disk" || true
    sleep 1
    udevadm settle 2>/dev/null || true
}

# Usable-диска (MiB): диск без ESP 1024 и запаса метаданных 128.
# usable_mib <disk_bytes> [disk_bytes...]
usable_mib() {
    local min_bytes="$1" b
    for b in "$@"; do
        [ "$b" -lt "$min_bytes" ] && min_bytes="$b"
    done
    awk -v bytes="$min_bytes" 'BEGIN { print int(bytes / 1024 / 1024) - 1024 - 128 }'
}

# Расчёт размера LV data (MiB): usable по меньшему диску зеркала минус
# root-LV (процент от usable). Чистая функция (тестируется).
# lv_data_mib <disk_bytes> [disk_bytes...]
lv_data_mib() {
    local usable sys_mib
    usable="$(usable_mib "$@")"
    sys_mib="$(installer_root_mib "$usable")"
    awk -v u="$usable" -v sys="$sys_mib" 'BEGIN { print u - sys }'
}

# Определение имён разделов: nvme0n1p1 vs sda1
partition_device() {
    local disk="$1" num="$2"
    case "$disk" in
        *nvme*|*mmcblk*) echo "${disk}p${num}" ;;
        *) echo "${disk}${num}" ;;
    esac
}
