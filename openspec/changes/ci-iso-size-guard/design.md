## Context

Issue #33. Workflow уже собирает ISO через `make iso`. Нужен дешёвый
post-step без изменения gate подписи/релиза.

Baseline берём от известного хорошего релиза **1.4.1**
(≈897.3 МиБ / 940879872 B) → `iso_baseline_mib: 898`. Margin по умолчанию
**5%** → порог fail ≈ **942.9 МиБ**.

## Decisions

1. **Два ключа, не один `iso_max_mib`:** `iso_baseline_mib` +
   `iso_size_margin_pct` — явно видно «норма» vs «допуск». Hard ceiling =
   `baseline * (100+margin)/100` (арифметика в MiB, сравнение по байтам
   через порог в байтах).
2. **Скрипт в репо** (`scripts/check-iso-size.sh`), не inline в YAML —
   локальный прогон и unit на tmp-файле.
3. **Топ файлов внутри ISO** — диагностика best-effort (`7z l` или
   `xorriso`); отсутствие инструмента = WARN, не fail (fail только по
   размеру).
4. **Шаг workflow** — сразу после `make iso`, до GPG (экономит подпись
   при красном размере; артефакт всё ещё на диске раннера для лога).

## Verify impact

- Unit/smoke: tmp-файл меньше/больше лимита → exit 0/1.
- Полный `make iso` / QEMU — **не** в этом change; зелёный CI на теге
  или `workflow_dispatch` — приёмка на практике.

## Rejected

- Только hard `iso_max_mib` без baseline — хуже объясняет «от чего +5%».
- Падать из-за отсутствия 7z — ложные FAIL на минимальных раннерах.
