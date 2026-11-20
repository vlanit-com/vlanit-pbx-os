## 1. Rootfs slim (#29/#30/#32)

- [x] 1.1 `scripts/slim-rootfs.sh`
- [x] 1.2 Вызов из `10-golden-rootfs.sh` и `20-live-rootfs.sh` после Plymouth
- [x] 1.3 Smoke на tmp-дереве

## 2. Live initrd (#31)

- [x] 2.1 `conf.d` MODULES=list + modules (GPU) в live перед mkinitramfs
- [x] 2.2 Убедиться, что hook vlanit-live остаётся источником storage/FS

## 3. Docs / OpenSpec

- [x] 3.1 `docs/specs/iso-size-slim.md` as-built
- [x] 3.2 validate + checkpoint
- [ ] 3.3 `make iso` + QEMU — отдельная сессия (не блокер кода)
