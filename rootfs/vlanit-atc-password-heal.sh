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

# источник пароля: root-600 файл (Podman secret), НЕ quadlet (секьюрити-фидбек)
PW_FILE="/etc/vlanit/atc-admin-password"
PW=""
[ -s "$PW_FILE" ] && PW="$(cat "$PW_FILE")"
if [ -z "$PW" ]; then
    log "пароль веб-админа отсутствует (/etc/vlanit/atc-admin-password) — нечего лечить, выход"
    exit 0
fi

# ожидание готовности приложения (до 10 минут)
log "ожидание готовности MikoPBX"
for i in $(seq 1 120); do
    podman logs mikopbx 2>/dev/null | grep -q "All services are fully loaded welcome" && break
    sleep 5
done

login_ok() {
    # ретраи: DockerCloud применяет env асинхронно после баннера готовности
    local i
    for i in 1 2 3; do
        curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
            -H 'Content-Type: application/json' \
            -d "{\"login\":\"admin\",\"password\":\"$PW\"}" | grep -q accessToken && return 0
        [ "$i" -lt 3 ] && sleep 10
    done
    return 1
}

# часовой пояс АТС = пояс устройства (issue #18): TZ/localtime проброшены
# в контейнер, а настройка PBXTimezone применяется через REST v3
# (PATCH /pbxcore/api/v3/time-settings, localhost bypass)
sync_timezone() {
    local tz
    tz="$(cat /etc/timezone 2>/dev/null)"
    [ -z "$tz" ] && return 0
    local cur
    cur="$(curl -sk --max-time 10 https://127.0.0.1/pbxcore/api/v3/time-settings 2>/dev/null         | sed -n 's/.*"PBXTimezone":"\([^"]*\)".*/\1/p' | head -1)"
    if [ "$cur" != "$tz" ]; then
        log "выравнивание часового пояса АТС: $cur -> $tz"
        curl -sk --max-time 15 -X PATCH https://127.0.0.1/pbxcore/api/v3/time-settings             -H 'Content-Type: application/json'             -d "{\"PBXTimezone\":\"$tz\"}" >/dev/null 2>&1 ||             log "WARN: не удалось применить PBXTimezone через API"
    fi
}

if login_ok; then
    log "пароль веб-админа в порядке"
    rm -f /var/lib/vlanit/atc-password-broken
    sync_timezone
    exit 0
fi

log "пароль quadlet не принимается — сброс upstream (issue #10), самолечение через REST v3"
touch /var/lib/vlanit/atc-password-broken

# повторное применение пароля (настройки применяются асинхронно — ждём и ретраим)
for i in 1 2 3; do
    HEAL="$(curl -sk --max-time 15 -X PATCH https://127.0.0.1/pbxcore/api/v3/general-settings \
        -H 'Content-Type: application/json' \
        -w '\nHTTP:%{http_code}' \
        -d "{\"WEB_ADMIN_PASSWORD\":\"$PW\"}")"
    echo "$HEAL" | grep -qE '"result": ?true' || {
        log "попытка $i: PATCH отклонён: $(echo "$HEAL" | tr -d '\n' | head -c 200)"
        sleep 10
        continue
    }
    # асинхронное применение: ждём, пока логин начнёт проходить (до 90 с)
    for j in $(seq 1 18); do
        if curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
                -H 'Content-Type: application/json' \
                -d "{\"login\":\"admin\",\"password\":\"$PW\"}" | grep -q accessToken; then
            log "самолечение успешно: пароль quadlet применён и проверен"
            rm -f /var/lib/vlanit/atc-password-broken
            sync_timezone
            exit 0
        fi
        sleep 5
    done
done

log "ОШИБКА: самолечение не удалось — пароль всё ещё не принимается (флаг /var/lib/vlanit/atc-password-broken)"
exit 1
