# Архитектура VLANit PBX OS

## Общая схема

```
Сборочная машина (docker)
  Dockerfile.build (Debian 13 + mmdebstrap/xorriso/grub + cargo/rustc → vlanit-tui)
    10-golden-rootfs.sh   Golden Image: Debian 13 + podman + VLANit-службы
    20-live-rootfs.sh     Live: ядро + GUI/TUI установщик + netsurf-fb -> squashfs
    30-initramfs.sh       initramfs с кастомным vlanit-init
    40-staging.sh         payload + release-manifest
    50-iso.sh             GRUB UEFI + xorriso -> dist/*.iso

Целевое устройство (UEFI)
  ISO (VLANIT_PBX_OS)
    -> GRUB -> vmlinuz + initrd (vlanit-init)
       -> монтирование /dev/sr0 по метке, squashfs + overlayfs (tmpfs)
       -> switch_root -> systemd -> VLANit Installer
            (primary: HTML+netsurf-fb; fallback: vlanit-tui / dialog)
            -> разметка GPT: EFI 1GiB + LVM PV; vg0: root = system_size_pct %
               usable, data = остаток (минимум Data ≥ DATA_MIN_GIB)
            -> Btrfs поверх LV: @, @var_log, @snapshots | mikopbx-cf, mikopbx-storage
            -> два диска: LV типа raid1 (зеркало), ESP на обоих дисках
            -> развёртывание Golden Image, fstab по UUID
            -> grub-install (x86_64-efi) в chroot, update-initramfs
            -> импорт образа MikoPBX в rootful Podman (offline, из payload)
            -> первая загрузка: vlanit-firstboot -> systemd Quadlet
               -> mikopbx.service (podman, network=host, NET_ADMIN)
                  -> MikoPBX: env provisioning (PBX_NAME, пароль и т.д.)
```

## Golden Image

Переносимый образ файловой системы (tar.zst), а не поблочный образ диска —
поэтому установка возможна на накопители разного размера (минимум —
Data-LV ≥ 8 GiB; продакшен ≥ 50 GiB).

Из Golden Image удаляются все уникальные идентификаторы: machine-id
(пустой файл → systemd генерирует при первой загрузке), SSH host keys,
hostname, журналы. Секретов в образе нет: пароли администратора и веб-админа
задаются установщиком на устройстве.

## Загрузка Live

initramfs собирается initramfs-tools с hook `vlanit-live`, который копирует
busybox, скрипт `/vlanit-init` и модули (squashfs, isofs, loop, overlay,
virtio/sata/nvme, cdrom). `vlanit-init`:

1. монтирует devtmpfs/proc/sysfs;
2. ищет блочное устройство с меткой `VLANIT_PBX_OS` (без фиксированных имён);
3. монтирует ISO и squashfs rootfs;
4. поднимает overlayfs с tmpfs upper (Live-среда не пишет на носитель);
5. `switch_root` в систему; ISO остаётся смонтирован в `/media/vlanit`
   (оттуда установщик берёт payload).

Диагностика: пункт меню GRUB «режим отладки» (`VLANIT_DEBUG=1`) открывает
shell в initramfs.

## Дисковая схема (LVM под Btrfs)

Разметка каждого диска (GPT):

| Раздел | Размер | Тип | Назначение |
|---|---|---|---|
| 1 | 1 GiB | FAT32 (EF00) | ESP: GRUB (+ fallback `BOOTX64.EFI`) |
| 2 | остаток | LVM (8E00) | PV в VG `vg0` |

LV поверх Btrfs (метки ФС сохранены — тулинг по меткам не меняется):

| LV | Размер | ФС | Назначение |
|---|---|---|---|
| `vg0/root` | 40 GiB | Btrfs (`vlanit-system`) | `@` (root), `@var_log`, `@snapshots` |
| `vg0/data` | остаток | Btrfs (`vlanit-data`) | `mikopbx-cf` (конфигурация АТС), `mikopbx-storage` (записи), `.snapshots` |

Два диска — режим «зеркало»: оба диска размечаются одинаково, LV типа
`raid1` (по легу на диск, размер — по меньшему диску), ESP-B — байт-в-байт
копия ESP-A + UEFI-запись (фallback `BOOTX64.EFI` есть на обоих). Смерть
диска не останавливает АТС: хук `/etc/initramfs-tools/scripts/local-block/
vlanit-lvm` принудительно активирует vg0 в initramfs — штатная
автоактивация (udev 69-lvm.rules) срабатывает только когда VG полна
(все PV на месте), без хука при пропаже диска корень не находится.
Активация деградированной VG — дефолт `activation_mode=degraded` (trixie).

Один диск — та же схема, LV типа `linear` (единый кодовый путь установщика;
зркало добавляется потом вторым PV + `lvconvert --type raid1`).

Спека: `docs/specs/mirror-two-disk.md`, решение и цена: `docs/adr/0004`.
fstab генерируется по UUID. Монтирование: `compress=zstd,noatime` для
данных. Снапшоты — команда `vlanit-snapshot` (read-only, `/.snapshots`).

Ограничение v1: rollback работающей БД MikoPBX автоматически не выполняется
(нет подтверждённого механизма согласованного восстановления); снапшоты
создаются перед обновлениями вручную/скриптово.

## Podman и MikoPBX

- Rootful Podman (обоснование: host-network + NET_ADMIN + владение данными,
  максимальная совместимость с docker-run параметрами MikoPBX).
- Автозапуск — **systemd Quadlet** `/etc/containers/systemd/mikopbx.container`
  (Podman 5.4 в trixie, генератор в комплекте). `Restart=always`,
  `TimeoutStopSec=90` (entrypoint MikoPBX корректно обрабатывает SIGTERM).
- `Network=host` (требование MikoPBX для SIP/RTP/fail2ban),
  `AddCapability=NET_ADMIN`.
- Volumes: `/var/spool/mikopbx/cf:/cf`, `/var/spool/mikopbx/storage:/storage`
  (Btrfs subvolumes, владелец `vlanit-www` uid 1001 → `ID_WWW_USER/GROUP`).
- Внешние registry отключены (`unqualified-search-registries = []`) —
  образ импортируется из локального payload, интернет не нужен.

## Provisioning

Декларативная схема VLANit (YAML, `schema_version: 1`), валидация —
`provisioning/vlanit-provision` (python3-yaml):

- **System**: hostname, network (DHCP/static), ssh, storage, container,
  wireguard (enabled, address, listen_port, peers).
- **PBX**: только подтверждённые переменные окружения MikoPBX
  (PBX_NAME, WEB_ADMIN_*, порты и др., см. docs/mikopbx-research.md §3).
  Они применяются механизмом DockerCloud при каждом старте контейнера
  и сохраняются в БД → конфигурация переживает обновление образа.
- Профили расширений (SIP extensions, trunks, routes, IVR и т.д.) заложены
  схемой, но не реализуются до подтверждения соответствующих API-ресурсов.

Идемпотентность: повторный запуск перезаписывает только изменившиеся блоки;
службы применяются через systemd (daemon-reload + restart).

## Systemd-службы (установленная система)

| Юнит | Назначение |
|---|---|
| `vlanit-firstboot.service` | одноразовая первичная настройка (маркер `/var/lib/vlanit/firstboot-done`) |
| `vlanit-atc-password-heal.service` | каждая загрузка: самолечение пароля АТС после upstream-сброса (1.2.8, issue #10) |
| `mikopbx.service` | quadlet-служба контейнера MikoPBX |
| `vlanit-test-agent.service` | только при `VLANIT_TEST=1` в cmdline (QEMU-тесты) |
| `systemd-timesyncd.service` | NTP-синхронизация (1.2.3; FallbackNTP pool.ntp.org) |
| `nftables.service` | firewall: input policy drop, явные разрешения (1.2.4, ADR-0003) |
| `ssh.service.d/00-keygen.conf` | drop-in: `ssh-keygen -A` до старта sshd (1.2.6) |

## Журналы и аудит

- systemd-journald: `Storage=persistent`, каталог `/var/log/journal`
  (Btrfs subvolume `@var_log`), `SystemMaxUse=200M` — журналы переживают
  перезагрузку (1.2.4).
- Аудит безопасности: `/cso` (daily). Отчёт 1.2.2: `.gstack/security-reports/2026-11-13-014500.json`
  (HIGH #1 — пароль в quadlet 0644 — исправлено в 1.2.3 правами 0600).

## Кнопка питания

logind (`/etc/systemd/logind.conf.d/01-vlanit.conf`, 1.2.4):
короткое нажатие — игнор, длинное (>5 с) — штатное выключение.
Апплаенс: случайное нажатие не должно ронять телефонию.

## Контейнер MikoPBX (лимиты, 1.2.6)

`PidsLimit` и `StopTimeout` задаются установщиком из настройки
`/etc/vlanit/mikopbx-container.conf` (дефолты 8192 и 120 с; раньше было
жёстко 4096, стоп 10 с — недостаточно для корректного завершения АТС).
`MemoryMax` — осознанно не задан (жёсткий лимит рискован для длинных звонков).

## Сборка релизов и цепочка доверия (CI, 1.2.6)

- Workflow `build-iso` (`.github/workflows/build-iso.yml`): push тега `v*`
  → сборка ISO из исходников тега в build-контейнере → GPG-подпись
  контрольных сумм → публикация релиза (`--verify-tag`). Тег и файлы после
  публикации не меняются (идея #11).
- Подпись: `scripts/sign-release.sh`, detached-sign `*.iso.sha256` ключом
  релиза. Приватный ключ — GitHub Secret `RELEASE_GPG_PRIVATE_KEY`;
  публичный — `rootfs/etc-vlanit-release.pub` (ed25519,
  `2DACA38E…4CB4`), тот же, что подписывает OTA-пакеты — одна цепочка
  доверия на ISO и OTA.
- Проверка у получателя: `gpg --no-default-keyring --keyring
  rootfs/etc-vlanit-release.pub --verify <file>.sha256.asc`, затем
  `sha256sum -c <file>.sha256`.
- Спека: `docs/specs/1.2.6-ci-release.md`.

## UI установщика (1.4.0)

- Реестр экранов: `installer/screens.yaml` (id / title / enabled / phase).
  GUI ходит только по `enabled: true` collect; handlers в
  `installer/gui/server.py` (`RENDERERS`).
- Шаблоны: `installer/gui/templates/layout.html`.
- Брендинг: `installer/branding/<profile>/` + `VLANIT_BRANDING`
  (default `default`).
- Контракт данных: `/run/vlanit/install-config.json` через
  `vlanit-probe` + `config-json.sh`; этапы — `install-run.sh`.
- Спека / галерея: `docs/specs/gui-installer.md`, `docs/gui-installer.md`.

## Безопасность установщика

- Диски обнаруживаются динамически (`lsblk`), исключаются removable-носители,
  установочный USB и диски с смонтированными разделами.
- Нет фиксированных `/dev/sda|nvme0n1`.
- Деструктивные операции — только после явного подтверждения (интерактив)
  или `confirm: yes` (только автоустановка в тестах).
- Контрольные суммы payload проверяются перед разметкой.
