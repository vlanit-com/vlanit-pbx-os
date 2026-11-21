## Context

- OTA: `snapshots/vlanit-update` (USB / path / `--online`), GPG, snapshot
  pre-update, podman load, Image=, health banner.
- Doctor GUI: `doctor/gui/server.py` + netsurf-fb, контракт checks
  read-only для `--json` / `--quiet`.
- Гибрид **C**: doctor показывает статус + handoff; apply только в
  `vlanit-update`.

## Goals / Non-Goals

**Goals:** полевой мастер OTA на FB; кнопка в doctor при наличии пакета;
fallback CLI если GUI не стартовал.

**Non-goals:** см. proposal.

## Decisions

1. **Один движок apply** — этапы 1–8 остаются в `vlanit-update`; GUI
   читает progress (файл/JSON status или шаг через обёртку), не дублирует
   load/GPG.
2. **Handoff** — `POST /action/update` на loopback doctor → spawn
   `vlanit-update --gui <pkg>`; при ненулевом старте GUI →
   `vlanit-update <pkg>` на tty. Confirm YES только внутри updater.
3. **Кнопка видна** iff check/обнаружение: есть `vlanit-update-*.tar`+`.asc`
   (USB). Нет кандидата — кнопки нет.
4. **Новые checks** (read-only): `mikopbx-image-pin`, `ota-package-present`,
   `ota-last-result` → группа `updates`.
5. **Порты** — doctor и update-gui не слушают один порт одновременно
   (разные порты или doctor `/quit` перед FB updater).

## Risks / Trade-offs

- Два netsurf: риск конфликта FB → handoff закрывает doctor UI.
- Spawn от root на консоли: только loopback action; без удалённого API.
- Online OTA в GUI — v1.1 (сначала USB/path).

## Migration

Нет миграции данных. Пакет golden: тот же netsurf-fb уже из #56.
