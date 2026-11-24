# Спека: #18 часовой пояс + #45 heal при stop (as-built)

Статус: **в работе** (`fix/tz-heal-18-45`).

## #18. Дефолт мастера + PBXTimezone с первого старта

**Корень (поле 1.4.3/1.4.4):**
1. Мастер (GUI/TUI/dialog) заранее заполнял `Europe/Moscow`; ожидание
   поля — `Asia/Dubai`.
2. Host/`TZ`/localtime выравнивались сразу; `PBXTimezone` в БД АТС —
   только через heal REST после баннера готовности (~2–2,5 мин).

**Решение:**
1. Дефолт IANA во всех UI: `Asia/Dubai` (GUI `server.py`, dialog
   `vlanit-installer`, TUI `main.rs`).
2. В VLANIT-ENV quadlet рядом с `TZ=<пояс>` — `PBX_TIMEZONE=<пояс>`
   (`PbxSettings::PBX_TIMEZONE`). DockerCloud применяет env при каждом
   старте контейнера → `PBXTimezone` с первого старта АТС без ожидания
   heal. Heal REST остаётся запасным выравниванием.

**Проверка:**
- Мастер: поле «Часовой пояс» = `Asia/Dubai` до ввода.
- После первой загрузки: `podman exec mikopbx printenv PBX_TIMEZONE`
  и `PBXTimezone` в time-settings = пояс мастера (без ожидания heal).
- Агент: `atc-tz-env` (TZ и PBX_TIMEZONE непусты в контейнере).

## #45. heal не деградирует систему при stop mikopbx

**Корень (поле 1.4.4):** `systemctl stop mikopbx` во время ожидания
heal → heal крутит 10 мин (120×5 с), PATCH к остановленной АТС,
exit 1 → `degraded`.

**Решение:** в `vlanit-atc-password-heal.sh` на каждом витке ожидания /
ретраев — проверка `mikopbx_running` (юнит active или контейнер
Running). Стоп → log + **exit 0** (без failed).

**Проверка:**
- Во время ожидания heal: `systemctl stop mikopbx` → heal завершается
  успешно (exit 0), система не `degraded`.
- Обычная загрузка: heal по-прежнему чинит пароль / догоняет TZ при
  нужде.
