## 1. OpenSpec / docs

- [x] 1.1 proposal + design + delta spec
- [x] 1.2 `openspec validate vlanit-doctor-gui`
- [x] 1.3 as-built stub `docs/specs/vlanit-doctor-gui.md`

## 2. GUI server (read-only)

- [x] 2.1 `doctor/gui/server.py`: loopback HTTP, overview + group pages
      из `vlanit-doctor --json`
- [x] 2.2 templates/CSS (layout по образцу installer; branding default)
- [x] 2.3 launcher: `vlanit-doctor --gui` / `vlanit-doctor-gui` +
      netsurf-fb; no-fb → ошибка + hint CLI

## 3. Image packaging

- [x] 3.1 поставить `netsurf-fb` (+ deps) в golden (`10-golden-rootfs.sh`)
- [x] 3.2 установить doctor GUI в `/opt/vlanit/doctor/`
- [x] 3.3 сверить размер ISO с `iso_baseline_mib`; bump baseline → 849

## 4. Tests / verify

- [x] 4.1 unit: JSON fixture → HTML (группы, OK/FAIL/SKIP, hint)
- [x] 4.2 unit/smoke launcher no-fb
- [ ] 4.3 `make iso` + QEMU doctor — отдельная сессия (не блокер спеки)

## 5. Ops docs

- [x] 5.1 README: как открыть doctor GUI на консоли
- [x] 5.2 runbooks: упоминание GUI рядом с CLI (скрин — после QEMU)

## 6. Field checks + GUI polish

- [x] 6.1 WARN(3) в контракте; `lvm-mirror-health` деградация → WARN
- [x] 6.2 checks: ntp-synchronized, btrfs-device-stats, efi-esp,
      wireguard-handshake; dns без route → SKIP
- [x] 6.3 GUI: progress (meta-refresh), фильтр `?fail=1`
- [x] 6.4 unit lib + gui обновлены
