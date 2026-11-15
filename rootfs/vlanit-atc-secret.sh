#!/usr/bin/env bash
# /opt/vlanit/vlanit-atc-secret.sh — idempotent: Podman secret atc-admin-password.
# Ранняя служба (ДО mikopbx.service): secret должен существовать до старта
# контейнера. Раньше secret создавал vlanit-firstboot, что требовало
# After=vlanit-firstboot.service в quadlet → цикл порядка загрузки
# (multi-user → mikopbx → firstboot → multi-user), systemd на последующих
# загрузках удалял job mikopbx и АТС не стартовала (issue #34).
set -Eeuo pipefail

PW_FILE="/etc/vlanit/atc-admin-password"

if podman secret exists atc-admin-password 2>/dev/null; then
    exit 0   # уже есть (в т.ч. после reboot)
fi

if [ ! -s "$PW_FILE" ]; then
    # файл исключён из vlanit-backup → после восстановления из бэкапа
    # пароль ротируется (provisioning MikoPBX применит его из env при
    # каждом старте контейнера). Фактический пароль — в PW_FILE (0600).
    install -d -m 0700 /etc/vlanit
    openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16 > "$PW_FILE"
    chmod 600 "$PW_FILE"
    echo "vlanit-atc-secret: пароль отсутствовал (восстановление?) — сгенерирован новый" >&2
fi

podman secret create atc-admin-password "$PW_FILE"
