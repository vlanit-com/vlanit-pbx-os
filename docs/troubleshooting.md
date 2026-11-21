# Диагностика проблем (troubleshooting)

Сначала на установленном устройстве:

```bash
sudo vlanit-doctor --fix-hints    # CLI
sudo vlanit-doctor --gui          # консоль с монитором
```

Руководства: [`doctor-gui.md`](doctor-gui.md), OTA [`update-gui.md`](update-gui.md).  
`--quiet` = 0 при только WARN (degraded зеркало — ожидаемо).

## Не загружается с USB

- Проверьте, что загрузка именно **UEFI** (в Boot Menu пункт с пометкой UEFI).
- Перезапишите USB: `sudo bash scripts/write-usb.sh dist/...iso /dev/sdX`.
- Пункт GRUB «режим отладки» (`VLANIT_DEBUG=1`) даёт shell в initramfs:
  `blkid` — виден ли носитель с меткой `VLANIT_PBX_OS`.

## Live-среда не находит установочный носитель

- `vlanit-init` ищет метку `VLANIT_PBX_OS` на /dev/sr*, затем сканирует
  блочные устройства. На нестандартных контроллерах добавьте модуль ядра
  в `live/initramfs-hook-vlanit-live` и пересоберите (`make iso`).

## Установщик: нет подходящих дисков

- Исключаются removable-носители и диски с смонтированными разделами.
- `lsblk -d -o NAME,TYPE,RM,SIZE,MODEL` — проверьте, что диск TYPE=disk, RM=0.

## Проблемы сети после установки

- Настройки привязаны к MAC-адресу (`/etc/systemd/network/10-vlanit.network`).
- Проверка: `networkctl status`, `journalctl -u systemd-networkd`.
- DNS: `resolvectl status` (systemd-resolved).

## Podman / MikoPBX

**Пароль веб-админа из мастера перестал приниматься после перезагрузки
или жёсткого отключения питания (стандартный admin/admin работает).**
Механизм: env `WEB_ADMIN_PASSWORD` применяется provisioning'ом MikoPBX при
первом старте; маркер применения хранится в `PbxSettings.CLOUD_INSTANCE_ID`
(открытым текстом). Жёсткое отключение питания до checkpoint SQLite WAL
откатывает запись хэша пароля, а маркер выживает → provisioning считает
пароль «уже применённым» и не повторяет.

**Автоматическое самолечение (с 1.2.8, issue #10):** служба
`vlanit-atc-password-heal` на каждой загрузке проверяет логин паролем из
quadlet и при сбросе повторно применяет его через REST v3
(`PATCH /pbxcore/api/v3/general-settings`). Диагностика:

```bash
systemctl status vlanit-atc-password-heal
journalctl -u vlanit-atc-password-heal -b
# флаг сброса (снимается после успешного самолечения):
ls /var/lib/vlanit/atc-password-broken 2>/dev/null
```

Если служба не справилась — ручной обход: задать пароль заново через
консоль MikoPBX (`podman exec -it mikopbx /etc/rc/console_menu`).
Регрессионная проверка: `reboot-api-login` в тест-агенте.


- `systemctl status mikopbx` — служба Quadlet; генератор:
  `systemctl cat mikopbx.service`.
- Образ отсутствует: `zcat /var/lib/vlanit/payload/mikopbx-*.tar.zst | podman load`.
- Веб не поднимается: `podman logs mikopbx | tail -50`; занятые порты
  (host network!): `ss -tlnp`.
- NET_ADMIN: без capability не работают fail2ban/iptables внутри контейнера,
  базовая телефония работает.
- Только rootful: rootless-режим с host-сетью и NET_ADMIN не поддерживается v1.

## Btrfs / снапшоты

- `findmnt /` — btrfs; `btrfs subvolume list /`.
- `vlanit-snapshot create before-update`, `vlanit-snapshot list`.
- Rollback: корневой subvolume переносится (mv), из снапшота создаётся
  новый — перезагрузка обязательна.

## OTA-обновления и откат

- GUI: `vlanit-update --gui` — пошагово [`docs/update-gui.md`](update-gui.md).
  Из doctor (USB-пакет): кнопка **Обновить АТС**.
- `vlanit-update [пакет]` — CLI: USB / `--online`, GPG, compat, SHA256,
  снапшот `pre-update`, apply, health MikoPBX.
- `vlanit-rollback [снапшот]` — откат + reboot.
- Пакет: `scripts/build-update-package.sh` (ключ релиза вне репо).
- Журналы: `/var/log/vlanit-update.log`, `/var/log/vlanit-backup.log`.

## Бэкап на USB

- `vlanit-backup` — останавливает MikoPBX, пишет tar.zst (cf + storage +
  /etc) на USB, запускает контейнер обратно, проверяет health.
- Восстановление: остановить контейнер, распаковать `data.tar.zst`
  с корня (`tar -C / --zstd -xf`), запустить контейнер.

## systemd

- `journalctl -b -p err` — ошибки текущей загрузки.
- `systemctl --failed` — упавшие юниты.
- Первичная настройка: `journalctl -u vlanit-firstboot -b`.

## Сборка

- Журналы шагов: `build/logs/*.log`.
- `make clean` затрагивает только `build/rootfs|live|iso-staging` и `dist`.
- Обновление MikoPBX: `scripts/pull-mikopbx.sh` (проверит digest),
  затем `make iso`.
