## Why

WireGuard сейчас спрятан внутри экрана «Система» — пользователь не видит
явного выбора «включить после установки или нет». Поля форм GUI уезжают
вправо: NetSurf плохо соблюдает `table-layout: fixed` / `<col>`, контролы
растягиваются на всю ширину карточки.

## What Changes

- Отдельный шаг мастера **WireGuard** (GUI, Cursive, dialog) между
  «Система» и «Подтверждение»: вкл/выкл после установки + адрес/порт.
- **Реестр экранов** (`installer/screens.yaml`): порядок, `enabled`,
  заголовок; GUI навигирует по включённым; шаблоны layout/экранов.
- **Брендинг-профили** (`installer/branding/<name>/`): имя продукта,
  цвета, логотип; переключение `VLANIT_BRANDING`.
- Выравнивание полей форм под NetSurf.
- Доки/галерея под новый поток.
- Контракт autoinstall / JSON `wireguard.*` **не ломается**.

## Capabilities

### New Capabilities

- `gui-installer`: реестр экранов (вкл/выкл), шаблоны, брендинг-профили,
  отдельный WG-шаг, выравнивание HTML-форм без JS.

### Modified Capabilities

<!-- нет существующих openspec/specs — capability новая -->

## Impact

- `installer/gui/server.py`, `installer/gui/static/style.css`
- `installer/tui-cursive/src/main.rs` (+ rebuild `vlanit-tui`)
- `installer/vlanit-installer` (порядок dialog)
- `docs/installation.md`, `docs/gui-installer.md`, `docs/specs/gui-installer.md`
- shots: `docs/gui-installer/shots/`
- Backend `wireguard.sh` / `config-json.sh` / autoinstall YAML — без смены схемы
