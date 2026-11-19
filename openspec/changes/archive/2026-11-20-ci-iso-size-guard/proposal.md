## Why

Размер ISO растёт и плавает (±apt-дрейф между локальной и CI-сборкой).
Без порога в CI регрессия размера замечается поздно. Нужен автоматический
guard после `make iso` в `build-iso`.

## What Changes

- Ключи baseline/margin в `config/build.yaml` (`output.iso_baseline_mib`,
  `output.iso_size_margin_pct`).
- Скрипт `scripts/check-iso-size.sh`: размер ISO, сравнение с
  baseline×(1+margin/100), топ крупных файлов внутри ISO в лог.
- Шаг в `.github/workflows/build-iso.yml` после сборки ISO.
- Короткая as-built спека в `docs/specs/`.
- Локальный smoke-тест скрипта на фиктивном файле (без полной сборки ISO).

## Non-goals

- Не ужимать ISO в этом change (locale/doc/initrd — отдельные issues #29–#32).
- Не менять правила тегов/подписи/публикации релиза.
- Не требовать локальный `make iso` для приёмки скрипта.
- Не дублировать политику в wiki.

## Capabilities

### New Capabilities
- `iso-size-guard`: CI/локальная проверка размера собранного ISO против
  baseline из `config/build.yaml` с допускаемым margin %.

### Modified Capabilities

_(нет)_

## Impact

- CI job `build-iso`: новый failing step при превышении лимита.
- `config/build.yaml`: новые ключи (потребитель — скрипт).
- При намеренном росте образа (новые пакеты) — поднять baseline в том же
  PR, иначе CI красный.

## Source of truth

Этот change (`openspec/changes/ci-iso-size-guard/`). Issue #33 — стимул.
`docs/specs/` — as-built после реализации.
