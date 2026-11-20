# Checkpoint: iso-size-slim

| Поле | Значение |
|---|---|
| OpenSpec change | iso-size-slim (#29–#32) |
| Stage | implement / ready for PR |
| Done | slim-rootfs; golden/live hooks; MODULES=list live; docs; unit smoke |
| Remaining | make iso + QEMU (отдельная сессия); archive после merge; возможно ↓ iso_baseline_mib |
| Files touched | scripts/slim-rootfs.sh, 10/20/30-*.sh, live/initramfs-*, docs/specs/iso-size-slim.md, tests/unit/test-slim-rootfs.sh, openspec/changes/iso-size-slim/* |
| Last verify | test-slim-rootfs + openspec validate (pending run) |
| Blockers | нет |
| Next action | validate → PR; ISO в другом чате |
