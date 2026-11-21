## Context

CLI doctor: `rootfs/vlanit-doctor` + `rootfs/lib-checks.sh` (~43 checks,
8 groups). Installer GUI: live-only `installer/gui/server.py` +
`netsurf-fb`; golden has python3/yaml, **no** netsurf.

## Goals / Non-Goals

**Goals:** read-only HTML UI на FB; данные из `--json`; брендинг как у
установщика; CLI не ломать.

**Non-Goals:** см. proposal (TUI fallback, remote web, fix-actions, bump).

## Decisions

1. **Источник данных** — `vlanit-doctor --json` (один контракт с CLI).
   GUI не дублирует `check_*`.
2. **Отдельный сервер** `doctor/gui/server.py` на `127.0.0.1` (порт ≠
   8765 установщика, напр. `8766`); шаблоны/CSS по образцу installer,
   без collect/install handlers.
3. **Экраны** — overview (итог + счётчики) + одна страница на группу
   `CHECK_GROUPS`; refresh перезапускает прогон (meta-refresh /
   кнопка «Обновить»).
4. **Запуск** — `vlanit-doctor --gui` или `vlanit-doctor-gui`: сервер +
   `netsurf-fb`; без FB → сообщение + exit ≠0, CLI подсказка.
5. **Golden** — пакет `netsurf-fb` (+ deps как в live); файлы
   `/opt/vlanit/doctor/`. Брендинг: symlink/copy профиля
   `installer/branding/default` или минимальный `doctor/branding`.
6. **Права** — root рекомендуется; без root — SKIP как в CLI, баннер
   «часть проверок требует root».
7. **Секреты** — в HTML не больше, чем в CLI/JSON (пароли не показывать).

## Rejected

- Встроить GUI в `installer/gui/server.py` — разный lifecycle (live vs
  installed), риск раздуть установщик.
- Только CSS-обёртка над ANSI stdout — нет структуры групп/статусов.
- Полноценный browser на golden — избыточно; netsurf-fb уже принят.

## Risks

- Рост ISO от netsurf → измерить; при > baseline×margin — bump
  `iso_baseline_mib` в том же PR.
- Долгий прогон (~30 с) → экран «идёт проверка» до первого JSON.
- NetSurf CSS quirks → shots / ручной просмотр layout.

## Verify impact

- Unit: JSON fixture → HTML содержит группы/OK|FAIL|SKIP.
- `make iso` + QEMU: doctor-gui стартует на FB **или** smoke без FB
  (сервер отдаёт overview) — детали в verification.md; полный FB —
  отдельная сессия.
