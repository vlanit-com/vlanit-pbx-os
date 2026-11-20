## Why

ISO ~900 МиБ; аудит #29–#32: locale/doc/man/plymouth/fonts и жирный
live-initrd (`MODULES=most`) раздувают образ без пользы для appliance.

## What Changes

- Общий `scripts/slim-rootfs.sh`: locale en/ru, doc/man, лишние plymouth
  themes, лишние consolefonts — вызов из golden и live.
- Live initramfs: `MODULES=list` + явный modules-файл (hook vlanit-live
  уже тянет storage/FS/USB); цель — initrd заметно легче.
- As-built `docs/specs/iso-size-slim.md`; при росте/уменьшении — сверить
  с `iso_baseline_mib` (#33).

## Non-goals

- Не бампить версию/релиз в этом change.
- Не трогать payload MikoPBX / golden.tar содержимое сверх slim rootfs.
- Не полевой прогон #14 (только QEMU после сборки в отдельной сессии).

## Capabilities

### New Capabilities
- `iso-size-slim`: политика очистки rootfs и состав live-initrd для
  уменьшения ISO.

### Modified Capabilities

_(нет)_

## Impact

- `scripts/10-golden-rootfs.sh`, `20-live-rootfs.sh`, `30-initramfs.sh`
- Новый `scripts/slim-rootfs.sh`, drop-in initramfs conf + modules для live
- После merge: `make iso` + QEMU regress; возможно снизить
  `iso_baseline_mib`

## Source of truth

Этот change. Issues #29 #30 #31 #32.
