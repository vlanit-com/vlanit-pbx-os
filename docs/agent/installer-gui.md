# Pack: установщик (GUI / TUI fallback)

Читать при работе с `installer/`, `docs/gui-installer*`, wiki установки,
экранами/брендингом.

## Primary / fallback

- **Primary:** HTML + FB-браузер (`installer/gui/`, обычно `netsurf-fb`).
- **Fallback:** Cursive TUI (`installer/tui-cursive/` → `installer/bin/vlanit-tui`).
- **dialog / whiptail / newt** — не primary (переходный fallback).
- Принудительно: kernel cmdline `vlanit.ui=gui|tui|dialog`.
- Источник требований при изменении установщика (кроме бампа версии):
  OpenSpec → см. [openspec.md](openspec.md).

## Контракт

- Конфиг: JSON `/run/vlanit/install-config.json`.
- Probe: `installer/bin/vlanit-probe`; раннер: `installer/lib/install-run.sh`.
- Реестр экранов: `installer/screens.yaml` (добавление/выключение шагов).
- Брендинг: `installer/branding/<profile>/`, переключение `VLANIT_BRANDING`.

## UI и документация

- Править реальный UI в `installer/gui/` (и fallback при затронутом потоке),
  не только скрины/доки. После UI — переснять скрины.
- Поля форм: одна вертикаль контролов; не уводить далеко вправо; схемы
  дисков не ломать колонки полей.
- Пользовательские доки/wiki под **GUI-мастер** (не старый dialog-only):
  текст и скрины обновлять вместе.
- Галерея: `docs/gui-installer.md` + `docs/gui-installer/shots/`.
- Пользовательская установка: `docs/installation.md`.
- Wiki: [Home](https://github.com/vlanit-com/vlanit-pbx-os/wiki) —
  Quick-Start, Installation-Screens, Branding, Runbooks и др.

## Сборка TUI / payload в worktree

- TUI: `scripts/build-tui.sh` (Docker `rust:1.85-bookworm`) →
  `installer/bin/vlanit-tui`.
- Для `make iso` в worktree нужен **реальный** `build/payload` (symlink на
  payload другого checkout часто не виден в docker-mount).

## Проверки

Матрица — [verification.md](verification.md). ISO/QEMU — отдельная сессия
агента, не смешивать с чисто доксовой работой.
