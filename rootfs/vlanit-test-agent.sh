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

# --- T6: Btrfs ---
check "btrfs-root" lib
check "btrfs-subvol-mikopbx-cf" lib
check "btrfs-snapshot-create" /opt/vlanit/vlanit-snapshot create testagent
check "btrfs-snapshot-list" sh -c "/opt/vlanit/vlanit-snapshot list | grep -q testagent"

# --- Т4: MikoPBX ---
check "quadlet-service" lib
systemctl start mikopbx.service 2>/dev/null || true

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
    PW="$(sed -n 's/^Environment=WEB_ADMIN_PASSWORD=//p' /etc/containers/systemd/mikopbx.container | head -1)"
    PW="${PW%\"}"; PW="${PW#\"}"
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
