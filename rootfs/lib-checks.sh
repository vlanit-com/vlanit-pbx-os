#!/usr/bin/env bash
# /opt/vlanit/lib/checks.sh — общая библиотека диагностических проверок
# VLANit PBX OS (issue #9). Единый источник правды: используют
# vlanit-test-agent (QEMU-регрессия, протокол на ttyS0) и vlanit-doctor
# (полевой диагностический инструмент на установленном устройстве).
#
# Контракт:
#   check_<name>() -> 0 = OK, 1 = FAIL, 2 = SKIP (не применимо)
#   hint_<name>()  -> строка подсказки исправления (для --fix-hints)
#   desc_<name>()  -> короткое описание проверки
#   CHECK_GROUPS: карта group -> список имён проверок (порядок вывода)
#
# Безопасность: проверки read-only, секреты не выводятся.

# --- группы (для отчёта) ---
CHECK_GROUPS=(
    "system:hostname timezone-set timesyncd apt-security-source unattended-upgrades"
    "disks:btrfs-root btrfs-subvol-mikopbx-cf fstab-uuid btrfs-snapshot-list disk-space lvm-layout lvm-mirror-health"
    "network:networkd-active network-address dns-resolve wireguard-active"
    "firewall:nft-active nft-policy-drop nft-no-testnet nft-localhost-root-only ports-listening"
    "ssh:ssh-host-keys ssh-service-active security-root-ssh-denied security-fail2ban bin-login-present"
    "mikopbx:quadlet-service mikopbx-service-active mikopbx-image-version mikopbx-cf-nonempty atc-ssh-port-23 atc-password-nonempty atc-secret-exists atc-no-plaintext-in-quadlet atc-env-in-container atc-stop-timeout pids-limit mikopbx-webui mikopbx-api-login"
    "logs:journal-persistent journal-last-boot"
    "updates:apt-upgradable pre-update-snapshot"
)

# ============ system ============
desc_hostname() { echo "hostname задан (vlanit)"; }
check_hostname() { hostname | grep -q vlanit; }
hint_hostname() { echo "hostnamectl set-hostname vlanit-pbx-001"; }

desc_timezone-set() { echo "часовой пояс задан (/etc/timezone)"; }
check_timezone-set() { [ -s /etc/timezone ]; }
hint_timezone-set() { echo "timedatectl set-timezone Europe/Moscow"; }

desc_timesyncd() { echo "синхронизация времени (timesyncd)"; }
check_timesyncd() { systemctl is-active --quiet systemd-timesyncd; }
hint_timesyncd() { echo "systemctl enable --now systemd-timesyncd"; }

desc_apt-security-source() { echo "apt: security-источник подключён"; }
check_apt-security-source() { grep -rh trixie-security /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -q .; }
hint_apt-security-source() { echo "проверьте /etc/apt/sources.list.d/"; }

desc_unattended-upgrades() { echo "автообновления безопасности включены"; }
check_unattended-upgrades() { unattended-upgrades --dry-run >/dev/null 2>&1 || unattended-upgrades --dry-run -d >/dev/null 2>&1; }
hint_unattended-upgrades() { echo "dpkg-reconfigure unattended-upgrades"; }

# ============ disks ============
desc_btrfs-root() { echo "корень на Btrfs"; }
check_btrfs-root() { findmnt -n / | grep -q btrfs; }
hint_btrfs-root() { echo "findmnt /"; }

desc_btrfs-subvol-mikopbx-cf() { echo "данные АТС на Btrfs-subvolume"; }
check_btrfs-subvol-mikopbx-cf() { findmnt -n /var/spool/mikopbx/cf | grep -q btrfs; }
hint_btrfs-subvol-mikopbx-cf() { echo "findmnt /var/spool/mikopbx/cf"; }

desc_fstab-uuid() { echo "fstab по UUID"; }
check_fstab-uuid() { grep -q 'UUID=.*btrfs' /etc/fstab; }
hint_fstab-uuid() { echo "проверьте /etc/fstab"; }

desc_btrfs-snapshot-list() { echo "снапшоты доступны (vlanit-snapshot list)"; }
check_btrfs-snapshot-list() { /opt/vlanit/vlanit-snapshot list >/dev/null 2>&1; }
hint_btrfs-snapshot-list() { echo "/opt/vlanit/vlanit-snapshot list"; }

# LVM-схема vg0 (root/data поверх LV; спека mirror-two-disk).
# Legacy-системы (Btrfs прямо на разделах, до LVM) — валидны: SKIP.
desc_lvm-layout() { echo "хранилище на LVM (vg0/root, vg0/data)"; }
check_lvm-layout() {
    if findmnt -n -o SOURCE / | grep -q "^/dev/mapper/${VG_NAME:-vg0}-"; then
        lvs --noheadings -o lv_name "${VG_NAME:-vg0}" 2>/dev/null | grep -qx root \
            && lvs --noheadings -o lv_name "${VG_NAME:-vg0}" 2>/dev/null | grep -qx data
        return
    fi
    findmnt -n -o FSTYPE / 2>/dev/null | grep -q btrfs && return 2
    return 1
}
hint_lvm-layout() { echo "lvs; findmnt / (источник должен быть /dev/mapper/vg0-root)"; }

# Здоровье зеркала: только для raid1-LV (два диска). Linear/без vg0 — SKIP.
desc_lvm-mirror-health() { echo "LVM-зеркало целостно (оба лега raid1)"; }
check_lvm-mirror-health() {
    command -v lvs >/dev/null 2>&1 || return 2
    lvs "${VG_NAME:-vg0}" >/dev/null 2>&1 || return 2
    lvs --noheadings -o lv_layout "${VG_NAME:-vg0}" 2>/dev/null | grep -q raid1 || return 2
    # health_status непустой и не "-" — деградация (partial и т.п.)
    ! lvs --noheadings -o lv_health_status "${VG_NAME:-vg0}" 2>/dev/null \
        | grep -qE '[^[:space:]-]'
}
hint_lvm-mirror-health() { echo "lvs -a -o +health_status; при умершем диске — runbook «Замена диска» (wiki)"; }

desc_disk-space() { echo "свободное место System и Data (>10%)"; }
check_disk-space() {
    local ok=0 p
    for mnt in / /var/spool/mikopbx/cf; do
        p=$(df --output=pcent "$mnt" 2>/dev/null | tail -1 | tr -dc '0-9')
        [ -z "$p" ] && return 2
        [ "$p" -gt 90 ] && ok=1
    done
    return $ok
}
hint_disk-space() { echo "df -h; очистите записи разговоров/снапшоты"; }

# ============ network ============
desc_networkd-active() { echo "systemd-networkd активен"; }
check_networkd-active() { systemctl is-active --quiet systemd-networkd; }
hint_networkd-active() { echo "systemctl status systemd-networkd"; }

desc_network-address() { echo "IP-адрес получен"; }
check_network-address() { ip -4 -o addr show scope global | grep -q .; }
hint_network-address() { echo "ip a; проверьте DHCP/статический адрес"; }

desc_dns-resolve() { echo "DNS резолвит deb.debian.org"; }
check_dns-resolve() { getent hosts deb.debian.org >/dev/null 2>&1; }
hint_dns-resolve() { echo "resolvectl status; проверьте DNS-серверы"; }

desc_wireguard-active() { echo "WireGuard (если включён): интерфейс поднят"; }
check_wireguard-active() {
    if ! systemctl is-enabled --quiet wg-quick@wg0.service 2>/dev/null; then
        return 2   # не включён — не применимо
    fi
    ip -4 -o addr show dev wg0 >/dev/null 2>&1
}
hint_wireguard-active() { echo "systemctl status wg-quick@wg0; wg show"; }

# ============ firewall ============
desc_nft-active() { echo "nftables активен"; }
check_nft-active() { systemctl is-active --quiet nftables 2>/dev/null || nft list ruleset >/dev/null 2>&1; }
hint_nft-active() { echo "systemctl enable --now nftables"; }

desc_nft-policy-drop() { echo "политика input: default drop"; }
check_nft-policy-drop() { nft list ruleset 2>/dev/null | grep -q 'policy drop'; }
hint_nft-policy-drop() { echo "nft -f /etc/nftables.conf"; }

desc_nft-localhost-root-only() { echo "API АТС с loopback — только root (skuid)"; }
check_nft-localhost-root-only() {
    nft list ruleset 2>/dev/null | grep -q 'skuid != 0'
}
hint_nft-localhost-root-only() { echo "проверьте /etc/nftables.conf (meta skuid != 0 drop)"; }

desc_nft-no-testnet() { echo "нет тестовой подсети 10.0.2.0/24 в правилах"; }
check_nft-no-testnet() { ! nft list ruleset 2>/dev/null | grep -q '10\.0\.2\.0/24'; }
hint_nft-no-testnet() { echo "проверьте /etc/nftables.conf"; }

desc_ports-listening() { echo "ожидаемые порты слушаются (443 tcp, 5060 udp)"; }
check_ports-listening() {
    ss -ltnH "sport = :443" 2>/dev/null | grep -q . || return 1
    ss -lunH "sport = :5060" 2>/dev/null | grep -q .
}
hint_ports-listening() { echo "ss -tlnp; systemctl status mikopbx"; }

# ============ ssh ============
desc_ssh-host-keys() { echo "SSH host keys сгенерированы"; }
check_ssh-host-keys() { ls /etc/ssh/ssh_host_* >/dev/null 2>&1; }
hint_ssh-host-keys() { echo "ssh-keygen -A && systemctl restart ssh"; }

desc_ssh-service-active() { echo "ssh.service активен"; }
check_ssh-service-active() {
    systemctl is-enabled --quiet ssh.service 2>/dev/null || return 2  # выключен намеренно
    systemctl is-active --quiet ssh.service
}
hint_ssh-service-active() { echo "journalctl -u ssh -b"; }

desc_security-root-ssh-denied() { echo "root по SSH запрещён"; }
check_security-root-ssh-denied() { sshd -T 2>/dev/null | grep -qi '^permitrootlogin no' || grep -rqi '^PermitRootLogin no' /etc/ssh/sshd_config.d/ 2>/dev/null; }
hint_security-root-ssh-denied() { echo "PermitRootLogin no в sshd_config.d"; }

desc_security-fail2ban() { echo "fail2ban активен (sshd jail)"; }
check_security-fail2ban() { systemctl is-active --quiet fail2ban && fail2ban-client status sshd >/dev/null 2>&1; }
hint_security-fail2ban() { echo "systemctl status fail2ban"; }

desc_bin-login-present() { echo "консольный login присутствует"; }
check_bin-login-present() { test -x /usr/bin/login; }
hint_bin-login-present() { echo "apt install login"; }

# ============ mikopbx ============
desc_quadlet-service() { echo "quadlet mikopbx.service включён"; }
check_quadlet-service() { systemctl is-enabled --quiet mikopbx.service; }
hint_quadlet-service() { echo "systemctl enable mikopbx.service"; }

desc_mikopbx-service-active() { echo "quadlet mikopbx.service активен"; }
check_mikopbx-service-active() { systemctl is-active --quiet mikopbx.service; }
hint_mikopbx-service-active() { echo "systemctl start mikopbx.service; journalctl -u mikopbx -b"; }

desc_mikopbx-image-version() { echo "образ MikoPBX присутствует (localhost/vlanit)"; }
check_mikopbx-image-version() { podman images --format '{{.Repository}}' 2>/dev/null | grep -q 'localhost/vlanit/mikopbx'; }
hint_mikopbx-image-version() { echo "podman images; импорт из /var/lib/vlanit/payload"; }

desc_mikopbx-cf-nonempty() { echo "конфигурация MikoPBX создана (/cf не пуст)"; }
check_mikopbx-cf-nonempty() { test -n "$(ls -A /var/spool/mikopbx/cf 2>/dev/null)"; }
hint_mikopbx-cf-nonempty() { echo "контейнер ещё не инициализировался — подождите"; }

desc_atc-ssh-port-23() { echo "SSH АТС на порту 23"; }
check_atc-ssh-port-23() { podman exec mikopbx sh -c 'test "$SSH_PORT" = 23' 2>/dev/null; }
hint_atc-ssh-port-23() { echo "проверьте Environment=SSH_PORT в quadlet"; }

desc_atc-password-nonempty() { echo "пароль веб-админа АТС задан (root-600 файл)"; }
check_atc-password-nonempty() {
    [ -s /etc/vlanit/atc-admin-password ] || return 1
    [ "$(stat -c %a /etc/vlanit/atc-admin-password)" = "600" ]
}
hint_atc-password-nonempty() { echo "файл создаёт установщик; см. troubleshooting"; }

desc_atc-secret-exists() { echo "Podman secret atc-admin-password создан"; }
check_atc-secret-exists() { podman secret exists atc-admin-password 2>/dev/null; }
hint_atc-secret-exists() { echo "podman secret create atc-admin-password /etc/vlanit/atc-admin-password"; }

desc_atc-no-plaintext-in-quadlet() { echo "пароля открытым текстом нет в quadlet"; }
check_atc-no-plaintext-in-quadlet() { ! grep -q 'WEB_ADMIN_PASSWORD=' /etc/containers/systemd/mikopbx.container 2>/dev/null; }
hint_atc-no-plaintext-in-quadlet() { echo "пароль должен быть в Podman secret, не в юните"; }

desc_atc-env-in-container() { echo "env мастера дошли до контейнера"; }
check_atc-env-in-container() { podman exec mikopbx sh -c 'env | grep -q ^WEB_ADMIN_PASSWORD=' 2>/dev/null; }
hint_atc-env-in-container() { echo "блок VLANIT-ENV должен быть в [Container] quadlet"; }

desc_atc-stop-timeout() { echo "лимит остановки контейнера из настройки"; }
check_atc-stop-timeout() {
    local want
    want="$(sed -n 's/^StopTimeout=//p' /etc/containers/systemd/mikopbx.container 2>/dev/null | head -1)"
    [ -n "$want" ] || return 2
    podman inspect mikopbx --format '{{.Config.StopTimeout}}' 2>/dev/null | grep -qx "$want"
}
hint_atc-stop-timeout() { echo "/etc/vlanit/mikopbx-container.conf + restart"; }

desc_pids-limit() { echo "PidsLimit контейнера из настройки"; }
check_pids-limit() {
    local want
    want="$(sed -n 's/^PidsLimit=//p' /etc/containers/systemd/mikopbx.container 2>/dev/null | head -1)"
    [ -n "$want" ] || return 2
    podman inspect mikopbx --format '{{.HostConfig.PidsLimit}}' 2>/dev/null | grep -qx "$want"
}
hint_pids-limit() { echo "/etc/vlanit/mikopbx-container.conf + restart"; }

desc_mikopbx-webui() { echo "веб-интерфейс отвечает (HTTPS, внешний адрес)"; }
check_mikopbx-webui() {
    local ip
    ip="$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)"
    curl -sk --max-time 5 "https://${ip:-127.0.0.1}/" -o /dev/null -w '%{http_code}' 2>/dev/null | grep -qE '200|301|302'
}
hint_mikopbx-webui() { echo "podman logs mikopbx | tail; curl -k https://<ip>/"; }

desc_mikopbx-api-login() { echo "API-логин паролем из quadlet (localhost)"; }
check_mikopbx-api-login() {
    local pw=""
    [ -s /etc/vlanit/atc-admin-password ] && pw="$(cat /etc/vlanit/atc-admin-password)"
    [ -n "$pw" ] || return 2
    # известный upstream-баг (#10): после reboot хэш может быть сброшен —
    # FAIL трактуется как известная проблема (см. troubleshooting)
    curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
        -H 'Content-Type: application/json' \
        -d "{\"login\":\"admin\",\"password\":\"$pw\"}" 2>/dev/null | grep -q accessToken
}
hint_mikopbx-api-login() { echo "известный upstream-баг #10; см. docs/troubleshooting.md"; }

# ============ logs ============
desc_journal-persistent() { echo "journald persistent (логи переживают reboot)"; }
check_journal-persistent() {
    local boots
    boots=$(journalctl --list-boots 2>/dev/null | grep -cE '^\s*-?[0-9]+')
    [ "${boots:-0}" -lt 2 ] && return 2   # первая загрузка — прошлых журналов нет
    [ "$(journalctl -b -1 -n 1 2>/dev/null | wc -l)" -gt 0 ]
}
hint_journal-persistent() { echo "Storage=persistent в /etc/systemd/journald.conf"; }

desc_journal-last-boot() { echo "journald пишет журналы текущей загрузки"; }
check_journal-last-boot() { [ "$(journalctl -b -n 1 2>/dev/null | wc -l)" -gt 0 ]; }
hint_journal-last-boot() { echo "systemctl status systemd-journald"; }

# ============ updates ============
desc_apt-upgradable() { echo "нет ожидающих security-обновлений"; }
check_apt-upgradable() {
    # требует свежего индекса; при отсутствии сети — SKIP
    if ! getent hosts deb.debian.org >/dev/null 2>&1; then return 2; fi
    apt-get update -qq >/dev/null 2>&1
    [ "$(apt list --upgradable 2>/dev/null | grep -c security)" -eq 0 ]
}
hint_apt-upgradable() { echo "apt-get upgrade; unattended-upgrades"; }

desc_pre-update-snapshot() { echo "есть pre-update снапшот (откат)"; }
check_pre-update-snapshot() {
    # норма: снапшот создаётся ПЕРЕД обновлением (vlanit-update). На свежей
    # системе без обновлений его нет — это SKIP, а не FAIL
    /opt/vlanit/vlanit-snapshot list 2>/dev/null | grep -q 'pre-update' || return 2
}
hint_pre-update-snapshot() { echo "/opt/vlanit/vlanit-snapshot create manual"; }
