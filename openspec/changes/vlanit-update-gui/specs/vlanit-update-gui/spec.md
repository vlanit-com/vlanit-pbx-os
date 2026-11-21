## ADDED Requirements

### Requirement: Update GUI launch

На установленной ОС MUST существовать `vlanit-update --gui` (и/или
обёртка), обслуживающий HTML только на loopback и показывающий мастер
через framebuffer-браузер при наличии `/dev/fb0`.

#### Scenario: Launch with framebuffer

- **WHEN** root запускает update GUI и `/dev/fb0` доступен
- **THEN** открывается мастер OTA на локальном порту через FB-браузер

#### Scenario: No framebuffer

- **WHEN** GUI запускают без `/dev/fb0` или без netsurf-fb
- **THEN** процесс MUST завершиться с ненулевым кодом и подсказать CLI
  `vlanit-update` (без зависания)

### Requirement: Wizard steps

GUI MUST проводить пользователя по этапам: выбор пакета → проверки
(GPG, compat, SHA256) → сводка с явным confirm YES → применение
(снапшот, import, Image, restart) → health-check готовности MikoPBX.
GUI MUST NOT применять обновление без confirm YES.
Apply MUST использовать ту же логику доверия, что CLI `vlanit-update`.

#### Scenario: Cancel before YES

- **WHEN** пользователь отменяет на сводке
- **THEN** система MUST остаться без изменений (нет снапшота/import)

#### Scenario: Health OK

- **WHEN** после apply появляется banner готовности MikoPBX в срок
- **THEN** GUI показывает успех и hint `vlanit-rollback`
