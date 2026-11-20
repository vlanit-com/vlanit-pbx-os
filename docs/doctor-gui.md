# Галерея: vlanit-doctor GUI (#56)

HTML + framebuffer (как установщик). Mock-данные для скринов
(не живой прогон на боксе).

```bash
# переснять:
# (см. scripts — пока chrome headless на VLANIT_DOCTOR_CMD fixture)
ls docs/doctor-gui/shots/
```

## 1. Сводка

![Сводка doctor](doctor-gui/shots/01-overview.png)

## 2. Группа system (FAIL + hint)

![Группа system](doctor-gui/shots/02-group-system.png)

## 3. Группа mikopbx

![Группа mikopbx](doctor-gui/shots/03-group-mikopbx.png)

Запуск на устройстве: `sudo vlanit-doctor --gui`.  
Спека: `docs/specs/vlanit-doctor-gui.md`.
