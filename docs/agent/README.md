# Agent context packs

Always-on правила — только корневой `AGENTS.md` (Cursor подхватывает его
как workspace rules). Файлы ниже **не** загружаются автоматически: агент
читает их по маршрутизации из `AGENTS.md` или по явному запросу.

| Pack | Когда читать |
|---|---|
| [installer-gui.md](installer-gui.md) | Работа с `installer/`, экранами, брендингом, UI/wiki установки |
| [release-ci.md](release-ci.md) | Релиз, теги, CI `build-iso`, CHANGELOG, параллельные ветки |
| [verification.md](verification.md) | Выбор проверок (unit / ISO / QEMU); Plymouth без железа |
| [openspec.md](openspec.md) | Change/validate/archive; источники требований |
| [memory.md](memory.md) | Continual-learning / Learned в `AGENTS.md` |
| [checkpoint.template.md](checkpoint.template.md) | Шаблон передачи состояния между сессиями/агентами |

## Совместимость

- **Cursor:** always-on = `AGENTS.md`. Packs — по ссылке «прочитай …».
- **Claude Code:** читать `AGENTS.md`, затем нужный pack (`@docs/agent/…`
  или Read). Глобальный `~/.claude/CLAUDE.md` репо не меняет.
- **Kimi:** то же: старт с `AGENTS.md` + pack по задаче. Автоподхват packs
  в этом репо не настроен.

## Checkpoint

Для активного OpenSpec change: `openspec/changes/<id>/checkpoint.md`
(скопировать из template). Не использовать один глобальный `STATUS.md`
на все ветки.
