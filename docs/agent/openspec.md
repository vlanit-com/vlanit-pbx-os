# Pack: OpenSpec

Проект уже инициализирован (`openspec/`). **Не** запускать `openspec init`
повторно без явной необходимости.

CLI: OpenSpec **1.8.x** (`openspec --version`).

## Источники требований (политика)

| Слой | Роль |
|---|---|
| `openspec/changes/<id>/` (proposal, design, tasks, delta specs) | **Главный** источник во время реализации |
| `openspec/specs/` | Принятые требования после archive |
| `docs/specs/` | As-built / полевые спеки (корень → решение → проверка); не дублировать целиком OpenSpec delta без нужды |
| Wiki | Пользовательская и эксплуатационная документация |

Во время apply: опираться на **tasks** change. Не переписывать план с нуля,
если tasks актуальны. Смена scope → сначала обновить proposal/design/tasks
(и delta spec), потом код.

Non-goals — обязательны в proposal (см. `openspec/config.yaml`).

## Шпаргалка команд

```bash
openspec --version
openspec doctor
openspec list
openspec list --specs
openspec new change <id>          # создать change
openspec status --change <id>
openspec instructions specs --change <id>
openspec validate <id>
openspec archive <id>             # после завершения; обновит openspec/specs
```

Справка: `openspec <cmd> --help`. Глобальный `openspec config` — настройки
CLI пользователя, не путать с проектным `openspec/config.yaml`.

## Checkpoint

При паузе / смене агента / после compaction: обновить
`openspec/changes/<id>/checkpoint.md` по
[checkpoint.template.md](checkpoint.template.md).

## Установщик

Изменения установщика (кроме бампа версии) — через OpenSpec. Домен UI:
[installer-gui.md](installer-gui.md).
