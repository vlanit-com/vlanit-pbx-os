# Брендинг VLANit PBX OS

Палитра и логотип — как в wiki
[Брендинг](https://github.com/vlanit-com/vlanit-pbx-os/wiki/Branding).
Исходник логотипа: `branding/vlanit-logo-on-dark.svg`.

## Plymouth (заставка загрузки)

Тема `vlanit` (two-step): логотип — кадры `animation-*` / `throbber-*` и
`watermark.png` (RGB на фоне `#09090b`). Сборка:
`scripts/install-plymouth-theme.sh`. Спека:
[`docs/specs/1.3.2-plymouth-verify.md`](specs/1.3.2-plymouth-verify.md).

Макет сплэша (логотип по центру, как на загрузке при рабочем DRM):

![Plymouth: фирменная заставка](branding/shots/plymouth-splash.png)

Проверка без железа: QEMU burst screendump — см. спеку (screendump ≠
всегда DRM-буфер).
