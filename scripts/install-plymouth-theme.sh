#!/usr/bin/env bash
# scripts/install-plymouth-theme.sh — фирменная тема Plymouth в rootfs.
# Вызывается из 10-golden-rootfs.sh и 20-live-rootfs.sh (единый источник,
# см. AGENTS.md «нет дублированной логики»).
#   $1 — путь к rootfs (требует установленных пакетов plymouth + plymouth-themes)
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:?usage: install-plymouth-theme.sh <rootfs>}"

# на базе spinner: диалоги копируются из пакета; анимация/watermark — логотип
PLY_THEME="$ROOTFS/usr/share/plymouth/themes/vlanit"
mkdir -p "$PLY_THEME"
cp "$ROOTFS"/usr/share/plymouth/themes/spinner/*.png "$PLY_THEME/"
install -D -m 0644 "$PROJECT_ROOT/branding/vlanit.plymouth" \
    "$PLY_THEME/vlanit.plymouth"

python3 - "$PROJECT_ROOT/branding/vlanit-logo-on-dark.svg" "$PLY_THEME" <<'PYEOF'
"""Логотип: непрозрачный RGB на фоне темы; им же заменяем animation/throbber.

two-step рисует animation по центру (VerticalAlignment). Watermark с альфой
на части DRM-путей не композитится — поэтому flatten на #09090b.
"""
import io
import sys
from pathlib import Path

import cairosvg
from PIL import Image

svg = sys.argv[1]
theme = Path(sys.argv[2])
BG = (9, 9, 11, 255)  # BackgroundStartColor 0x09090b


def logo_rgb(width: int) -> Image.Image:
    raw = cairosvg.svg2png(url=svg, output_width=width, background_color="rgba(0,0,0,0)")
    logo = Image.open(io.BytesIO(raw)).convert("RGBA")
    bg = Image.new("RGBA", logo.size, BG)
    return Image.alpha_composite(bg, logo).convert("RGB")


# крупный логотип — главный элемент splash (animation)
hero = logo_rgb(720)
# watermark чуть меньше (дубль снизу/по центру темы)
wm = logo_rgb(520)
wm.save(theme / "watermark.png", "PNG")

for p in sorted(theme.glob("animation-*.png")):
    hero.save(p, "PNG")
for p in sorted(theme.glob("throbber-*.png")):
    hero.save(p, "PNG")
PYEOF

mkdir -p "$ROOTFS/etc/plymouth"
cat > "$ROOTFS/etc/plymouth/plymouthd.conf" <<'EOF'
[Daemon]
Theme=vlanit
ShowDelay=0
EOF

ln -sfn vlanit/vlanit.plymouth \
    "$ROOTFS/usr/share/plymouth/themes/default.plymouth"

install -D -m 0644 "$PROJECT_ROOT/rootfs/etc-modules-load.d-vlanit-drm.conf" \
    "$ROOTFS/etc/modules-load.d/vlanit-drm.conf"
install -D -m 0755 "$PROJECT_ROOT/rootfs/plymouth-wait-drm.sh" \
    "$ROOTFS/usr/local/sbin/vlanit-plymouth-wait-drm"
install -D -m 0644 "$PROJECT_ROOT/rootfs/plymouth-start.service.d-vlanit-drm.conf" \
    "$ROOTFS/etc/systemd/system/plymouth-start.service.d/vlanit-drm.conf"
