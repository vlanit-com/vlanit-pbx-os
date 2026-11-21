## Why

Полевой OTA (`vlanit-update`) сейчас CLI + `YES` на tty. Doctor GUI уже
на консоли, но только диагностика. Нужен тот же HTML+fb UX для обновления
АТС и handoff из doctor, когда на USB есть пакет (issue #58).

## What Changes

- `vlanit-update --gui`: мастер (источник → проверки → confirm YES →
  apply → health), loopback + netsurf-fb; CLI без регрессии.
- Doctor GUI: read-only checks про OTA + **кнопка «Обновить»**, если
  пакет есть → запуск `vlanit-update --gui`; при FAIL GUI → fallback CLI
  на консоли. Doctor сам пакет не применяет и auto-YES не шлёт.
- Новые checks в `lib-checks.sh` (pin Image, наличие пакета, last result).

## Non-goals

- Сборочный bump #12 в GUI (Hub / make iso / QEMU).
- Remote web / SSH-GUI / TUI fallback updater (v2).
- Apply / rollback из того же HTTP-процесса doctor без отдельного
  `vlanit-update`.
- Авто-YES, unattended apply из doctor.
- Бамп `distro.version` / релизный тег в этом change.

## Capabilities

### New Capabilities
- `vlanit-update-gui`: HTML+FB мастер полевого OTA.
- `doctor-update-handoff`: кнопка запуска updater из doctor GUI.

### Modified Capabilities
- `vlanit-doctor-gui`: блок updates + action handoff (не apply).

## Impact

- `snapshots/vlanit-update`, `doctor/gui/`, `rootfs/lib-checks.sh`, golden
- Доки: as-built + `docs/doctor-gui.md` / troubleshooting
- Тесты: unit GUI/handoff; QEMU OTA — отдельная сессия

## Source of truth

`openspec/changes/vlanit-update-gui/` до archive.
