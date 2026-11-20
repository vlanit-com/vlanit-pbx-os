## Context

Issues #29–#32. As-built initrd 1.4.x: один zstd-слой ~54 МиБ,
`MODULES=most` (~900 .ko) — не «early uncompressed cpio» из аудита 1.2.8.
Главный рычаг initrd сейчас — `MODULES=list`.

## Decisions

1. **Один slim-скрипт** для golden и live — без дублирования find/rm.
2. **Plymouth:** оставить `vlanit` + `text`; остальное из plymouth-themes
   удалить после `install-plymouth-theme.sh`.
3. **Fonts:** только `*CyrSlav-DejaVu30x16*` под `vconsole.conf`.
4. **Live MODULES=list** через `conf.d/vlanit-live.conf`; modules-файл =
   GPU list из golden + комментарий, что storage тянет hook `vlanit-live`.
5. **#31 reframed:** не «early cpio», а отказ от `MODULES=most` на live.

## Verify

- Unit: нет (нужен rootfs). Smoke: скрипт на tmp tree.
- Полный `make iso` + QEMU — отдельная сессия / CI; agent checks
  `console-font-cyrillic`, `plymouth-theme-vlanit`.

## Rejected

- `MODULES=dep` на сборочной машине — не портативно для чужого железа.
- dpkg path-exclude — тяжелее сопровождать, чем явный slim после apt.
