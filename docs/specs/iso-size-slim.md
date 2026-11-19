# Спецификация: уменьшение ISO (#29–#32)

Статус: **as-built** (код в `feature/iso-size-slim`; полный `make iso`/QEMU —
отдельная проверка).

## 0. Корень

Лишний вес: locale, doc/man, неиспользуемые plymouth-темы и consolefonts;
live-initrd с `MODULES=most` (~900 модулей). Аудит 1.2.8 про «early cpio»
для текущего 1.4.x не подтвердился as-built: один zstd-слой, раздувание
из-за `MODULES=most`.

## 1. Решение

| Issue | Механизм |
|---|---|
| #29 | `slim-rootfs.sh`: locale только `en*`/`ru*` |
| #30 | удаление `/usr/share/doc`, `/usr/share/man` (+info/lintian) |
| #32 | plymouth: `vlanit`+`text`; fonts: `*CyrSlav-DejaVu30x16*` |
| #31 | live: `MODULES=list` + hook vlanit-live + GPU modules-файл |

Потребители: `10-golden-rootfs.sh`, `20-live-rootfs.sh`, `30-initramfs.sh`.

## 2. Отклонённые

- `MODULES=dep` на build-хосте — не портативно.
- dpkg path-exclude — сложнее явного slim.

## 3. Проверка

```bash
# smoke slim
bash -n scripts/slim-rootfs.sh
# tmp tree
mkdir -p /tmp/slim-t/{usr/share/locale/{de,en_US,ru_RU},usr/share/doc/x,usr/share/man/man1}
bash scripts/slim-rootfs.sh /tmp/slim-t
test ! -d /tmp/slim-t/usr/share/locale/de
test -d /tmp/slim-t/usr/share/locale/en_US
```

Полный критерий issues: `make iso` → меньше размер; QEMU; agent
`console-font-cyrillic`, plymouth; при падении размера — обновить
`iso_baseline_mib` (#33) осознанно вниз.
