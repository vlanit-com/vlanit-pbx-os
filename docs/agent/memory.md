# Pack: continual-learning / Learned

## Где живёт память

- Секции `## Learned User Preferences` и `## Learned Workspace Facts` в
  корневом `AGENTS.md` (always-on в Cursor).
- Индекс инкремента: `.cursor/hooks/state/continual-learning-index.json`
  (локально; не источник правды для других разработчиков).
- Skill: continual-learning → subagent `agents-memory-updater`.

## Правила записи (обязательно)

1. **Add** — только recurring preference или durable workspace fact с
   подтверждением в коде/доках/спеке. Ссылка на источник, если факт
   архитектурный.
2. **Update** — при изменении факта править существующий bullet, не
   плодить противоречия.
3. **Delete / не писать:**
   - имя текущей git-ветки, ephemeral worktree path как «истина»;
   - текущий номер задачи «сейчас делаем X»;
   - одноразовые пути/таймстемпы сессии;
   - секреты, токены, пароли.
4. Временное состояние задачи — в **checkpoint** change, не в Learned.
5. После updater: человек или агент **просматривает** diff `AGENTS.md` и
   вычищает STALE (ручная проверка; авто-удаление без ревью запрещено).

## Лимит

Держать Learned суммарно коротким (ориентир: ≤15 bullets на обе секции).
При переполнении: перенести устойчивые DOMAIN-факты в packs
(`installer-gui.md` и т.д.), из AGENTS оставить отсылку.
