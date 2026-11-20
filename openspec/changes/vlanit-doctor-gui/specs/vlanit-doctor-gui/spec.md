## Purpose

HTML+framebuffer UI для диагностики установленной VLANit PBX OS поверх
существующего CLI `vlanit-doctor`, без изменения контракта проверок.

## ADDED Requirements

### Requirement: GUI launch on installed system

На установленной ОС MUST существовать способ запустить локальный
read-only GUI диагностики (команда `vlanit-doctor --gui` и/или
`vlanit-doctor-gui`). GUI MUST обслуживаться HTTP только на loopback и
отображаться через framebuffer-браузер при наличии `/dev/fb0`.

#### Scenario: Launch with framebuffer

- **WHEN** пользователь с root (или достаточными правами) запускает GUI
  и `/dev/fb0` доступен
- **THEN** открывается HTML-интерфейс doctor на локальном порту через
  framebuffer-браузер

#### Scenario: No framebuffer

- **WHEN** GUI запускают без доступного `/dev/fb0`
- **THEN** процесс MUST завершиться с ненулевым кодом и подсказать
  использовать CLI `vlanit-doctor` (без зависания)

### Requirement: Same checks as CLI

GUI MUST отображать результаты тех же проверок и групп, что даёт
`vlanit-doctor --json` / библиотека checks. Статусы MUST быть
`OK` / `FAIL` / `SKIP`. GUI MUST NOT изменять систему.

#### Scenario: Overview matches JSON result

- **WHEN** прогон завершён
- **THEN** сводка показывает общий результат и перечень групп со
  счётчиками, согласованными с JSON того же прогона

#### Scenario: Group detail and hints

- **WHEN** пользователь открывает группу с FAIL
- **THEN** видны имя проверки, статус и hint исправления (как
  `--fix-hints`), без вывода секретов

### Requirement: CLI unchanged

Существующий CLI (`vlanit-doctor`, флаги `--quiet` / `--fix-hints` /
`--json`, код возврата 0/1) MUST сохранить поведение для SSH, агента и
скриптов.

#### Scenario: Agent still uses CLI

- **WHEN** тест-агент вызывает `vlanit-doctor --quiet`
- **THEN** поведение и смысл кода возврата MUST совпадать с as-built
  CLI (без зависимости от GUI)
