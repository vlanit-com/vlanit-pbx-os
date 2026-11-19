# Идея #12: графический HTML-установщик с fallback на Cursive TUI

Статус: РЕАЛИЗОВАНО в ветке `feature/gui-installer` (2026-11-19);
регресс T1–T9+mirror PASS. До GA: полевой спайк netsurf-fb на ≥2
моделях. Спека: `docs/specs/gui-installer.md`. Галерея:
`docs/gui-installer.md`. Инструкция: `docs/installation.md` §2–3.

## Запрос

Заменить TUI-мастер (`dialog`) на графический интерфейс с HTML:
картинки на страницах, multi-field формы. Аппаратная поддержка
отображения обязательна; TUI остаётся fallback.

## Решения (as-designed)

- **Цели:** бренд/картинки + UX форм; удалёнка не в скоупе.
- **Primary:** HTML + `netsurf-fb` на `/dev/fb0` (без X/Chromium).
- **Fallback:** Cursive (Rust) TUI — multi-field формы; без схем дисков.
- **Бэкенд:** bash-логика установки; autoinstall YAML мимо обоих UI.
- **`dillo-fb` в Debian trixie нет** (пакет `dillo` тянет X11/FLTK) —
  только `netsurf-fb`.

## Почему это реалистично на нашем железе

- Целевые устройства — UEFI x86-64; ядро даёт `efifb`/`vesafb` → `/dev/fb0`.
- X/Wayland не нужны.
- Python3 уже в live (YAML) — локальный HTTP без новых рантаймов.
- `netsurf-fb` в trixie: ~4 МБ + SDL/freetype (десятки МБ с транзитивными
  deps; acceptable для USB ISO).

## Архитектура

```
vlanit-installer (entry)
  ├─ autoinstall.yaml ──────────────────────────────► bash stages
  ├─ probe /dev/fb0 + netsurf-fb
  │     yes → python3 HTTP 127.0.0.1 + netsurf-fb ──► config JSON → stages
  │     no  → vlanit-tui (Cursive) ─────────────────► config JSON → stages
  └─ (переходный) dialog, если нет Cursive-бинаря
```

- UI ↔ backend: JSON-конфиг `/run/vlanit/install-config.json` + probe-команды
  (`hardware` / `disks` / `ifaces` → JSON).
- HTML: статика + PNG из branding/; без JS (NetSurf без JS) — валидация
  на сервере (POST → ошибка → та же страница).
- Progress: poll `/progress` во время `run-stages`.

## Спайк netsurf-fb (заметки)

- Пакет: `netsurf-fb` 3.11 (trixie), Installed-Size ~4147 KiB.
- Зависимости: libsdl1.2, freetype, jpeg/png/webp, curl, xcb (поверхности
  libnsfb включают linux/sdl/x — xcb тянется пакетом).
- Запуск: `netsurf-fb -f linux URL` или `-f sdl` в QEMU.
- Кириллица: freetype + системные шрифты (`fonts-dejavu-core` в live).
- Проверка: `scripts/spike-netsurf-fb.sh` (QEMU/live); флот — вручную
  на ≥2 моделях до GA.

## Отклонённые альтернативы

- X/Wayland + Chromium/Firefox: +400–600 МБ ISO.
- GTK/Qt native app: правки UI = пересборка.
- whiptail/newt как fallback: формы не лучше `dialog`.
- Textual (Python) fallback: отклонён в пользу Cursive (паттерн Proxmox).
- Calamares/Agama: чужой бэкенд, тяжёлый стек.
- Оставить только TUI: схемы дисков/картинки не закрыть.
