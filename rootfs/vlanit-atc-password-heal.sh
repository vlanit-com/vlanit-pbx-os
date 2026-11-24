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
#
# Issue #45: если mikopbx остановлен во время ожидания — выход 0 без
# 10‑мин кручения и без failed/degraded.
set -uo pipefail

LOG_TAG="vlanit-atc-heal"
log() { logger -t "$LOG_TAG" -- "$*"; echo "[$LOG_TAG] $*"; }

mikopbx_running() {
    # юнит active ИЛИ контейнер Running
    if systemctl is-active --quiet mikopbx.service 2>/dev/null; then
        return 0
    fi
    local st
    st="$(podman inspect -f '{{.State.Running}}' mikopbx 2>/dev/null || true)"
    case "$st" in
        true|True) return 0 ;;
        *) return 1 ;;
    esac
}

# источник пароля: root-600 файл (Podman secret), НЕ quadlet (секьюрити-фидбек)
PW_FILE="/etc/vlanit/atc-admin-password"
PW=""
[ -s "$PW_FILE" ] && PW="$(cat "$PW_FILE")"
if [ -z "$PW" ]; then
    log "пароль веб-админа отсутствует (/etc/vlanit/atc-admin-password) — нечего лечить, выход"
    exit 0
fi

# ожидание готовности приложения (до 10 минут); стоп контейнера → выход 0
log "ожидание готовности MikoPBX"
ready=0
for i in $(seq 1 120); do
    if podman logs mikopbx 2>/dev/null | grep -q "All services are fully loaded welcome"; then
        ready=1
        break
    fi
    if ! mikopbx_running; then
        log "mikopbx остановлен во время ожидания готовности — выход без ошибки (issue #45)"
        exit 0
    fi
    sleep 5
done

if [ "$ready" != "1" ]; then
    if ! mikopbx_running; then
        log "таймаут ожидания и mikopbx не запущен — выход без ошибки (issue #45)"
        exit 0
    fi
    log "таймаут ожидания баннера готовности — пробуем API"
fi

login_ok() {
    # ретраи: DockerCloud применяет env асинхронно после баннера готовности
    local i
    for i in 1 2 3; do
        if ! mikopbx_running; then
            return 1
        fi
        curl -sk --max-time 10 -X POST https://127.0.0.1/pbxcore/api/v3/auth:login \
            -H 'Content-Type: application/json' \
            -d "{\"login\":\"admin\",\"password\":\"$PW\"}" | grep -q accessToken && return 0
        [ "$i" -lt 3 ] && sleep 10
    done
    return 1
}

# часовой пояс АТС = пояс устройства (issue #18): TZ + PBX_TIMEZONE в env
# DockerCloud; heal — запасной PATCH через REST v3
sync_timezone() {
    local tz
    tz="$(cat /etc/timezone 2>/dev/null)"
    [ -z "$tz" ] && return 0
    if ! mikopbx_running; then
        log "mikopbx не запущен — sync_timezone пропущен"
        return 0
    fi
    local cur
    cur="$(curl -sk --max-time 10 https://127.0.0.1/pbxcore/api/v3/time-settings 2>/dev/null \
        | sed -n 's/.*"PBXTimezone":"\([^"]*\)".*/\1/p' | head -1)"
    if [ "$cur" != "$tz" ]; then
        log "выравнивание часового пояса АТС: $cur -> $tz"
        curl -sk --max-time 15 -X PATCH https://127.0.0.1/pbxcore/api/v3/time-settings \
            -H 'Content-Type: application/json' \
            -d "{\"PBXTimezone\":\"$tz\"}" >/dev/null 2>&1 || \
            log "WARN: не удалось применить PBXTimezone через API"
    fi
}

if login_ok; then
    log "пароль веб-админа в порядке"
    rm -f /var/lib/vlanit/atc-password-broken
    sync_timezone
    exit 0
fi

if ! mikopbx_running; then
    log "mikopbx не запущен после ожидания — самолечение отложено, выход без ошибки (issue #45)"
    exit 0
fi

log "пароль quadlet не принимается — сброс upstream (issue #10), самолечение через REST v3"
touch /var/lib/vlanit/atc-password-broken

# повторное применение пароля (настройки применяются асинхронно — ждём и ретраим)
for i in 1 2 3; do
    if ! mikopbx_running; then
        log "mikopbx остановлен во время самолечения — выход без ошибки (issue #45)"
        exit 0
    fi
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
        if ! mikopbx_running; then
            log "mikopbx остановлен во время проверки пароля — выход без ошибки (issue #45)"
            exit 0
        fi
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

if ! mikopbx_running; then
    log "mikopbx не запущен — самолечение не завершено, выход без ошибки (issue #45)"
    exit 0
fi

log "ОШИБКА: самолечение не удалось — пароль всё ещё не принимается (флаг /var/lib/vlanit/atc-password-broken)"
exit 1
