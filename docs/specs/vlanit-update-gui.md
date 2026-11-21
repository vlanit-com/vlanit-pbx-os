# Спека: vlanit-update GUI + handoff из doctor (issue #58)

Статус: **as-built (stub)** — реализация в `feature/vlanit-update-gui`.

## 0. Корень

OTA на консоли — CLI. Doctor GUI (#56) — только диагностика. Нужен
мастер обновления на FB и кнопка в doctor при наличии USB-пакета.

## 1. Решение

Гибрид C (OpenSpec `vlanit-update-gui`):

- `vlanit-update --gui` → `/opt/vlanit/update/launch-gui.sh` + `server.py`
  (порт 8767): пакет → confirm YES → `VLANIT_ASSUME_YES=1 vlanit-update`
- Doctor: кнопка «Обновить АТС» если `ota_list_usb_packages`; handoff
  `--gui`, при exit 2 → CLI на tty
- Checks: `mikopbx-image-pin`, `ota-package-present`, `ota-last-result`

## 2. Отклонённые

- Apply внутри doctor HTTP; auto-YES; сборочный bump #12 в GUI

## 3. Проверка

```bash
bash tests/unit/test-doctor-lib.sh
bash tests/unit/test-doctor-gui.sh
bash tests/unit/test-update-gui.sh
# QEMU: scripts/test-qemu.sh ota
```
