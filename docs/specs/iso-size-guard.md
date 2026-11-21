# Спецификация: CI guard размера ISO (#33)

Статус: **as-built** (реализация в ветке `feature/iso-size-guard`).

## 0. Корень

Рост и плавание размера ISO между локальной и CI-сборкой. Нужен
автоматический fail в `build-iso`, если образ заметно больше известного
baseline.

## 1. Решение

- `config/build.yaml` → `output.iso_baseline_mib` (v1.4.2 + doctor GUI
  ≈849; kernel 6.12.117) + `output.iso_size_margin_pct` (5).
- `scripts/check-iso-size.sh` — порог `baseline×(1+margin/100)`, лог,
  топ членов ISO best-effort (7z/xorriso).
- Workflow: шаг после `make iso`, до GPG.

OpenSpec: `openspec/changes/ci-iso-size-guard/`.

## 2. Отклонённые

- Только hard `iso_max_mib` без baseline — хуже трассировка «от чего +5%».
- Fail при отсутствии 7z — ложные падения.

## 3. Проверка

```bash
# under → 0
dd if=/dev/zero of=/tmp/tiny.iso bs=1M count=1 status=none
bash scripts/check-iso-size.sh /tmp/tiny.iso

# over → 1 (нужен файл > порога; или временно iso_baseline_mib: 1)
```

Полный CI — на `workflow_dispatch` / теге после merge.
