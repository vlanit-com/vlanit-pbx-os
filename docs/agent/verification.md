# Pack: выбор проверок

Читать перед запуском тестов / ISO / QEMU. **Не отключать** обязательные
релизные и installer safety gates. Длинные ISO/QEMU — по возможности
**отдельная** агентная сессия (не смешивать с docs-only / OpenSpec-draft).

## Матрица по типу изменения

| Характер diff | Минимум | Когда больше |
|---|---|---|
| Только `docs/`, wiki, `docs/agent/`, `CONTEXT.md`, `AGENTS.md` | Ссылки, орфография смысла; если трогали OpenSpec change — `openspec validate` | ISO/QEMU **не** нужны |
| `openspec/config.yaml` / change artifacts | `openspec doctor`; `openspec validate <change>` | — |
| `installer/**`, `tests/unit/**` (без live/rootfs) | Релевантные `tests/unit/*` (напр. `test-config-json.sh`) | Затронут поток GUI/TUI → переснять скрины; ISO — если нужно подтвердить live-пакеты |
| `live/`, `rootfs/`, payload, пакеты в образе, Plymouth, сервисы live | Unit где есть + **ISO** (`make iso`) и целевой QEMU-сценарий | Полный `scripts/regress-full.sh` перед релизом / крупным installer change |
| Бамп версии / тег / release notes | Чеклист [release-ci.md](release-ci.md); CI `build-iso` на теге | Локальный ISO не заменяет публикацию с тега |
| Зеркало дисков / LVM | Сценарий mirror в QEMU / тест-агент | См. `docs/specs/mirror-two-disk.md`, wiki Mirror-Disk-Replace |

## Инструменты (как есть)

- `make check` / `make test` — быстрые проверки Makefile.
- `tests/unit/` — точечные unit (disk, doctor, config-json, quadlet, …).
- `scripts/test-qemu.sh` — QEMU-сценарии.
- `scripts/regress-full.sh` — полный регресс.
- Тест-агент на устройстве: `rootfs/vlanit-test-agent.sh` (id: одна фича —
  одна проверка) — единый источник полевых/стендовых id-проверок.

## Перед ISO/QEMU

1. Остановить ненужные VM (`pgrep`/терминалы QEMU).
2. Worktree: реальный `build/payload` (не битый symlink в docker-mount).
3. После UI, попадающего в ISO: пересобрать ISO и прогнать согласованный
   регресс — в **отдельном** чате/агенте, с checkpoint если смена инструмента.

## Plymouth без железа

QEMU burst screendump (~0.2–0.5 с, сырые PPM, `virtio-vga`). Конфиг-чек ≠
отрисованный splash. Спека: `docs/specs/1.3.2-plymouth-verify.md`.
