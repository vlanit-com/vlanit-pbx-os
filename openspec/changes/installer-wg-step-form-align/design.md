## Context

See proposal.md — Why. Сейчас WG в `render_system` / `screen_system`;
dialog уже отдельный. Backend: `WG_ENABLED`/`WG_ADDR`/`WG_PORT` →
`configure_target_wireguard`. GUI без JS (NetSurf-fb).

## Goals / Non-Goals

**Goals:**
- Один явный шаг WG во всех UI-фронтах; общий JSON-контракт.
- Формы: колонка меток + ограниченные контролы, читаемые в NetSurf.

**Non-Goals:**
- Смена схемы autoinstall / peers UI.
- Динамический hide полей при `wg=no` (нет JS).
- Бамп версии релиза (отдельный шаг вне этого change).

## Decisions

1. **`installer/screens.yaml`** — единый реестр id/title/enabled/phase
   (`collect|progress|finish`). GUI держит `state["screen_id"]` и
   индекс в списке enabled collect; не `step==N` россыпью.
2. **Handlers map** `id → render_* / validate_*` в server.py; шаблон
   `gui/templates/layout.html` + опционально `gui/templates/<id>.html`
   для статичных кусков; динамика (options) остаётся в handler.
3. **Брендинг** `installer/branding/<profile>/branding.yaml` +
   `theme.css` + logo; `VLANIT_BRANDING` (default: `default`). CSS
   variables инжектятся в layout; structural CSS в `static/style.css`
   через `var(--vlanit-accent, …)`.
4. **Поля addr/port всегда на экране WG** — при `no` бэкенд игнорирует.
5. **Cursive/dialog** — тот же порядок экранов (WG отдельным шагом);
   полный YAML-драйвер Cursive — non-goal (пока handlers в Rust/bash).
6. **CSS форм: `td.lbl` + max-width** под NetSurf.

## Risks / Trade-offs

- [NetSurf CSS quirks] → проверять shots через shot-gui-html.sh + ручной
  взгляд; inline width на `.lbl` как запасной якорь.
- [Сдвиг step id ломает старые закладки] → нет закладок; state в памяти
  процесса сервера.
- [Cursive rebuild нужен для ISO] → `scripts/build-tui.sh` в tasks.

## Migration Plan

Код в ветке `feature/gui-installer`. Autoinstall без изменений YAML.
Откат: вернуть WG в system-экран + старый CSS.
