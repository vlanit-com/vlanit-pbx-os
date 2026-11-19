# Спека: GUI-установщик HTML + Cursive fallback (идея #12)

Статус: **as-built / эпик #46 закрыт** (релизы 1.4.0–1.4.1, 2026-11-19).

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
- **Fallback:** `vlanit-tui` (Cursive), затем `dialog` (переходный).
- **Контракт:** `/run/vlanit/install-config.json` + `vlanit-probe`;
  stages — `install-run.sh`. Autoinstall YAML без смены схемы.
- **Сборка TUI:** `scripts/build-tui.sh` → `installer/bin/vlanit-tui`.

## Отклонённые альтернативы

- X/Chromium, Calamares/Agama, GTK/Qt, whiptail как primary.
- Полный YAML-драйвер Cursive (пока handlers в Rust).

## Проверка (факты закрытия эпика)

- OpenSpec `installer-wg-step-form-align` → archived
  `openspec/changes/archive/2026-11-19-installer-wg-step-form-align/`
- Unit: `tests/unit/test-config-json.sh` PASS
- Shots: `docs/gui-installer/shots/` (`scripts/shot-gui-html.sh`)
- Регресс QEMU: `regress-full.sh` Т1–Т9+mirror PASS на ISO 1.4.0
  (`docs/testing.md`)
- Релиз: теги `v1.4.0` / `v1.4.1`, wiki Installation-Screens / Branding
- Fallback cmdline: `vlanit.ui=gui|tui|dialog`

Критерий эпика #46 (код + стенд + docs/wiki) — выполнен. Полевой
netsurf-fb / скрины с флота — **не** критерий закрытия эпика; вынесены
в follow-up (см. ниже).

## Follow-up (вне эпика)

- Полевой прогон GUI/`netsurf-fb` на ≥2 моделях + скрины live ISO —
  issue #49; пересекается с #42.
- Удаление dialog-пути — после стабилизации Cursive на флоте (отдельный
  issue, не сейчас).
