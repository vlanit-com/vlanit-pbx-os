# Спека: Т11 — performance baseline

Статус: **as-built** (2026-11-18). Issue #1. Дорожная карта:
`docs/specs/testing-roadmap-t10-t17.md`.

## Корень

Нет числового следа «стало хуже» между релизами: размер ISO и длительность
Т2 живут только в головах/логах прогонов. Регрессия +20% по времени или
размеру замечается поздно.

## Решение

Host-side замер в `scripts/test-qemu.sh` (сценарий Т2):

| Метрика | Как |
|---|---|
| `iso_mib` | `stat` релизного ISO (`dist/…`) |
| `install_sec` | wall-clock фазы 1: старт QEMU → `VLANIT_INSTALL_DONE` |
| `agent_sec` | wall-clock фазы 2: старт QEMU → `VLANIT_TEST_PASS`/`FAIL` |
| `iso_to_web_sec` | старт фазы 1 → успешный `curl` hostfwd :8443 |

Скрипт `scripts/perf-baseline.sh`:

- `record` — файл прогона + markdown-строка таблицы;
- `append-docs` — строка в `docs/testing.md` между маркерами T11;
- сравнение с предыдущей строкой: отклонение **>20%** → WARN в stderr,
  **не FAIL** (внешние факторы хоста).

По умолчанию после Т2: `PERF_BASELINE_UPDATE=1` (пишет в testing.md).
Отключить: `PERF_BASELINE_UPDATE=0`.

Отклонённые альтернативы:

- Парсинг timestamps serial — в serial их нет; добавлять штампы ради
  Т11 = лишний контракт установщика/агента.
- Авто-FAIL при >20% — ложные красные на загруженном хосте (уже было
  на mirror-регрессе).

## Проверка

```bash
bash scripts/perf-baseline.sh record \
  --out /tmp/perf.txt --version 1.3.2 \
  --iso dist/VLANit-PBX-1.3.2-amd64.iso \
  --install-sec 600 --agent-sec 400 --iso-to-web-sec 1000
# после реального Т2: строка в docs/testing.md, файл build/qemu/<run>/perf-baseline.txt
```

Unit: `bash tests/unit/test-perf-baseline.sh`.
