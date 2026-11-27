# Спека: #60 netsurf surface + #61 vlanit-tui в ISO (as-built)

Статус: **as-built** (HTML primary; TUI/dialog — запасные).

## Контракт UI

1. **Primary:** HTML + `netsurf-fb` при `/dev/fb0` (и наличии бинаря).
2. **Fallback:** `vlanit-tui` (Cursive) → `dialog`.
3. `vlanit.ui=` — только принудительный режим, не меняет дефолтный порядок.

На железе / с рабочим `fb0` ожидается кадр HTML (чёрный/золотой бренд
VLANit). QEMU headless часто не удерживает netsurf (`sdl`+fbcon) —
проверяется цепочка fallback (лог `GUI fail → fallback tui`), primary
не ослабляется.

## #60. Unknown surface `linux` / зависание GUI

**Корень:** Debian `netsurf-fb` 3.11 собран без surface `linux`
(valid: `ram` `sdl` `x` `vnc` `wld`). `launch-gui.sh` ставил `-f linux`
при `/dev/fb0` → netsurf сразу exit; цикл ждал только `gui-done` /
смерть HTTP-сервера → зависание, TUI/dialog не стартовали.

**Решение:**
1. Общий `installer/lib/netsurf-fb.sh` → `/opt/vlanit/lib/netsurf-fb.sh`:
   дефолт при fb0 — `sdl` + `SDL_VIDEODRIVER=fbcon` (без DISPLAY);
   override `VLANIT_FB_SURFACE`.
2. Harden: `chvt 1`, `FRAMEBUFFER`/`SDL_FBDEV=/dev/fb0`, stderr →
   `/run/vlanit/gui-netsurf.log`, grace ~1.2 с, один retry при ранней
   смерти (`vlanit_fb_serve_browser`).
3. Ожидание: смерть netsurf до done → exit ≠0 → `ui-select` fallback
   TUI/dialog. То же в doctor/update launchers.
4. Лог: `UI primary=gui; fallback=tui|dialog`; `GUI fail → fallback tui`.

**Проверка:**
- Unit: `tests/unit/test-netsurf-fb.sh` (env/log helpers без реального fb).
- На fb0: HTML виден через sdl/fbcon; иначе сразу fallback; нет вечного
  экрана `Unknown surface`.
- QEMU: цель — HTML screendump; если netsurf падает — fallback
  задокументирован (см. выше), primary = HTML. Пример headless
  `virtio-vga` на 1.4.6: serial `UI frontend: gui` → `GUI … fallback`,
  кадры `docs/gui-installer/shots-qemu-html-primary/` — синий TUI
  (не ослабляет primary на железе).
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
