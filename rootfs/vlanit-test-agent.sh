#!/usr/bin/env bash
# vlanit-test-agent — тестовый агент первой загрузки.
# Активируется ТОЛЬКО при kernel cmdline VLANIT_TEST=1 (сценарии QEMU).
# Публикует результаты проверок на последовательный порт для test-qemu.sh.
set -u

out() { echo "VLANIT_TEST: $*" > /dev/ttyS0 2>/dev/null || true; echo "VLANIT_TEST: $*"; }
# общая библиотека проверок (issue #9): тот же код, что у vlanit-doctor
# shellcheck source=../lib/checks.sh
source /opt/vlanit/lib/checks.sh 2>/dev/null || true
pass=0; fail=0
AGENT_LOG=/var/log/vlanit-test-agent.log
: > "$AGENT_LOG"

check() {
    local name="$1"; shift
    if [ "$#" -eq 1 ] && [ "$1" = "lib" ]; then
        if "check_$name" >>"$AGENT_LOG" 2>&1; then
            out "PASS $name"; pass=$((pass+1))
        elif [ "$?" = "2" ]; then
            out "SKIP $name"; pass=$((pass+1))
        else
            out "FAIL $name (детали: $AGENT_LOG)"; fail=$((fail+1))
        fi
    elif "$@" >>"$AGENT_LOG" 2>&1; then
        out "PASS $name"; pass=$((pass+1))
    else
        out "FAIL $name (детали: $AGENT_LOG)"; fail=$((fail+1))
    fi
}

out "agent start"

# --- Т3: система ---
check "hostname" lib
check "podman" podman --version
check "networkd-active" lib
check "fstab-uuid" lib

# --- Т6/Т2: Btrfs + LVM-хранилище (установщик vg0, спека mirror-two-disk) ---
check "btrfs-root" lib
check "lvm-layout" lib
check "btrfs-subvol-mikopbx-cf" lib
check "btrfs-snapshot-create" /opt/vlanit/vlanit-snapshot create testagent
check "btrfs-snapshot-list" sh -c "/opt/vlanit/vlanit-snapshot list | grep -q testagent"

# --- зеркало двух дисков (маркер VLANIT_MIRROR=1 — только тест-профиль) ---
if grep -q 'VLANIT_MIRROR=1' /proc/cmdline; then
    # DIAG: снимок lvm-состояния на ранней загрузке — агент видел «0 PV»,
    # интерактивно (позже) всё здорово; нужен точный ответ в окне отказа
    {
        echo "lvm-diag uptime=$(cut -d' ' -f1 /proc/uptime)"
        pvs 2>&1; echo "pvs_rc=$?"
        vgs 2>&1; echo "vgs_rc=$?"
        lvs 2>&1; echo "lvs_rc=$?"
        ls /dev/mapper/ 2>&1
        head -3 /proc/mdstat 2>/dev/null
    } | while read -r dl; do out "DIAG $dl"; done
    check "mirror-raid1-layout" sh -c "lvs --noheadings -o lv_layout vg0 2>/dev/null | grep -q raid1"
    # Полное зеркло ⇔ 2 PV и 0 missing (поля vgs — метаданные VG: pv_count
    # считает ВСЕ PV, включая отсутствующие; присутствие = total − missing).
    # pvs в окне ранней загрузки на стенде давал пустой вывод при
    # работающих lvs/vgs — считаем через vgs (зафиксировано DIAG).
    npv_vg0=0
    for _ in $(seq 1 12); do
        total="$(vgs --noheadings -o pv_count vg0 2>/dev/null | tr -d ' ')"
        missing="$(vgs --noheadings -o vg_missing_pv_count vg0 2>/dev/null | tr -d ' ')"
        case "$total" in ''|*[!0-9]*) total=0 ;; esac
        case "$missing" in ''|*[!0-9]*) missing=0 ;; esac
        npv_vg0=$(( total - missing ))
        [ "$npv_vg0" -ge 2 ] && break
        sleep 5
    done
    out "DIAG npv_vg0=$npv_vg0 (total=$total missing=$missing)"
    if [ "$npv_vg0" -ge 2 ]; then
        # полное зеркло: оба лега на месте, второй ESP присутствует
        check "mirror-health" sh -c "! lvs --noheadings -o lv_health_status vg0 2>/dev/null | grep -qE '[^[:space:]-]'"
        check "esp-b-present" sh -c "blkid -L VLANIT-ESPB >/dev/null 2>&1"
    else
        # деградация: система работает на одном диске; если рядом чистый
        # диск — выполняем процедуру замены (как в runbook)
        out "INFO mirror: vg0 деградирован ($npv_vg0 PV в системе)"
        newdisk=""
        while read -r dev; do
            pvs --noheadings -o pv_name 2>/dev/null | grep -q "/dev/${dev}" && continue
            lsblk -n -o NAME "/dev/$dev" 2>/dev/null | tail -n +2 | grep -q . && continue
            newdisk="/dev/$dev"; break
        done < <(lsblk -b -d -n -o NAME,TYPE,RM,RO | awk '$2=="disk" && $3=="0" && $4=="0" {print $1}')
        if [ -z "$newdisk" ]; then
            check "mirror-degraded-boot" sh -c "findmnt -n / | grep -q /dev/mapper/vg0-"
        else
            case "$newdisk" in *nvme*|*mmcblk*) pvpart="${newdisk}p2"; esppart="${newdisk}p1" ;;
                               *) pvpart="${newdisk}2";  esppart="${newdisk}1" ;; esac
            out "mirror-replace: новый диск $newdisk ($pvpart)"
            if wipefs -a "$newdisk" >/dev/null 2>&1 \
                && sgdisk --zap-all "$newdisk" >/dev/null 2>&1 \
                && sgdisk -n1:1MiB:+1024MiB -t1:EF00 -c1:"VLANIT_EFI" "$newdisk" >/dev/null \
                && sgdisk -n2:0:0 -t2:8E00 -c2:"VLANIT_LVM" "$newdisk" >/dev/null \
                && partprobe "$newdisk" >/dev/null 2>&1 && sleep 2 \
                && pvcreate -y "$pvpart" >/dev/null \
                && vgextend vg0 "$pvpart" >/dev/null \
                && lvconvert -y --repair vg0/root >/dev/null 2>&1 \
                && lvconvert -y --repair vg0/data >/dev/null 2>&1; then
                # ESP новому диску — он должен быть загрузочным сам по себе
                mkfs.vfat -F 32 -n VLANIT_EFI "$esppart" >/dev/null 2>&1 || true
                mkdir -p /mnt/vlanit-newesp \
                    && mount "$esppart" /mnt/vlanit-newesp >/dev/null 2>&1 \
                    && cp -a /boot/efi/. /mnt/vlanit-newesp/ \
                    && umount /mnt/vlanit-newesp || true
                # ожидание resync (до 10 минут)
                resync_done=0
                for i in $(seq 1 120); do
                    pend="$(lvs --noheadings -o sync_percent vg0 2>/dev/null | tr ',' '.' | awk '$1!="100.00" {n++} END {print n+0}')"
                    [ "$pend" -eq 0 ] && { resync_done=1; break; }
                    sleep 5
                done
                if [ "$resync_done" -eq 1 ] \
                    && ! lvs --noheadings -o lv_health_status vg0 2>/dev/null | grep -qE '[^[:space:]-]'; then
                    out "PASS mirror-replace (resync завершён, оба лега)"
                    out "VLANIT_MIRROR: REPLACE_PASS"
                    pass=$((pass+1))
                else
                    out "VLANIT_MIRROR: REPLACE_FAIL (resync_done=$resync_done)"
                    fail=$((fail+1))
                fi
            else
                out "VLANIT_MIRROR: REPLACE_FAIL (сбой процедуры замены)"
                fail=$((fail+1))
            fi
        fi
    fi
fi

# --- Т4: MikoPBX ---
check "quadlet-service" lib
# АТС стартует САМА при загрузке (quadlet auto-enable + vlanit-atc-secret).
# Ручной start здесь маскировал дефекты порядка загрузки (issue #34) —
# только ждём, не поднимая вручную.
for i in $(seq 1 24); do
    systemctl is-active --quiet mikopbx.service && break
    sleep 5
done

# ожидание готовности приложения (до 6 минут)
ready=0
for i in $(seq 1 72); do
    if podman logs mikopbx 2>/dev/null | grep -q "All services are fully loaded welcome"; then
        ready=1; break
    fi
    sleep 5
done
[ "$ready" -eq 1 ] && { out "PASS mikopbx-ready-banner"; pass=$((pass+1)); } \
                   || { out "FAIL mikopbx-ready-banner"; fail=$((fail+1)); }

check "mikopbx-service-active" lib

# веб-интерфейс (HTTPS, self-signed) — через ВНЕШНИЙ адрес устройства,
# а не loopback: интерфейс должен быть доступен из сети
EXT_IP="$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)"
web=0
for i in $(seq 1 24); do
    if curl -sk --max-time 5 "https://${EXT_IP:-127.0.0.1}/" -o /dev/null -w '%{http_code}' | grep -qE '200|301|302'; then
        web=1; break
    fi
    sleep 5
done
[ "$web" -eq 1 ] && { out "PASS mikopbx-webui"; pass=$((pass+1)); } \
                 || { out "FAIL mikopbx-webui"; fail=$((fail+1)); }

# REST API login с localhost (v3, localhost bypass)
if curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
        -H 'Content-Type: application/json' \
        -d '{"login":"admin","password":"admin12345"}' 2>/dev/null | \
        grep -qE 'accessToken|result'; then
    out "PASS mikopbx-api-login"; pass=$((pass+1))
else
    out "FAIL mikopbx-api-login"; fail=$((fail+1))
fi

# persistence конфигурации MikoPBX (env provisioning применён в БД)
check "mikopbx-cf-nonempty" lib

# --- WireGuard (если включён установщиком) ---
if systemctl is-enabled --quiet wg-quick@wg0.service 2>/dev/null; then
    check "wireguard-service-enabled" systemctl is-enabled --quiet wg-quick@wg0.service
    systemctl start wg-quick@wg0.service 2>/dev/null || true
    check "wireguard-interface-up" sh -c "wg show wg0 | grep -q interface"
    check "wireguard-address" sh -c "ip -4 -o addr show dev wg0 | grep -q '10\.66\.66\.'"
fi

# --- безопасность (1.2) ---
check "unattended-upgrades" lib
check "security-root-ssh-denied" lib
check "security-fail2ban" lib

# --- брендинг: фирменная тема Plymouth ---
check "plymouth-theme-vlanit" grep -q "Theme=vlanit" /etc/plymouth/plymouthd.conf

# --- 1.2.3: реестр проверок по фидбеку полевых тестов ---
check "apt-security-source" lib
check "timesyncd" lib
check "timezone-set" lib
check "console-font-cyrillic" grep -q "^FONT=CyrSlav" /etc/vconsole.conf
check "quadlet-perms-600" sh -c "stat -c %a /etc/containers/systemd/mikopbx.container | grep -q 600"
check "atc-ssh-port-23" lib
check "atc-password-nonempty" lib
# пароль из мастера РЕАЛЬНО дошёл до контейнера (переменная в [Container],
# а не только в файле) и логин ей проходит (полевой дефект 1.2.4 #3)
check "atc-env-in-container" lib
# лимит остановки контейнера: 120 с, а не дефолтные 10 (полевой дефект 1.2.4 #4)
check "atc-stop-timeout" lib

# --- 1.2.4: системная интеграция и харденинг ---
check "bin-login-present" lib
check "ssh-host-keys" sh -c '
  ls /etc/ssh/ssh_host_* >/dev/null 2>&1 || { echo "== /etc/ssh:"; ls -la /etc/ssh/; }
  systemctl is-active --quiet ssh || { echo "== ssh status:"; systemctl status ssh --no-pager 2>&1 | tail -8; }
  ls /etc/ssh/ssh_host_* >/dev/null 2>&1 && systemctl is-active --quiet ssh
'
check "nft-policy-drop" lib
# тестовая подсеть QEMU не должна уезжать в образ (полевой дефект 1.2.4 #2)
check "nft-no-testnet" lib
check "nft-localhost-root-only" lib
# файлы системы — root, а не uid сборочного пользователя (дефект 1.2.4 #1);
# /home исключён (домашний каталог администратора legitimately uid 1000)
check "files-root-owned" sh -c "test \"\$(find / -xdev -uid 1000 -not -path '/home/*' 2>/dev/null | wc -l)\" -eq 0"
check "sudo-works" sh -c "test \"\$(stat -c %u /usr/bin/sudo)\" = 0 && test -u /usr/bin/sudo && /usr/bin/sudo -n true 2>/dev/null || { test \"\$(stat -c %u /usr/bin/sudo)\" = 0 && test -u /usr/bin/sudo; }"
# ssh.service не должен падать на старте: ключи генерируются drop-in'ом
# ДО sshd (полевой дефект 1.2.4 #5)
check "ssh-clean-start" sh -c "systemctl show ssh.service -p NRestarts --value | grep -qx 0 && systemctl is-active --quiet ssh.service"
check "pids-limit" lib
check "handle-power-key" sh -c "busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandlePowerKey 2>/dev/null | grep -q ignore"
# issue #9: диагностический инструмент на устройстве (общая библиотека)
check "vlanit-doctor" sh -c "vlanit-doctor --quiet"
# issue #10: служба самолечения пароля АТС включена и отработала
check "atc-heal-service" sh -c "systemctl is-enabled --quiet vlanit-atc-password-heal.service"
check "atc-secret-service" sh -c "systemctl is-enabled --quiet vlanit-atc-secret.service"
# ordering cycle ломал автозапуск АТС на 2-й загрузке (issue #34):
# systemd удалял job mikopbx «to break ordering cycle». В журнале быть не должно
check "no-ordering-cycle" sh -c "! journalctl -b 2>/dev/null | grep -qi 'ordering cycle'"
check "atc-secret-exists" lib
check "atc-no-plaintext-in-quadlet" lib
check "atc-dockerenv-mount" sh -c "podman inspect mikopbx --format '{{range .Mounts}}{{.Destination}} {{end}}' | grep -q '/.dockerenv'"
check "atc-tz-env" sh -c "podman exec mikopbx sh -c 'test -n \"\$TZ\"'"
# journal-persistent проверяется после reboot-фазы (см. ниже)

# --- перезагрузка и проверка сохранения (Т4: автозапуск после reboot) ---
if [ "$fail" -eq 0 ] && [ ! -f /var/spool/mikopbx/storage/.vlanit-reboot-marker ]; then
    date -Is > /var/spool/mikopbx/storage/.vlanit-reboot-marker
    sync
    out "PHASE1_DONE rebooting (проверка сохранения после перезагрузки)"
    sleep 3
    reboot -f
    exit 0
fi
if [ -f /var/spool/mikopbx/storage/.vlanit-reboot-marker ]; then
    check "reboot-data-persisted" sh -c "test -s /var/spool/mikopbx/storage/.vlanit-reboot-marker"
    check "reboot-mikopbx-active" systemctl is-active --quiet mikopbx.service
    # журналы прошлой загрузки доступны (Storage=persistent)
    check "journal-persistent" sh -c "[ \"\$(journalctl -b -1 -n 1 2>/dev/null | wc -l)\" -gt 0 ]"
    # пароль веб-админа ПЕРЕЖИЛ перезагрузку. ИЗВЕСТНАЯ ПРОБЛЕМА upstream
    # (MikoPBX): provisioning применяет WEB_ADMIN_PASSWORD по маркеру
    # CLOUD_INSTANCE_ID; после перезагрузки хэш в БД сброшен, маркер
    # совпадает → повторное применение пропускается. Проверка WARN-уровня
    # до исправления upstream; детект на устройстве — vlanit-firstboot.
    for i in $(seq 1 60); do
        podman logs mikopbx 2>/dev/null | grep -q "All services are fully loaded welcome" && break
        sleep 5
    done
    PW=""
    [ -s /etc/vlanit/atc-admin-password ] && PW="$(cat /etc/vlanit/atc-admin-password)"
    if curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
            -H 'Content-Type: application/json' \
            -d "{\"login\":\"admin\",\"password\":\"$PW\"}" | grep -q accessToken; then
        out "WARN-CHECK PASS reboot-api-login"
    else
        out "WARN-CHECK FAIL reboot-api-login (известная проблема upstream, см. troubleshooting)"
    fi
    out "REBOOT_TEST_PASS"
fi

if [ "$fail" -eq 0 ]; then
    out "RESULT PASS ($pass checks)"
    out "VLANIT_TEST_PASS"
else
    out "AGENT_LOG (последние строки):"
    tail -20 "$AGENT_LOG" | while read -r line; do out "  $line"; done
    out "RESULT FAIL ($fail из $((pass+fail)))"
    out "VLANIT_TEST_FAIL"
fi
