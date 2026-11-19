## 1. Screen registry + branding

- [x] 1.1 `installer/screens.yaml` — collect/progress/finish + enabled
- [x] 1.2 `installer/branding/default/{branding.yaml,theme.css,logo}`
- [x] 1.3 `gui/templates/layout.html`; server: навигация по реестру, inject brand CSS

## 2. GUI WireGuard + forms

- [x] 2.1 Убрать WG из system; `render_wireguard`; confirm со сводкой WG
- [x] 2.2 CSS: `td.lbl` + max-width контролов (NetSurf)

## 3. Cursive + dialog

- [x] 3.1 `screen_wireguard`; порт editable; dialog система→WG→confirm+порт
- [x] 3.2 `scripts/build-tui.sh` → `installer/bin/vlanit-tui`

## 4. Docs + shots

- [x] 4.1 installation / gui-installer / specs — реестр, брендинг, экраны
- [x] 4.2 Reshoot shots

## 5. Verify

- [x] 5.1 `bash tests/unit/test-config-json.sh`
- [x] 5.2 `openspec validate installer-wg-step-form-align`
