# iso-size-slim Specification

## Purpose
Уменьшение размера ISO за счёт очистки golden/live rootfs и узкого набора
модулей в live-initrd без потери кириллицы, темы Plymouth vlanit и
загрузки с USB/virtio.
## Requirements
### Requirement: Shared rootfs slim step

The build MUST run a shared slim step on both golden and live rootfs after
package install and Plymouth branding that: keeps only `en*`/`ru*` under
`/usr/share/locale`; removes `/usr/share/doc` and `/usr/share/man`; keeps
only Plymouth themes `vlanit`, `text`, and `details` (`details` required
by initramfs-tools plymouth hook); keeps only console font files
matching `CyrSlav-DejaVu30x16`.

#### Scenario: Slim invoked from both rootfs scripts

- **WHEN** golden or live rootfs build finishes package and Plymouth setup
- **THEN** `scripts/slim-rootfs.sh` is executed against that rootfs

### Requirement: Live initrd uses MODULES=list

The live initramfs configuration MUST set `MODULES=list` (not `most`) so
that modules come from hooks/`modules` list. The vlanit-live hook MUST
continue to add filesystem and storage modules required for live boot.

#### Scenario: Config drop-in present before mkinitramfs

- **WHEN** `scripts/30-initramfs.sh` builds the live initrd
- **THEN** initramfs-tools sees `MODULES=list` from a vlanit conf.d drop-in
  installed into the live rootfs

