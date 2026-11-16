# Общие функции VLANit Installer (источникится из vlanit-installer)
: "${DIALOG_OK:=0}" "${DIALOG_CANCEL:=1}" "${DIALOG_ESC:=255}"

ISO_MOUNT="/media/vlanit"
PAYLOAD="$ISO_MOUNT/payload"
LOG_FILE="/var/log/vlanit-install.log"

log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    echo "$msg"
    # дублирование на serial-консоль для диагностики и тестов
    [ -w /dev/ttyS0 ] && echo "$msg" > /dev/ttyS0 2>/dev/null || true
}

die() {
    log "ОШИБКА: $*"
    if [ -n "${AUTOMODE:-}" ]; then
        echo "VLANIT_INSTALL_FAILED: $*" > /dev/console 2>/dev/null || true
        exit 1
    fi
    dialog --title "Ошибка установки" --msgbox "$*\n\nЖурнал: $LOG_FILE" 12 70 || true
    exit 1
}

# чтение простого значения из YAML через python3+yaml
yaml_get() {
    # yaml_get <file> <dotted.path> [default]
    python3 - "$1" "$2" "${3:-}" <<'PYEOF'
import sys, yaml
path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = yaml.safe_load(open(path))
except Exception as e:
    print(default); sys.exit(0)
cur = data
for part in key.split("."):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print(default); sys.exit(0)
print("" if cur is None else cur)
PYEOF
}

human_gb() {
    awk -v bytes="$1" 'BEGIN { printf "%.1f", bytes/1024/1024/1024 }'
}

# Размер root-LV (MiB): переопределение из autoinstall.yaml (стенд mirror,
# ключ system_size_mib) → installer.system_size_mib из payload build.yaml
# → 40960. Три потребителя: минимум диска, lv_data_mib, create_storage.
installer_system_size_mib() {
    if [ -n "${SYS_SIZE_MIB_OVERRIDE:-}" ]; then
        echo "$SYS_SIZE_MIB_OVERRIDE"
        return
    fi
    yaml_get "$PAYLOAD/build.yaml" installer.system_size_mib 40960
}
