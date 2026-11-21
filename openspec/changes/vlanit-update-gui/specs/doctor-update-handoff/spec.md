## ADDED Requirements

### Requirement: Doctor shows update action when package present

Doctor GUI MUST показывать кнопку запуска обновления только когда
обнаружен кандидат пакета OTA (`vlanit-update-*.tar` + `.asc` на USB
или эквивалент check `ota-package-present` = OK). При отсутствии пакета
кнопка MUST NOT предлагать apply.

#### Scenario: Package on USB

- **WHEN** overview/group updates отрисован и пакет найден
- **THEN** видна кнопка «Обновить» (или эквивалент)

#### Scenario: No package

- **WHEN** пакета нет
- **THEN** кнопки запуска нет; остаётся hint CLI при необходимости

### Requirement: Handoff to vlanit-update

Нажатие кнопки MUST запускать `vlanit-update --gui` с выбранным/единственным
пакетом (не применять обновление внутри процесса doctor). Doctor MUST NOT
передавать auto-YES. Confirm остаётся в updater.

#### Scenario: GUI starts

- **WHEN** handoff успешен и FB доступен
- **THEN** пользователь продолжает в мастере `vlanit-update --gui`

#### Scenario: GUI unavailable

- **WHEN** update GUI не стартовал (нет fb/netsurf)
- **THEN** MUST выполнить fallback: `vlanit-update` в консольном режиме
  на tty; doctor MAY показать сообщение «смотрите консоль»

### Requirement: Doctor checks stay side-effect free for --json/--quiet

Новые checks (`mikopbx-image-pin`, `ota-package-present`, `ota-last-result`)
MUST быть read-only. `vlanit-doctor --json` / `--quiet` MUST NOT запускать
обновление.

#### Scenario: Quiet does not spawn updater

- **WHEN** вызывают `vlanit-doctor --quiet` или `--json`
- **THEN** процесс MUST NOT запускать `vlanit-update` / `--gui`
