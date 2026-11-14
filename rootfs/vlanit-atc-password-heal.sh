#!/usr/bin/env bash
# /opt/vlanit/vlanit-atc-password-heal.sh — самолечение пароля веб-админа
# MikoPBX (issue #10, известный upstream-баг: provisioning сбрасывает хэш
# пароля на перезагрузке, маркер CLOUD_INSTANCE_ID не даёт повторно
# применить WEB_ADMIN_PASSWORD из окружения).
#
# Логика: дождаться готовности приложения → проверить логин паролем из
# quadlet → при FAIL применить пароль через REST v3 PATCH general-settings
# (localhost bypass: токен не нужен) → перепроверить.
# Идемпотентно и безопасно при повторном запуске (каждая загрузка).
set -uo pipefail

LOG_TAG="vlanit-atc-heal"
log() { logger -t "$LOG_TAG" -- "$*"; echo "[$LOG_TAG] $*"; }

QUADLET="/etc/containers/systemd/mikopbx.container"
PW="$(sed -n 's/^Environment=WEB_ADMIN_PASSWORD=//p' "$QUADLET" 2>/dev/null | head -1)"
PW="${PW%\"}"; PW="${PW#\"}"
if [ -z "$PW" ]; then
    log "WEB_ADMIN_PASSWORD в quadlet не задан — нечего лечить, выход"
    exit 0
fi

# ожидание готовности приложения (до 10 минут)
log "ожидание готовности MikoPBX"
for i in $(seq 1 120); do
    podman logs mikopbx 2>/dev/null | grep -q "All services are fully loaded welcome" && break
    sleep 5
done

login_ok() {
    curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
        -H 'Content-Type: application/json' \
        -d "{\"login\":\"admin\",\"password\":\"$PW\"}" | grep -q accessToken
}

if login_ok; then
    log "пароль веб-админа в порядке"
    rm -f /var/lib/vlanit/atc-password-broken
    exit 0
fi

log "пароль quadlet не принимается — сброс upstream (issue #10), самолечение через REST v3"
touch /var/lib/vlanit/atc-password-broken

# повторное применение пароля (настройки применяются асинхронно — ждём и ретраим)
for i in 1 2 3; do
    HEAL="$(curl -sk --max-time 15 -X PATCH https://127.0.0.1/pbxcore/api/v3/general-settings \
        -H 'Content-Type: application/json' \
        -d "{\"WEB_ADMIN_PASSWORD\":\"$PW\"}")"
    echo "$HEAL" | grep -q '"result":true' || {
        log "попытка $i: PATCH отклонён: $(echo "$HEAL" | head -c 160)"
        sleep 10
        continue
    }
    # асинхронное применение: ждём, пока логин начнёт проходить (до 60 с)
    for j in $(seq 1 12); do
        if login_ok; then
            log "самолечение успешно: пароль quadlet применён и проверен"
            rm -f /var/lib/vlanit/atc-password-broken
            exit 0
        fi
        sleep 5
    done
done

log "ОШИБКА: самолечение не удалось — пароль всё ещё не принимается (флаг /var/lib/vlanit/atc-password-broken)"
exit 1
