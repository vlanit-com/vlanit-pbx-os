# Runbooks (зеркало wiki)

Полевые runbooks со скринами живут в wiki (быстрее править без релиза ISO):

| Тема | Wiki | Issue |
|---|---|---|
| Обновление / откат / бэкап / миграция АТС | [Runbooks](https://github.com/vlanit-com/vlanit-pbx-os/wiki/Runbooks) | #41 |
| Замена диска, зеркало LVM | [Mirror-Disk-Replace](https://github.com/vlanit-com/vlanit-pbx-os/wiki/Mirror-Disk-Replace) | #39 |
| Паритет со старым боксом | [Parity-Matrix](https://github.com/vlanit-com/vlanit-pbx-os/wiki/Parity-Matrix) | #40 |

Скрины (иллюстрации + консоль стенда): `docs/runbooks/shots/` (копия `wiki/images/runbooks-1.4.1/`).

- `00-installer-mirror.png` — GUI мастер, режим зеркала
- `15-lvs-console.png`, `16-doctor.png` — реальный QEMU-консоль (1.3.3)
- `01`–`05` — иллюстрации типового вывода команд (не замена стенда)

Диагностика: CLI `vlanit-doctor` / на консоли с FB — `vlanit-doctor --gui`
(HTML+netsurf; #56). Спека: `docs/specs/vlanit-doctor-gui.md`.

Спеки: `docs/specs/mirror-two-disk.md`, `docs/specs/backup-usb.md`,
`docs/specs/parity-matrix.md`.
