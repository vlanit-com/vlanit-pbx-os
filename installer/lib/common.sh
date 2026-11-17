# Общие функции VLANit Installer (источникится из vlanit-installer)
: "${DIALOG_OK:=0}" "${DIALOG_CANCEL:=1}" "${DIALOG_ESC:=255}"

ISO_MOUNT="/media/vlanit"
PAYLOAD="$ISO_MOUNT/payload"
LOG_FILE="/var/log/vlanit-install.log"

# --- фирменная тема и backtitle всех диалогов ---
# INSTALLER_DIR обычно задан vlanit-installer; при самостоятельном
# source (юнит-тесты) выводим из пути common.sh (installer/lib → installer).
: "${INSTALLER_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# DIALOGRC применяется ко всем dialog процесса (меню, gauge, msgbox).
[ -f "$INSTALLER_DIR/dialogrc" ] && export DIALOGRC="$INSTALLER_DIR/dialogrc"
# backtitle — марка + версия; устанавливается в vlanit-installer после
# чтения манифеста (до первого диалога).
DIALOG_BACKTITLE="VLANit PBX OS — установка"
# Обёртка: каждый вызов dialog получает --backtitle. Переопределение
# функцией, а не правкой ~20 вызовов: один источник (ponytail #26-правило
# о дублировании). command dialog — бинарник, рекурсии нет.
dialog() { command dialog --backtitle "$DIALOG_BACKTITLE" "$@"; }
# Корректное закрытие gauge-диалога перед показом ошибки (die).
progress_abort() {
    [ -z "${PROGRESS_GAUGE_PID:-}" ] && return 0
    exec 9>&- 2>/dev/null || true
    kill "$PROGRESS_GAUGE_PID" 2>/dev/null || true
    wait "$PROGRESS_GAUGE_PID" 2>/dev/null || true
    PROGRESS_GAUGE_PID=""
    clear 2>/dev/null || true
}

log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    # пока открыт gauge-прогресс, stdout принадлежит dialog — echo
    # только в журнал и serial (инаце мусор поверх псевдографики)
    [ -n "${PROGRESS_GAUGE_PID:-}" ] || echo "$msg"
    # дублирование на serial-консоль для диагностики и тестов
    [ -w /dev/ttyS0 ] && echo "$msg" > /dev/ttyS0 2>/dev/null || true
}

die() {
    log "ОШИБКА: $*"
    if [ -n "${AUTOMODE:-}" ]; then
        echo "VLANIT_INSTALL_FAILED: $*" > /dev/console 2>/dev/null || true
        exit 1
    fi
    progress_abort
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

# Размер root-LV в процентах от usable-диска (диск − ESP 1 ГиБ − запас
# 128 МиБ). Переопределение из autoinstall.yaml (стенд mirror, ключ
# system_size_pct) → installer.system_size_pct из payload build.yaml → 25.
# Три потребителя: минимум диска, lv_data_mib, create_storage.
installer_system_size_pct() {
    if [ -n "${SYS_SIZE_PCT_OVERRIDE:-}" ]; then
        echo "$SYS_SIZE_PCT_OVERRIDE"
        return
    fi
    yaml_get "$PAYLOAD/build.yaml" installer.system_size_pct 25
}

# root-LV (MiB) из процента usable-диска. Чистая функция (тестируется).
# installer_root_mib <usable_mib>
installer_root_mib() {
    local usable="$1" pct
    pct="$(installer_system_size_pct)"
    awk -v u="$usable" -v p="$pct" 'BEGIN {
        if (p < 1) p = 1
        if (p > 90) p = 90
        print int(u * p / 100)
    }'
}

# Минимальный размер Data-LV, ГиБ: ниже этого установщик отказывает
# в установке (проверка до деструктивных операций).
DATA_MIN_GIB=8
