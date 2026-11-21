# Правила проекта VLANit PBX OS

Инструкции для агента/разработчика. Always-on — этот файл. Детали по
подсистемам: `docs/agent/` (читать по таблице ниже; **не** автозагрузка).

## Карта источников

| Нужно | Куда |
|---|---|
| Термины | `CONTEXT.md` |
| Установщик / GUI / UI-доки | `docs/agent/installer-gui.md` |
| CI / релиз / теги / CHANGELOG | `docs/agent/release-ci.md` |
| Какие тесты запускать | `docs/agent/verification.md` |
| OpenSpec change / validate | `docs/agent/openspec.md` |
| Learned / continual-learning | `docs/agent/memory.md` |
| Пауза / смена агента | `docs/agent/checkpoint.template.md` → `openspec/changes/<id>/checkpoint.md` |
| As-built спеки | `docs/specs/` |
| Принятые OpenSpec specs | `openspec/specs/` |
| Полевая/wiki дока | wiki проекта (не дублировать сюда) |

## Обязательное

1. **Документируем настройки устройства** (Golden Image, установщик,
   контейнер, сетевые/системные службы) в тот же коммит или сразу после:
   README («Системные настройки по умолчанию») · спека `docs/specs/`
   (корень → решение → отклонённые → проверка) · `docs/architecture.md`
   при затронутых разделах · ADR при hard-to-reverse + surprising
   trade-off. Формат: что · значение · файл на устройстве · как
   проверяется. Спека → **as-built**.
2. **В git нет бинарников пакетов:** `tools/fetch-tools.sh` + манифест;
   PNG/PF2 и т.п. — генерация при сборке из SVG/скриптов.
3. **Тест-агент** — единый источник id-проверок: новая функциональность →
   проверка агента (одна фича — одна проверка).
4. **Установщик (кроме бампа версии)** — через OpenSpec; во время
   реализации главный источник — `openspec/changes/<id>/`. См.
   `docs/agent/openspec.md`.
5. **Релизные инварианты** (детали — `docs/agent/release-ci.md`): тег и
   артефакты релиза не переписывать; ISO с тега через CI; GPG-проверка
   checksums обязательна; версию бампить везде до тега; CHANGELOG-секция
   до тега, без нейрослопа.
6. **Параллельная работа:** фичи в своей ветке/worktree; не ломать чужой
   master и чужую сборку образа.

## Ponytail (анти-овер-инжиниринг)

Уроки аудита 2026-11-14 (#21–#28):

- Каждый конфиг — с потребителем; мёртвые ключи не копить
  (`config/build.yaml` / `installer.*` — место дефолтов).
- Нет мёртвого кода: символ + вызов; перед коммитом `grep` на имя.
- Нет артефактов в git (`__pycache__`, отчёты, `build/`, `dist/` — gitignore).
- Нет дублей логики: на втором появлении — общий модуль.
- Нет настроек «на вырост»; YAGNI: «что ломается, если удалить?»
- Раз в квартал — ponytail-audit → issue `tech-debt`.

## Сессии и проверки

- Один чат ≈ один эпик (OpenSpec/implement **или** ISO/QEMU **или**
  docs/wiki). Длинный verify — отдельная сессия; состояние — checkpoint.
- Матрица проверок: `docs/agent/verification.md`. Docs-only → без
  `make iso`/QEMU.

## Learned User Preferences

- GUI-установщик: HTML+FB primary; Cursive fallback; dialog не primary.
- UI править в `installer/gui/` / `doctor/gui/` (+fallback при нужде);
  скрины после UI.
- Формы: одна вертикаль полей; схемы дисков не ломать колонки.
- Wiki/user docs установки — под GUI-мастер; текст+скрины вместе.

Правила записи/prune: `docs/agent/memory.md`. **Не** писать сюда текущую
git-ветку или одноразовый статус задачи.

## Learned Workspace Facts

- Контракт установщика: `/run/vlanit/install-config.json`, `vlanit-probe`,
  `install-run.sh`; GUI `installer/gui/`; TUI `installer/tui-cursive/`.
- Экраны: `installer/screens.yaml`; брендинг: `installer/branding/<profile>/`
  (`VLANIT_BRANDING`).
- OpenSpec установщика: `openspec/changes/` → archive → `openspec/specs/`.
- `make iso` в worktree: нужен реальный `build/payload` (symlink часто
  не виден в docker-mount).
- TUI-сборка: `scripts/build-tui.sh` (Docker `rust:1.85-bookworm`) →
  `installer/bin/vlanit-tui`.
- Галереи UI: installer `docs/gui-installer.md` + `shots/`; doctor
  `docs/doctor-gui.md` + `shots/`; OTA `docs/update-gui.md` + `shots/`;
  установка `docs/installation.md`.
- Doctor: CLI `rootfs/vlanit-doctor` + GUI `doctor/gui/`
  (`vlanit-doctor --gui`); проверки в `rootfs/lib-checks.sh`;
  pending NTP / apt-security → WARN (не FAIL); кнопка OTA →
  `vlanit-update --gui` (#58).
- ISO slim: `scripts/slim-rootfs.sh` (locale/doc/plymouth; из golden/live
  rootfs hooks).
- Plymouth без железа: QEMU burst PPM / `virtio-vga` —
  `docs/specs/1.3.2-plymouth-verify.md`.
- Полевой план: `docs/specs/field-visit-plan.md`.
