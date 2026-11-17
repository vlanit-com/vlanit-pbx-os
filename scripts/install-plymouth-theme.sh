#!/usr/bin/env bash
# scripts/install-plymouth-theme.sh — фирменная тема Plymouth в rootfs.
# Вызывается из 10-golden-rootfs.sh и 20-live-rootfs.sh (единый источник,
# см. AGENTS.md «нет дублированной логики»).
#   $1 — путь к rootfs (требует установленных пакетов plymouth + plymouth-themes)
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS="${1:?usage: install-plymouth-theme.sh <rootfs>}"

# на базе spinner: анимация и диалоги копируются из установленного пакета,
# фон/цвета — бренд (branding/vlanit.plymouth), watermark — логотип
PLY_THEME="$ROOTFS/usr/share/plymouth/themes/vlanit"
mkdir -p "$PLY_THEME"
cp "$ROOTFS"/usr/share/plymouth/themes/spinner/*.png "$PLY_THEME/"
install -D -m 0644 "$PROJECT_ROOT/branding/vlanit.plymouth" \
    "$PLY_THEME/vlanit.plymouth"
python3 - "$PROJECT_ROOT/branding/vlanit-logo-on-dark.svg" \
    "$PLY_THEME/watermark.png" <<'PYEOF'
import sys
import cairosvg
cairosvg.svg2png(url=sys.argv[1], write_to=sys.argv[2],
                 output_width=360, background_color="rgba(0,0,0,0)")
PYEOF
mkdir -p "$ROOTFS/etc/plymouth"
cat > "$ROOTFS/etc/plymouth/plymouthd.conf" <<'EOF'
[Daemon]
Theme=vlanit
ShowDelay=0
EOF
