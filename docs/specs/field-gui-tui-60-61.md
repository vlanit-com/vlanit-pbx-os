# Спека: #60 netsurf surface + #61 vlanit-tui в ISO (as-built)

Статус: **в работе** (`fix/tz-heal-18-45`).

## #60. Unknown surface `linux` / зависание GUI

**Корень:** Debian `netsurf-fb` 3.11 собран без surface `linux`
(valid: `ram` `sdl` `x` `vnc` `wld`). `launch-gui.sh` ставил `-f linux`
при `/dev/fb0` → netsurf сразу exit; цикл ждал только `gui-done` /
смерть HTTP-сервера → зависание, TUI/dialog не стартовали.

**Решение:**
1. Общий `installer/lib/netsurf-fb.sh` → `/opt/vlanit/lib/netsurf-fb.sh`:
   дефолт при fb0 — `sdl` + `SDL_VIDEODRIVER=fbcon` (без DISPLAY);
   override `VLANIT_FB_SURFACE`.
2. Ожидание: смерть netsurf до done → exit ≠0 → `ui-select` fallback
   TUI/dialog. То же в doctor/update launchers.

**Проверка:**
- Unit: `tests/unit/test-netsurf-fb.sh`.
- На fb0: GUI через sdl/fbcon или сразу fallback; нет вечного экрана
  `Unknown surface`.
- `vlanit.ui=dialog` без регрессии.

## #61. `vlanit.ui=tui` сразу обрывается

**Корень:** `installer/bin/vlanit-tui` в gitignore; CI `make iso` внутри
`vlanit-build` без docker/cargo → skip сборки → бинаря нет → TUI fail.

**Решение:**
1. `vlanit-build:1.2` — apt `cargo`/`rustc` 1.85 + `build-essential`.
2. `scripts/build.sh` — hard-fail если нет `installer/bin/vlanit-tui`.
3. `ui-select`: force `tui` без бинаря → return 2 (dialog), не глухой fail.

**Проверка:**
- В squashfs релизного ISO: `opt/vlanit/installer/bin/vlanit-tui`.
- CI log: `[tui] host cargo` → бинарь.
- `vlanit.ui=tui` открывает мастер (при наличии бинаря).
