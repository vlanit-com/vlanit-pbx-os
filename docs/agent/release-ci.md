# Pack: сборка, CI, релизы

Читать при бампе версии, тегах, CHANGELOG, правках `.github/workflows/`,
подписи ISO, слиянии длинных feature-веток.

## CI `build-iso` (с 1.2.6)

- Workflow: `.github/workflows/build-iso.yml`.
- Push тега `v*` → сборка ISO из исходников тега → GPG-подпись checksums →
  публикация релиза (`--verify-tag`).
- Ручной запуск: `workflow_dispatch` (артефакт или `release: true`).
- **Тег и файлы релиза после публикации не меняются.** Локально ISO не
  пересобирать «поверх» опубликованного релиза — бамп версии → новый тег.
- Подпись: `scripts/sign-release.sh` → `dist/*.iso.sha256`; pub —
  `rootfs/etc-vlanit-release.pub`; секрет CI —
  `RELEASE_GPG_PRIVATE_KEY`. Проверка подписи обязательна при выкладке
  ISO из любого источника.
- Push workflow-файлов требует scope `workflow` у токена
  (`gh auth refresh -s workflow`).

## Бамп и changelog

До тега обновить версию во всех местах: `config/build.yaml`,
`config/release-manifest.yaml`, `rootfs/etc-os-release`, имена ISO,
README, `docs/testing.md`.

Секция `## X.Y.Z` в `CHANGELOG.md` — **до** тега (часть исходников
коммита тега). Без секции workflow опубликует автогенерацию + WARN.

CHANGELOG — через stop-slop: факты, без штампов («починен корнем»,
«вообще», «один источник правды» и т.п.).

Документы: README «Правило релизов (CI)»; идея #11 в
`docs/ideas/engine-package.md` (РЕАЛИЗОВАНО).

## Параллельные ветки

- Миграция на Python — только `feature/python-migration`.
- Полевые фиксы и релизы — короткие ветки → master.
- Перед мерджем миграции в master: rebase на master + полная регрессия
  QEMU. Одновременное редактирование одних файлов в обоих потоках
  запрещено: сначала полевой фикс в master, потом rebase миграции.

## Полевой фидбек

Пункты тестов на железе — спека (корень → решение → проверка) до или
вместе с фиксом; открытые пункты — в notes релиза.
План выезда: `docs/specs/field-visit-plan.md`.
