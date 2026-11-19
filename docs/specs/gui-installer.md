# Спека: GUI-установщик HTML + Cursive fallback (идея #12)

Статус: as-built (ветка `feature/gui-installer`, 2026-11-19).

## Корень

TUI на `dialog` не закрывает бренд (схемы дисков, картинки) и
multi-field формы. Нужен графический primary с обязательным TUI-fallback;
экраны и бренд — декларативно, без жёсткой нумерации в коде.

## Решение (as-built)

- **Primary:** HTML + HTTP (`installer/gui/server.py`, `127.0.0.1:8765`) +
  `netsurf-fb`. Без JS — валидация на POST.
- **Реестр:** `installer/screens.yaml` — id / title / enabled / phase
  (`collect|progress|finish`). Навигация GUI по включённым collect;
  handlers `RENDERERS[id]`.
- **Шаблоны:** `installer/gui/templates/layout.html` (chrome + brand CSS).
- **Брендинг:** `installer/branding/<profile>/` (`branding.yaml`,
  `theme.css`, logo); `VLANIT_BRANDING` (default `default`).
- **WireGuard:** отдельный collect-экран (вкл после установки / нет +
  адрес/порт).
- **Fallback:** `vlanit-tui` (Cursive), затем `dialog`.
- **Контракт:** `/run/vlanit/install-config.json` + `vlanit-probe`;
  stages — `install-run.sh`. Autoinstall YAML без смены схемы.
- **Сборка TUI:** `scripts/build-tui.sh` → `installer/bin/vlanit-tui`.

## Отклонённые альтернативы

- X/Chromium, Calamares/Agama, GTK/Qt, whiptail как primary.
- Полный YAML-драйвер Cursive (пока handlers в Rust).

## Проверка

- `openspec validate installer-wg-step-form-align`
- Unit: `tests/unit/test-config-json.sh`
- Shots: `bash scripts/shot-gui-html.sh`
- Autoinstall QEMU: `scripts/test-qemu.sh` (UI не участвует)
- Fallback: `vlanit.ui=tui|dialog`

## Открытые пункты

- Полевой прогон netsurf-fb на ≥2 моделях.
- Скриншоты с live ISO на флоте — до GA.
- Удаление dialog-пути после стабилизации Cursive.
