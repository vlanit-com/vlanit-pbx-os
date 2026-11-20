# Checkpoint: vlanit-doctor-gui

| Поле | Значение |
|---|---|
| OpenSpec change | `vlanit-doctor-gui` (#56) |
| Stage | implement / verify |
| Done (кратко) | OpenSpec; server+launcher; golden netsurf; unit PASS; README |
| Remaining (кратко) | runbooks 5.2; make iso + baseline; QEMU FB smoke |
| Files touched | `doctor/gui/*`, `rootfs/vlanit-doctor*`, `scripts/10-golden-rootfs.sh`, specs/README/openspec |
| Last verify | `bash tests/unit/test-doctor-gui.sh` → PASS |
| Blockers | — |
| Next action | runbooks mention; затем `make iso` (отдельная сессия) или commit/PR |
