# Спецификация: паритет настроек со старым боксом (#40)

Статус: **as-built документ** (1.4.1, 2026-11-19). Полевая сверка железа — #42/#49.

## 0. Корень

Миграция флота с Ubuntu-стика (`pbx-box-standard`) на VLANit PBX OS.
Нужна явная сверка системных настроек: что переносится, что заменено
аналогом, что сознательно отброшено. Источник строк матрицы:
`pbx-box-standard/media/DEBIAN13_MIGRATION_PLAN.md`.

## 1. Решение

Полная таблица и итог — в wiki:
[Parity-Matrix](https://github.com/vlanit-com/vlanit-pbx-os/wiki/Parity-Matrix).

Кратко:

| Класс | Решение |
|---|---|
| Firewall ufw → nftables | DIFF, ADR-0003; порты АТС/SSH/WG открыты явно |
| chrony → timesyncd | OK, аналог |
| avahi/mdns | N/A, не переносим |
| qemu/libvirt на боксе | N/A, appliance не hypervisor |
| mdadm → LVM RAID1 + Btrfs | DIFF, ADR-0004; Т-mirror PASS |
| MikoPBX br0 → host+quadlet | DIFF; данные через backup/restore (#41) |

## 2. Отклонённые альтернативы

- Держать ufw «для Ansible» — нет: VLANit PBX OS не наследует роли стика.
- Тащить avahi «как было» — нет потребителя в схеме IP/WG.
- Ставить qemu/libvirt в golden «на всякий» — YAGNI, раздувает образ.

## 3. Проверка

- Документ в wiki + эта спека в репо.
- Полевой чеклист: `docs/specs/field-visit-plan.md` / field-first-box.
- Закрытие #40 после публикации wiki (код не требуется).
