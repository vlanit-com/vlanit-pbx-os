## 1. OpenSpec / docs

- [x] 1.1 proposal + design + delta specs
- [x] 1.2 `openspec validate vlanit-update-gui`
- [x] 1.3 as-built stub `docs/specs/vlanit-update-gui.md`

## 2. Checks (read-only)

- [x] 2.1 `mikopbx-image-pin`, `ota-package-present`, `ota-last-result`
      в `lib-checks.sh` → группа `updates`
- [x] 2.2 unit `test-doctor-lib.sh`

## 3. vlanit-update --gui

- [x] 3.1 `--gui` + launch (netsurf-fb / no-fb → exit + hint CLI)
- [x] 3.2 экраны: пакет → проверки → confirm YES → apply progress → health
- [x] 3.3 apply через существующий CLI-путь (без второго движка)
- [x] 3.4 unit/smoke рендер + no-fb

## 4. Doctor handoff

- [x] 4.1 кнопка «Обновить» только при наличии пакета
- [x] 4.2 `POST` loopback → `vlanit-update --gui`; fallback CLI на tty
- [x] 4.3 doctor не шлёт YES; не меняет Image=
- [x] 4.4 unit handoff / overview

## 5. Packaging / docs / verify

- [x] 5.1 golden: скрипты GUI update (netsurf уже есть)
- [x] 5.2 README / doctor-gui / troubleshooting
- [ ] 5.3 QEMU OTA (+ опц. FB) — отдельная сессия
