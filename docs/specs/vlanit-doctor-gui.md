# Спецификация: GUI для `vlanit-doctor` (#56)

Статус: **in-progress** (OpenSpec `vlanit-doctor-gui`).

## 0. Корень

CLI `vlanit-doctor` на консоли с FB неудобен. Установщик уже HTML+netsurf-fb.

## 1. Решение

- `doctor/gui/server.py` + `launch-gui.sh` → `/opt/vlanit/doctor/`
- Данные: `vlanit-doctor --json` (поля `desc`, `hint`)
- Запуск: `vlanit-doctor --gui` / `vlanit-doctor-gui`
- Golden: пакеты `netsurf-fb` `netsurf-common`
- Без `/dev/fb0` → exit 2 + подсказка CLI (`VLANIT_FB_SURFACE=sdl` для стенда)

## 2. Отклонённые

- TUI/dialog fallback (v2)
- Fix-actions из GUI
- Слияние с installer `server.py`

## 3. Проверка

```bash
bash tests/unit/test-doctor-gui.sh
# на устройстве с FB:
sudo vlanit-doctor --gui
```

OpenSpec: `openspec/changes/vlanit-doctor-gui/`.
CLI as-built: `docs/specs/1.2.8-vlanit-doctor.md`.
