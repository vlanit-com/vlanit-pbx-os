# Тестирование VLANit PBX OS

## Запуск

```bash
# unit-тесты (валидация схемы provisioning)
bash tests/unit/test-provision-validation.sh

# интеграционные тесты в QEMU/KVM (UEFI, OVMF)
bash scripts/test-qemu.sh boot      # Т1
bash scripts/test-qemu.sh install   # Т2, Т3, Т4, Т6
bash scripts/test-qemu.sh offline   # Т5
bash scripts/test-qemu.sh errors    # Т7
bash scripts/test-qemu.sh all
```

Требования: `qemu-system-x86_64`, KVM (`/dev/kvm`), OVMF
(`apt-get download ovmf && dpkg -x ovmf_*.deb tools/root`), образ
`dist/VLANit-PBX-1.0-amd64.iso`.

Сценарии используют профиль `tests/integration/autoinstall.yaml`
(автоустановка на /dev/vda, 64 GiB, DHCP, тест-агент `VLANIT_TEST=1`).
Каждый прогон изолируется в `build/qemu/<timestamp>_<pid>/`.

Механика: тестовый ISO собирается из `build/iso-staging` с подложенным
`/autoinstall.yaml`; установка (фаза 1, с ISO) и первая загрузка
(фаза 2, без ISO, общий NVRAM OVMF) — отдельные запуски QEMU. Тест-агент
(`rootfs/vlanit-test-agent.sh`, активен только при `VLANIT_TEST=1` в cmdline)
выполняет 16 проверок на устройстве и публикует `VLANIT_TEST: PASS/FAIL …`,
`VLANIT_TEST_PASS` / `VLANIT_TEST_FAIL` на ttyS0. После успешных проверок
агент перезагружает устройство и проверяет сохранение данных и автозапуск
MikoPBX (REBOOT_TEST_PASS).

## Фактические результаты

### Прогон 2026-11-19, feature/gui-installer 1.4.0 — ВСЁ ЗЕЛЁНОЕ

ISO: `dist/VLANit-PBX-1.4.0-amd64.iso` (892 МиБ). Оркестратор
`scripts/regress-full.sh` (boot → install → offline → errors → ota →
backup → mirror). GUI-shots: `docs/gui-installer/shots/` (пересъём
`scripts/shot-gui-html.sh`).

| Тест | Результат |
|---|---|
| Т1 boot | PASS |
| Т2–Т4/Т6 install | PASS; Т11: install 78s / agent 175s / iso→web 271s (rundir `20261119_090039_3414536`) |
| Т5 offline | PASS |
| Т7a–d errors | PASS |
| Т8 ota | PASS |
| Т9 backup | PASS |
| Т-mirror фазы 1–4 | PASS (raid1, ESP-B, degraded B, replace+resync) |

Итого: 21 PASS, 0 FAIL. Unit: `tests/unit/test-config-json.sh` PASS.
OpenSpec: `installer-wg-step-form-align` validate OK.

### Прогон 2026-11-17 (ночь), финальное принятие feature/two-disk-mirror — ВСЁ ЗЕЛЁНОЕ

| Тест | Результат |
|---|---|
| Т1–Т9 (regress-full на ISO с фиксом «комментарий без #») | PASS: boot, install (агент), offline, errors (Т7a–d), ota (негатив+обновление+откат), backup (бэкап+восстановление+reboot) |
| Т-mirror, фазы 1–4 (финальный ISO: efibootmgr, общий NVRAM, заглушка слота, WARN-doctor, partprobe-фикс) | **PASS**: установка на зеркало (raid1, ESP-B); агент 55 проверок 0 FAIL; degraded-загрузка со второго диска при изъятом A (АТС работает; doctor — WARN-CHECK при ожидаемой деградации); замена диска агентом (lvconvert --repair + resync + ESP на новый диск) — REPLACE_PASS |

Итог цикла: 17 дефектов найдено и исправлено (см. записи ниже и
коммиты ветки), спека mirror-two-disk приведена к as-built, issue #43
закрыт (причина «зависаний» — комментарий без #, не ядро). Т1–Т9 и
mirror проходили на двух последовательных ISO; между ними — изменения
только в тест-агенте и добавлении efibootmgr в golden (однодисковые
сценарии не затронуты: UEFI-запись второго диска им не нужна).


### Прогон 2026-11-16, ветка feature/two-disk-mirror (зеркало двух дисков, #37/#38)

ISO: сборка с финальным стеком (local-block хук, nofail ESP, фоновый
initial sync, малый/полный профиль). Стенд: `test-qemu.sh mirror`
(4 фазы), `regress-full.sh` — оркестратор полного регресса.

| Тест | Результат |
|---|---|
| Т-mirror, фазы 1–2 (прогоны #6/#7, диски 64 ГиБ, продакшн-геометрия) | PASS (установка на зеркало; агент: 54 проверки, 0 FAIL — включая lvm-layout, mirror-raid1-layout, mirror-health, esp-b-present, vlanit-doctor) |
| Т-mirror, фаза 3 (degraded-загрузка со второго диска) | ЧАСТИЧНО: хук local-block активирует vg0 деградированно (корень монтируется, systemd стартует — прогон #7); полный цикл с агентом — после фикса nofail не проходил из-за зависания установки (issue #43) |
| Т-mirror, фаза 4 (замена диска, lvconvert --repair) | ОЖИДАЕТ: блок агента написан, не исполнялся (зависит от фазы 3) |
| Т1 (regress-full, дневной прогон 16.11) | PASS |
| Т2–Т9 (regress-full, дневной прогон 16.11) | НЕ ЗАВЕРШЕНЫ: установка зависла на записи fstab (та же точка, что issue #43, но на ЛИНЕЙНОЙ схеме — зависание не специфично зеркалу; корреляция с дневной загрузкой хоста: ночные прогоны #6/#7 проходили, PSI показывает исторические memory-столлы хоста). Повторить регресс на освобождённом хосте (регресс не блокируется кодом ветки: Т1 и все ночные прогоны зелёные) |

**Дефекты, найденные и исправленные стендом (11):**
1. Метка ESP-B 12 символов — mkfs.vfat отклоняет, set -e молча обрывал
   установку → `VLANIT-ESPB`, команды хранилища `|| die`.
2. Переполнение диска хоста = бесшумный I/O-сталл в ВМ → preflight
   ≥16 ГБ в test-qemu.sh.
3. qcow2 write-lock между фазами → kill_qemu ждёт освобождения.
4. Гонка lvm на ранней загрузке → retry в проверках агента.
5. `grep -qx root` против паддинга `lvs --noheadings` («  root») → trim.
6. Автоактивация udev активирует VG только когда она полна → хук
   local-block принудительной активации vg0 в initramfs (degraded boot).
7. ESP в fstab без nofail → emergency mode при degraded-загрузке → nofail
   + x-systemd.device-timeout=10s.
8. `pv_count` считает метаданные (все PV, включая отсутствующие) →
   присутствие = pv_count − vg_missing_pv_count.
9. Гонка initial sync → фоновый sync (откат ожидания: простаивающий
   массив зависает — issue #43).
10. Магические числа минимума диска → system_size_mib из конфигурации,
    override в autoinstall.yaml (малый профиль стенда).
11. ru-локаль установщика: lvs печатает «100,00» → нормализация запятой
    в sync_percent.

**~~Известная проблема~~ РАЗРЕШЕНО (issue #43):** «зависание установки» — строка комментария без `#` (set -e молча убивал установщика; stderr на tty0). Корреляция со временем суток была ложной.


### Прогон 2026-11-15, ISO VLANit-PBX-1.2.9-amd64.iso (hotfix: цикл порядка загрузки #34)

| Тест | Результат |
|---|---|
| Т1–Т9 полный прогон | PASS (агент: 51 проверка, 0 FAIL, 0 WARN) |

Reboot-фаза честная: агент НЕ стартует АТС вручную (маскировал дефект
порядка загрузки в 1.2.8). reboot-mikopbx-active и no-ordering-cycle
PASS на обеих загрузках. Закрыт #34 (vlanit-atc-secret до mikopbx),
закрыты security-фидбеки (nft skuid до lo accept; пароль исключён из
бэкапа). Попутно: фикс 40-staging (чистка staging/live ломала ISO).

### Прогон 2026-11-14 (вечер), ISO VLANit-PBX-1.2.8-amd64.iso (финальный, #9/#10/#17/#18 + безопасность)

| Тест | Результат |
|---|---|
| Т1–Т9 полный прогон | PASS (агент: **49 проверок**, 0 FAIL, 0 WARN — reboot-api-login стал PASS) |

Закрыты: #10 (/.dockerenv-маркер — provisioning применяет env при каждом
старте), #17 (ExecStartPre порядок + ключи при установке, 0 падений sshd),
#18 (TZ АТС: localtime + TZ + PBXTimezone), #9 (vlanit-doctor — проверка
агентом PASS). Безопасность: пароль в Podman secret (проверки secret/
no-plaintext PASS), nft skuid != 0 (проверка PASS).

### Прогон 2026-11-14, ISO VLANit-PBX-1.2.7-amd64.iso (ponytail-фиксы #21–#23)

| Тест | Результат |
|---|---|
| Т1–Т9 полный прогон | PASS (агент: 42 проверки; WARN-CHECK reboot-api-login — известный upstream-баг #10) |
| Прогон после ponytail #24–#28 (общий vlanit_quadlet, gpg-release-common) | PASS (42 проверки) |

Ядро 6.12.117+deb13-amd64. Закрыты ponytail-issues #21–#23: фантомный
defaults.yaml удалён (system_size_mib → installer.system_size_mib в
build.yaml), артефакты (__pycache__, .gstack) вычищены из git, реализован
Экран 1 «Проверка оборудования» TUI (CPU/RAM/интерфейсы/режим загрузки +
предупреждения). Остальные находки аудита — #24–#28 (бэклог).

### Прогон 2026-11-13, ISO VLANit-PBX-1.2.6-amd64.iso (полевые фиксы, issue #15–#19)

| Тест | Результат |
|---|---|
| Т1–Т9 полный прогон | PASS (агент: 42 проверки; WARN-CHECK reboot-api-login — известный upstream-баг #10) |

Закрыты issue #15–#19 (фидбек теста 1.2.4): владение root (#1, guard сборки),
убрано тестовое правило 10.0.2.0/24 (#2), VLANIT-ENV в [Container] quadlet
(пароль веб-админа реально доходит), StopTimeout/PidsLimit в настройке
/etc/vlanit/mikopbx-container.conf (120 с / 8192), ssh drop-in ssh-keygen -A
(старт без падений), часовой пояс в TUI-мастере (Europe/Moscow default).
Спека: `docs/specs/1.2.6-field-fixes.md`.

### Прогон 2026-11-13, ISO VLANit-PBX-1.2.5-amd64.iso (последнее ядро)

| Тест | Результат |
|---|---|
| Т1–Т9 полный прогон | PASS (агент: 36 проверок; WARN-CHECK reboot-api-login — известный upstream-баг #10) |
| Ядро в образе | 6.12.116+deb13-amd64 (guard: installed==candidate 6.12.116-1), golden.tar.zst 471M → 322M |

Спека: `docs/specs/1.2.5-kernel-latest.md`. Корни: mmdebstrap очищает
resolv.conf (apt в chroot молча не резолвил), security-источники писались
после full-upgrade. Защита: sources до full-upgrade, rm -f висячего
symlink + cp resolv.conf, guard `--only-upgrade linux-image-amd64` с
проверкой Installed==Candidate, явный purge старых ядер, факты с sort -V.

### Прогон 2026-11-13, ISO VLANit-PBX-1.2.4-amd64.iso (system hardening)

| Тест | Результат |
|---|---|
| Т1–Т9 полный прогон | PASS (агент: 36 проверок: hardening 1.2.4 + timezone, консольный шрифт, непустой пароль АТС) |

### Прогон 2026-11-13, ISO VLANit-PBX-1.2.3-amd64.iso (field fixes)

| Тест | Результат |
|---|---|
| Т1–Т9 полный прогон | PASS (агент: 27 проверок, включая apt-security, timesyncd, quadlet 600, SSH_PORT=23) |

Спека: `docs/specs/1.2.3-field-fixes.md`. Известная проблема upstream (зафиксирована веб-QA 1.2.4): provisioning MikoPBX
применяет `WEB_ADMIN_PASSWORD` по маркеру `CLOUD_INSTANCE_ID` — после перезагрузки
хэш пароля сброшен, повторное применение пропускается. Детект: `vlanit-firstboot`
(флаг `/var/lib/vlanit/atc-password-broken`), WARN-проверка `reboot-api-login`.
См. troubleshooting.md.

Запланировано 1.2.4
(вход в систему, firewall, журналы, лимиты, питание):
`docs/specs/1.2.4-system-hardening.md`, ADR-0003.

### Прогон 2026-11-13, ISO VLANit-PBX-1.2.1-amd64.iso (USB-boot, брендинг, чистка)

| Тест | Результат |
|---|---|
| Т1 Загрузка (USB-носитель, эмуляция флешки) | PASS |
| Т2–Т4, Т6 (установка, MikoPBX, Btrfs) | PASS (22 проверки агента; REBOOT_TEST_PASS) |
| Т5 Offline | PASS |
| Т7a–d Ошибки | PASS |
| Т8 Обновление и откат | PASS |
| Т9 Бэкап на USB (носитель 3 ГБ) | PASS |

### Прогон 2026-11-12, ISO VLANit-PBX-1.2-amd64.iso (OTA, безопасность, бэкап)

| Тест | Результат |
|---|---|
| Т1 Загрузка ISO (UEFI) | PASS |
| Т2–Т4, Т6 (установка, MikoPBX, Btrfs) | PASS (22 проверки агента: 16 базовых + WireGuard×3 + безопасность×3; REBOOT_TEST_PASS) |
| Т5 Offline | PASS |
| Т7a–d Ошибки | PASS |
| Т8 Обновление и откат | PASS (негатив: битый пакет отклонён по GPG; снапшот pre-update; обновление; откат; версия возвращена) |
| Т9 Бэкап на USB | PASS (бэкап; модификация данных; восстановление; сохранение после reboot) |

### Прогон 2026-11-12, ISO VLANit-PBX-1.1-amd64.iso (WireGuard + брендинг)

| Тест | Результат |
|---|---|
| Т1 Загрузка ISO (UEFI) | PASS |
| Т2 Установка системы | PASS |
| Т3 Первая загрузка | PASS |
| Т4 MikoPBX | PASS (19 проверок агента: 16 базовых + wireguard-service-enabled, wireguard-interface-up, wireguard-address; REBOOT_TEST_PASS) |
| Т5 Offline | PASS |
| Т6 Btrfs | PASS |
| Т7a–d Ошибки | PASS |

### Прогон 2026-11-12, ISO VLANit-PBX-1.0-amd64.iso (базовый)

| Тест | Результат | Подтверждение |
|---|---|---|
| Т1 Загрузка ISO (UEFI) | PASS | live-среда загружена, установщик запущен |
| Т2 Установка системы | PASS | GPT (EFI 1G/System 40G/Data rest), Btrfs, Golden Image, fstab по UUID, GRUB x86_64-efi |
| Т3 Первая загрузка | PASS | загрузка с диска, hostname, networkd, podman, fstab-uuid |
| Т4 MikoPBX | PASS | quadlet-служба, баннер готовности, веб-интерфейс (из ВМ и с хоста через hostfwd 8443→443), API login v3, автозапуск и данные после reboot |
| Т5 Offline | PASS | полная установка и работа без сетевых устройств |
| Т6 Btrfs | PASS | subvolumes смонтированы, read-only snapshot создан и отображён |
| Т7a несуществующий диск | PASS | отказ установщика (диск не в списке кандидатов) |
| Т7b диск 10 GiB | PASS | отказ (Data < DATA_MIN_GIB=8 при pct=25) |
| Т7c повреждённый payload | PASS | отказ по SHA256 до разметки |
| Т7d установка без NIC | PASS | установка завершена успешно |

Итог агента (1.0): `RESULT PASS (16 checks)`, `VLANIT_TEST_PASS`, `REBOOT_TEST_PASS`.
Логи прогонов: `build/qemu/<run>/`, сводки `build/qemu*_t*.log`.

## Состав проверок агента (16)

hostname, podman, networkd-active, fstab-uuid, btrfs-root,
btrfs-subvol-mikopbx-cf, btrfs-snapshot-create, btrfs-snapshot-list,
quadlet-service, mikopbx-ready-banner, mikopbx-service-active,
mikopbx-webui, mikopbx-api-login, mikopbx-cf-nonempty,
reboot-data-persisted, reboot-mikopbx-active.

## Performance baseline (Т11)

Замер в каждом прогоне Т2 (`scripts/test-qemu.sh install` →
`scripts/perf-baseline.sh`). Отклонение >20% к предыдущей строке —
WARN, не FAIL. Спека: `docs/specs/t11-performance-baseline.md`.
Отключить запись в этот файл: `PERF_BASELINE_UPDATE=0`.

<!-- T11-BASELINE-START -->
| дата | версия | ISO МиБ | install_sec | agent_sec | iso_to_web_sec | заметка |
|---|---|---|---|---|---|---|
| 2026-11-18 | 1.3.1 | 786 | — | — | — | seed: размер dist/VLANit-PBX-1.3.1 до первого T2 на 1.3.2 |
| 2026-11-18 | 1.3.3 | 892 | 98 | 180 | 296 | T2 QEMU web_ok=1 rundir=20261119_011140_3115370 |
| 2026-11-19 | 1.4.0 | 892 | 78 | 175 | 271 | T2 QEMU web_ok=1 rundir=20261119_090039_3414536 |
| 2026-11-19 | 1.4.1 | 777 | 68 | 165 | 251 | T2 QEMU web_ok=1 rundir=20261120_012319_3824154 |
| 2026-11-20 | 1.4.2 | 849 | 78 | 1802 | 1890 | T2 QEMU web_ok=1 rundir=20261121_001948_478400 |
| 2026-11-20 | 1.4.2 | 802 | 259 | 1801 | 2071 | T2 QEMU web_ok=1 rundir=20261121_012440_602981 |
| 2026-11-21 | 1.4.2 | 849 | 104 | 180 | 302 | T2 QEMU web_ok=1 rundir=20261121_112820_822681 |
| 2026-11-24 | 1.4.4 | 850 | 232 | 190 | 440 | T2 QEMU web_ok=1 rundir=20261124_210426_2208579 |
| 2026-11-24 | 1.4.4 | 850 | 159 | 236 | 443 | T2 QEMU web_ok=1 rundir=20261124_220642_2352528 |
| 2026-11-25 | 1.4.5 | 850 | 73 | 210 | 301 | T2 QEMU web_ok=1 rundir=20261125_232713_67839 |
| 2026-11-27 | 1.4.6 | 853 | 73 | 168 | 258 | T2 QEMU web_ok=1 rundir=20261127_201549_32926 |
<!-- T11-BASELINE-END -->

## Интерактивные проверки 1.3.2 (TUI-мастер, стенд QEMU)

Одна фича — одна проверка; проходятся sendkey-проходом мастера:

- installer-gauge-progress — экран установки: gauge со статусами этапов
  и оценкой «осталось ~N мин» (не «~0 мин»); скриншоты
  release-shots/1.3.3/09–11 (регресс темы — 1.3.2/09-11-gauge).
- installer-brand-theme — все диалоги мастера в фирменной теме
  (полный dialogrc 1.3.3: без серого menubox/defaults Debian; backtitle
  версии); скриншоты release-shots/1.3.3/02–08; спека
  `docs/specs/1.3.3-installer-theme.md`; галерея
  `docs/installer-theme-gallery.md`; прогон
  `scripts/shot-installer-walk.sh`.
- disk-pct-geometry — root-LV = system_size_pct % usable-диска: lvs
  root 9.72g + data 29.16g на дисках 40 ГиБ; скриншот release-shots/1.3.2/15-lvs.
- installer-short-password-loop — пароль <8 символов возвращает в поле
  ввода, не обрывает установку (issue #44; факты: ver44/*-retry.png, галерея 10-11).
- firstboot-not-delayed-by-heal — userspace загрузки без ~2,5 мин
  ожидания vlanit-atc-password-heal, firstboot-done при первой загрузке
  (issue #45; факты: userspace 1min 25s, heal в mikopbx.service.wants, firstboot-done при первой загрузке).
- plymouth-brand-splash — фирменная заставка на загрузке live и
  установленной системы (факты — verply).

## GUI / Cursive installer 1.4.0–1.4.1 (идея #12, эпик #46 — закрыт)

Одна фича — одна проверка:

- gui-screens-registry — collect-экраны из `installer/screens.yaml`;
  `enabled: false` пропускает шаг; shots `docs/gui-installer/shots/`.
- gui-branding-profile — `VLANIT_BRANDING=default` подставляет logo/
  theme.css; переключение профиля без правки server.py.
- installer-wg-step — отдельный экран WireGuard (GUI / Cursive / dialog);
  `wireguard.enabled` в install-config; shots 04-system без WG,
  05-wireguard.
- gui-form-align — метки и контролы рядом (`table.form` ~34em);
  NetSurf без JS.
- `tests/unit/test-config-json.sh` — round-trip install-config.json
  (PASS 2026-11-19).
- Autoinstall QEMU — без UI (регрессия бэкенда); полный
  `regress-full` на 1.4.0 PASS.
- OpenSpec `installer-wg-step-form-align` archived 2026-11-19.
- Ручные / follow-up: GUI на железе (`netsurf-fb` ≥2 модели) — вне
  эпика #46. Спека: `docs/specs/gui-installer.md`.

## Не автоматизируется в v1 (ручные сценарии)

- Интерактивный мастер (GUI / Cursive / dialog) на железе/ВМ.
- Установка на реальный SATA/NVMe диск (прогон на физическом устройстве).
- Проверка SIP-регистрации/звонка (требуется SIP-клиент/транк).
- Загрузка Legacy BIOS (не поддерживается в v1; fallback `EFI/BOOT/BOOTX64.EFI` на целевом ESP добавлен).
- Secure Boot (не входит в v1).
- **Полевой первый бокс (#42)** — чеклист: `docs/specs/field-first-box.md`
  (зеркало на двух SSD, паритет, выдержка; результаты — сюда вручную).

## Воспроизводимость сборки

`make clean && make iso` пересобирает ISO полностью из исходников
(проверено: повторная сборка успешна). Побайтовая идентичность не
гарантируется (в манифесте — дата сборки, в rootfs — метки времени пакетов);
контроль целостности — SHA256 артефактов в `config/release-manifest.yaml`
и `dist/*.iso.sha256`.
