## Why

Полевой инженер на консоли с framebuffer видит длинный CLI-вывод
`vlanit-doctor`. Установщик уже primary HTML+`netsurf-fb`. Нужен тот же
UX для диагностики на **установленной** ОС (issue #56).

## What Changes

- GUI-оболочка поверх существующего `vlanit-doctor --json` /
  `lib-checks.sh`: локальный HTTP + `netsurf-fb`, read-only.
- Экраны: сводка + группы из `CHECK_GROUPS`; hints как в `--fix-hints`.
- Пакет в golden: `netsurf-fb` (+ deps), код под `/opt/vlanit/doctor/`.
- CLI `vlanit-doctor` без смены контракта (SSH, агент, cron).

## Non-goals

- TUI/dialog fallback для doctor (v2, если нет `/dev/fb0`).
- Действия «исправить» из GUI (только показ hint).
- Удалённый веб / SSH-GUI.
- Слияние с `installer/gui/server.py` в один процесс.
- Полевой прогон #42/#49/#14.
- Бамп версии релиза в этом change.

## Capabilities

### New Capabilities
- `vlanit-doctor-gui`: HTML+FB UI диагностики на установленной ОС.

### Modified Capabilities

_(нет — CLI doctor / checks остаются as-built)_

## Impact

- Новый каталог `doctor/gui/` (или `rootfs/...`); golden `10-golden-rootfs.sh`
- Размер ISO: +`netsurf-fb` — сверить с `iso_baseline_mib`
- Доки: as-built `docs/specs/vlanit-doctor-gui.md`, README/runbooks
- Тесты: unit рендер JSON→HTML; QEMU — отдельная сессия

## Source of truth

Этот change. Issue #56. CLI as-built: `docs/specs/1.2.8-vlanit-doctor.md`.
