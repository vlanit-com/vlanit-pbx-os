#!/usr/bin/env bash
# scripts/10-golden-rootfs.sh — сборка Golden Image (устанавливаемой Debian 13).
# Выполняется внутри build-контейнера от root.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
ROOTFS="$BUILD_DIR/rootfs/golden"
PAYLOAD="$BUILD_DIR/payload"
mkdir -p "$ROOTFS" "$PAYLOAD"
rm -rf "${ROOTFS:?}"/*   # чистый старт шага

log() { printf '[golden] %s\n' "$*"; }

# --- пакеты целевой системы (без рекомендаций, минимальный набор) ---
GOLDEN_PACKAGES="
systemd-sysv dbus udev
linux-image-amd64 initramfs-tools busybox-static
grub-efi-amd64 grub-pc-bin grub-common
podman crun golang-github-containers-common systemd-resolved
btrfs-progs dosfstools e2fsprogs lvm2 gdisk efibootmgr
openssh-server sudo login
curl ca-certificates jq zstd
python3 python3-minimal python3-yaml
netsurf-fb netsurf-common
tzdata kbd
iproute2 iputils-ping ethtool pciutils usbutils smartmontools nvme-cli dmidecode
iptables nftables
wireguard-tools
logrotate
unattended-upgrades fail2ban
plymouth plymouth-themes
systemd-timesyncd console-setup
"

log "mmdebstrap: Debian 13 (trixie) minimal rootfs"
mmdebstrap \
    --mode=root \
    --variant=apt \
    --architectures=amd64 \
    --aptopt='APT::Install-Recommends "false"' \
    --components="main contrib non-free-firmware" \
    --include="$GOLDEN_PACKAGES" \
    trixie "$ROOTFS" http://deb.debian.org/debian

# security/updates-источники (mmdebstrap пишет только базовый сьют) —
# ДО full-upgrade, иначе security-апгрейды (в т.ч. ядро) не подтягиваются
log "apt sources: trixie + updates + security"
cat > "$ROOTFS/etc/apt/sources.list.d/debian.list" <<'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free-firmware
deb http://deb.debian.org/debian-security trixie-security main contrib non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free-firmware
EOF
rm -f "$ROOTFS/etc/apt/sources.list"

# все пакеты — последних версий (security/updates на момент сборки)
# mmdebstrap очищает resolv.conf — без него apt в chroot не резолвит
# (в rootfs это висячий symlink /run/systemd/resolve/... — cp не пишет через него)
rm -f "$ROOTFS/etc/resolv.conf"
cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
log "apt full-upgrade"
chroot "$ROOTFS" sh -c '
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq full-upgrade
'
# гарантия последнего ядра: full-upgrade может его пропустить, если метапакет
# уже установлен — догоняем явно и проверяем, чтоInstalled == Candidate
log "проверка последнего ядра"
chroot "$ROOTFS" sh -c '
    apt-get install -y -qq --only-upgrade linux-image-amd64
    # старое ядро (оставшееся после обновления метапакета) — вычищаем явно:
    # autoremove не всегда помечает его orphaned (зависит от того, как пакет
    # попал в систему), а два ядра раздувают образ и портят факты версий
    NEW_KVER=$(ls /lib/modules | sort -V | tail -1)
    for d in /lib/modules/*; do
        k=$(basename "$d")
        [ "$k" = "$NEW_KVER" ] && continue
        echo "purge old kernel: linux-image-$k"
        DEBIAN_FRONTEND=noninteractive apt-get -y -qq purge "linux-image-$k"
    done
    apt-get autoremove -y -qq
    INSTALLED=$(dpkg-query -W -f=\${Version} linux-image-amd64)
    CANDIDATE=$(apt-cache policy linux-image-amd64 | awk "/Candidate:/{print \$2}")
    echo "kernel installed=$INSTALLED candidate=$CANDIDATE"
    [ "$INSTALLED" = "$CANDIDATE" ] || { echo "ОШИБКА: ядро устарело"; exit 1; }
'

# --- установка VLANit-компонентов в rootfs ---
log "копирование VLANit provisioning / quadlet / snapshots"
install -d -m 0755 "$ROOTFS/opt/vlanit"
cp -a "$PROJECT_ROOT/provisioning/." "$ROOTFS/opt/vlanit/provisioning/"
cp -a "$PROJECT_ROOT/snapshots/vlanit-snapshot" "$ROOTFS/opt/vlanit/"
# владение — строго root: cp -a сохраняет uid хостовой сборочной машины
# (в rootless-режиме — uid 1000), что ломает sudo и права в установленной
# системе (полевой дефект 1.2.4)
chown -R root:root "$ROOTFS/opt/vlanit"
install -D -m 0644 "$PROJECT_ROOT/quadlet/mikopbx.container" \
    "$ROOTFS/etc/containers/systemd/mikopbx.container"
# пароль веб-админа — в файле; читает только root (аудит cso #1)
chmod 600 "$ROOTFS/etc/containers/systemd/mikopbx.container"
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-containers-registries.conf" \
    "$ROOTFS/etc/containers/registries.conf"

# брендинг ОС
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-os-release" \
    "$ROOTFS/usr/lib/os-release"
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-os-release" \
    "$ROOTFS/etc/os-release"
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-issue" \
    "$ROOTFS/etc/issue"
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-issue" \
    "$ROOTFS/etc/issue.net"
# версия в макетах (motd) — из config/build.yaml; placeholder @VLANIT_VERSION@,
# тот же источник, что имя ISO и меню GRUB (50-iso.sh): литерал версии в
# артефактах уже дважды давал релиз с чужой строкой (1.3.0, 1.3.1).
DISTRO_VERSION="$(sed -n 's/^  version: //p' "$PROJECT_ROOT/config/build.yaml" | head -1 | tr -d '"')"
[ -n "$DISTRO_VERSION" ] || { echo "[golden] ОШИБКА: version не найден в config/build.yaml" >&2; exit 1; }
sed "s/@VLANIT_VERSION@/$DISTRO_VERSION/" "$PROJECT_ROOT/rootfs/etc-motd" > "$BUILD_DIR/motd.rendered"
install -D -m 0644 "$BUILD_DIR/motd.rendered" \
    "$ROOTFS/etc/motd"

# Параметры контейнера АТС (issue #16): установщик читает и пишет в quadlet
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-vlanit-mikopbx-container.conf" \
    "$ROOTFS/etc/vlanit/mikopbx-container.conf"

# OTA: команды обновления/отката, ключ релиза, конфиг канала
install -D -m 0755 "$PROJECT_ROOT/snapshots/vlanit-update" \
    "$ROOTFS/usr/local/sbin/vlanit-update"
install -D -m 0755 "$PROJECT_ROOT/snapshots/vlanit-rollback" \
    "$ROOTFS/usr/local/sbin/vlanit-rollback"
install -D -m 0755 "$PROJECT_ROOT/snapshots/vlanit-backup" \
    "$ROOTFS/usr/local/sbin/vlanit-backup"
# маркер Docker-среды для provisioning MikoPBX (issue #10): монтируется
# в контейнер как /.dockerenv:ro; без него DockerCloud не применяет env
install -d -m 0755 "$ROOTFS/var/lib/vlanit"
touch "$ROOTFS/var/lib/vlanit/dockerenv"

# диагностика (issue #9): doctor + общая библиотека проверок
install -D -m 0755 "$PROJECT_ROOT/rootfs/vlanit-doctor" \
    "$ROOTFS/usr/local/sbin/vlanit-doctor"
install -D -m 0755 "$PROJECT_ROOT/rootfs/vlanit-doctor-gui" \
    "$ROOTFS/usr/local/sbin/vlanit-doctor-gui"
install -D -m 0644 "$PROJECT_ROOT/rootfs/lib-checks.sh" \
    "$ROOTFS/opt/vlanit/lib/checks.sh"
# doctor GUI (issue #56): HTTP + netsurf-fb
install -d -m 0755 "$ROOTFS/opt/vlanit/doctor/static" \
    "$ROOTFS/opt/vlanit/doctor/templates"
install -D -m 0755 "$PROJECT_ROOT/doctor/gui/server.py" \
    "$ROOTFS/opt/vlanit/doctor/server.py"
install -D -m 0755 "$PROJECT_ROOT/doctor/gui/launch-gui.sh" \
    "$ROOTFS/opt/vlanit/doctor/launch-gui.sh"
install -D -m 0644 "$PROJECT_ROOT/doctor/gui/templates/layout.html" \
    "$ROOTFS/opt/vlanit/doctor/templates/layout.html"
install -D -m 0644 "$PROJECT_ROOT/doctor/gui/static/style.css" \
    "$ROOTFS/opt/vlanit/doctor/static/style.css"
if [ -f "$PROJECT_ROOT/installer/branding/default/logo.png" ]; then
    install -D -m 0644 "$PROJECT_ROOT/installer/branding/default/logo.png" \
        "$ROOTFS/opt/vlanit/doctor/static/logo.png"
fi
# OTA GUI (issue #58): HTTP + netsurf-fb, handoff из doctor
install -d -m 0755 "$ROOTFS/opt/vlanit/update/static"
install -D -m 0755 "$PROJECT_ROOT/update/gui/server.py" \
    "$ROOTFS/opt/vlanit/update/server.py"
install -D -m 0755 "$PROJECT_ROOT/update/gui/launch-gui.sh" \
    "$ROOTFS/opt/vlanit/update/launch-gui.sh"
install -D -m 0644 "$PROJECT_ROOT/update/gui/static/style.css" \
    "$ROOTFS/opt/vlanit/update/static/style.css"
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-vlanit-release.pub" \
    "$ROOTFS/etc/vlanit/release.pub"
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-vlanit-update.conf" \
    "$ROOTFS/etc/vlanit/update.conf"

# безопасность: автообновления, sshd, fail2ban
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-apt-20vlanit-auto-upgrades" \
    "$ROOTFS/etc/apt/apt.conf.d/20vlanit-auto-upgrades"
# degraded-активация vg0 в initramfs (штатная автоактивация — только
# когда VG полна; при умершем диске зеркала без хука корень не найден)
install -D -m 0755 \
    "$PROJECT_ROOT/rootfs/etc-initramfs-tools-scripts-local-block-vlanit-lvm" \
    "$ROOTFS/etc/initramfs-tools/scripts/local-block/vlanit-lvm"
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-ssh-01-vlanit.conf" \
    "$ROOTFS/etc/ssh/sshd_config.d/01-vlanit.conf"
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-ssh-service-d-00-keygen.conf" \
    "$ROOTFS/etc/systemd/system/ssh.service.d/00-keygen.conf"
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-fail2ban-vlanit-sshd.conf" \
    "$ROOTFS/etc/fail2ban/jail.d/vlanit-sshd.conf"

# Plymouth: фирменная тема VLANit (общий скрипт — та же логика в live rootfs)
"$PROJECT_ROOT/scripts/install-plymouth-theme.sh" "$ROOTFS"
# GPU KMS-модули в initramfs: без них ранний plymouth в initramfs сидит на
# текстовом фолбэке и графический splash не показывается (spec 1.3.2)
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-initramfs-tools-modules" \
    "$ROOTFS/etc/initramfs-tools/modules"
# #29/#30/#32 — после тем и пакетов
"$PROJECT_ROOT/scripts/slim-rootfs.sh" "$ROOTFS"

# кириллица на консоли (trixie: шрифты только в console-setup)
cat > "$ROOTFS/etc/vconsole.conf" <<'EOF'
FONT=CyrSlav-DejaVu30x16
EOF

# NTP: резервные серверы при отсутствии DHCP-опций
cat > "$ROOTFS/etc/systemd/timesyncd.conf" <<'EOF'
[Time]
FallbackNTP=0.deb.pool.ntp.org 1.deb.pool.ntp.org 2.deb.pool.ntp.org
EOF

# firewall default-deny (ADR-0003) и поведение кнопки питания
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-nftables.conf" \
    "$ROOTFS/etc/nftables.conf"
install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-logind-01-vlanit.conf" \
    "$ROOTFS/etc/systemd/logind.conf.d/01-vlanit.conf"

# персистентные журналы (без /var/log/journal journald пишет в tmpfs)
mkdir -p "$ROOTFS/var/log/journal" "$ROOTFS/etc/systemd/journald.conf.d"
cat > "$ROOTFS/etc/systemd/journald.conf.d/01-vlanit.conf" <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=200M
EOF

# first-boot служба
install -D -m 0644 "$PROJECT_ROOT/rootfs/vlanit-firstboot.service" \
    "$ROOTFS/etc/systemd/system/vlanit-firstboot.service"
install -D -m 0755 "$PROJECT_ROOT/rootfs/vlanit-firstboot.sh" \
    "$ROOTFS/opt/vlanit/vlanit-firstboot.sh"
install -D -m 0644 "$PROJECT_ROOT/rootfs/99-vlanit.preset" \
    "$ROOTFS/etc/systemd/system-preset/99-vlanit.preset"
install -D -m 0755 "$PROJECT_ROOT/rootfs/vlanit-test-agent.sh" \
    "$ROOTFS/opt/vlanit/vlanit-test-agent.sh"
install -D -m 0644 "$PROJECT_ROOT/rootfs/vlanit-test-agent.service" \
    "$ROOTFS/etc/systemd/system/vlanit-test-agent.service"
install -D -m 0755 "$PROJECT_ROOT/rootfs/vlanit-ota-test.sh" \
    "$ROOTFS/opt/vlanit/vlanit-ota-test.sh"
install -D -m 0644 "$PROJECT_ROOT/rootfs/vlanit-ota-test.service" \
    "$ROOTFS/etc/systemd/system/vlanit-ota-test.service"
install -D -m 0755 "$PROJECT_ROOT/rootfs/vlanit-backup-test.sh" \
    "$ROOTFS/opt/vlanit/vlanit-backup-test.sh"
install -D -m 0644 "$PROJECT_ROOT/rootfs/vlanit-backup-test.service" \
    "$ROOTFS/etc/systemd/system/vlanit-backup-test.service"
# preset-файл попадает в rootfs уже после установки пакетов — включаем службы явно
install -D -m 0755 "$PROJECT_ROOT/rootfs/vlanit-atc-password-heal.sh" \
    "$ROOTFS/opt/vlanit/vlanit-atc-password-heal.sh"
install -D -m 0644 "$PROJECT_ROOT/rootfs/vlanit-atc-password-heal.service" \
    "$ROOTFS/etc/systemd/system/vlanit-atc-password-heal.service"
# secret пароля веб-админа — ранняя служба ДО mikopbx (issue #34)
install -D -m 0755 "$PROJECT_ROOT/rootfs/vlanit-atc-secret.sh" \
    "$ROOTFS/opt/vlanit/vlanit-atc-secret.sh"
install -D -m 0644 "$PROJECT_ROOT/rootfs/vlanit-atc-secret.service" \
    "$ROOTFS/etc/systemd/system/vlanit-atc-secret.service"
for unit in vlanit-firstboot.service vlanit-test-agent.service \
            vlanit-ota-test.service vlanit-backup-test.service \
            vlanit-atc-password-heal.service \
            vlanit-atc-secret.service \
            systemd-networkd.service systemd-resolved.service \
            systemd-timesyncd.service nftables.service \
            ssh.service fail2ban.service; do
    chroot "$ROOTFS" systemctl enable "$unit" 2>/dev/null || \
        echo "WARN: не удалось включить $unit"
done

# --- очистка уникальных идентификаторов (критично для Golden Image) ---
# resolv.conf был нужен только для сборочных apt-операций
rm -f "$ROOTFS/etc/resolv.conf"

log "очистка machine-id, SSH host keys, журналов"
rm -f "$ROOTFS/etc/machine-id" "$ROOTFS/var/lib/dbus/machine-id"
touch "$ROOTFS/etc/machine-id"  # systemd сгенерирует при первой загрузке
rm -f "$ROOTFS/etc/ssh/ssh_host_"*
rm -f "$ROOTFS/etc/hostname"
find "$ROOTFS/var/log" -type f -delete 2>/dev/null || true
: > "$ROOTFS/etc/fstab"   # установщик генерирует fstab цели
# чистый кэш apt внутри образа
rm -rf "$ROOTFS/var/cache/apt/"* "$ROOTFS/var/lib/apt/lists/"*

# --- факты версий для манифеста ---
DEBIAN_VERSION="$(cat "$ROOTFS/etc/debian_version")"
KERNEL_VERSION="$(basename "$(ls -d "$ROOTFS"/lib/modules/* | sort -V | tail -1)")"
PODMAN_VERSION="$(chroot "$ROOTFS" dpkg-query -W -f='${Version}' podman 2>/dev/null || echo unknown)"
cat > "$BUILD_DIR/facts.json" <<EOF
{
  "debian_version": "$DEBIAN_VERSION",
  "kernel_version": "$KERNEL_VERSION",
  "podman_version": "$PODMAN_VERSION"
}
EOF
log "факты: Debian $DEBIAN_VERSION, kernel $KERNEL_VERSION, podman $PODMAN_VERSION"

# --- упаковка ---
# guard владения: в Golden Image не должно быть файлов uid/gid >= 1000
# (системные пользователи пакетов — < 1000). Иначе установленная система
# получит файлы пользователя сборки — sudo/shadow в чужом владении, и
# установка фактически сломана (полевой дефект 1.2.4).
STRAY_OWNERS="$(find "$ROOTFS" -xdev \( -uid +999 -o -gid +999 \) -print -quit 2>/dev/null)"
[ -z "$STRAY_OWNERS" ] || {
    echo "ОШИБКА: файлы не в root-владении в Golden Image, первый: $STRAY_OWNERS" >&2
    find "$ROOTFS" -xdev \( -uid +999 -o -gid +999 \) -print | head -20 >&2
    exit 1
}
log "упаковка golden.tar.zst"
tar -C "$ROOTFS" --zstd -cpf "$PAYLOAD/golden.tar.zst" .
( cd "$PAYLOAD" && sha256sum golden.tar.zst > golden.tar.zst.sha256 )
log "готово: $PAYLOAD/golden.tar.zst ($(du -h "$PAYLOAD/golden.tar.zst" | cut -f1))"
