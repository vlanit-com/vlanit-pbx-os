#!/usr/bin/env python3
"""SVG → PNG для HTML-установщика (NetSurf/Chromium)."""
from pathlib import Path
import cairosvg

ROOT = Path(__file__).resolve().parents[1]
static = ROOT / "installer" / "gui" / "static"
static.mkdir(parents=True, exist_ok=True)

for name in ("disk-scheme", "mirror-scheme"):
    svg = static / f"{name}.svg"
    png = static / f"{name}.png"
    cairosvg.svg2png(url=str(svg), write_to=str(png), output_width=640)
    print(f"{png.name} {png.stat().st_size}")

logo_svg = ROOT / "branding" / "vlanit-logo-on-dark.svg"
logo_png = static / "logo.png"
if logo_svg.is_file():
    cairosvg.svg2png(url=str(logo_svg), write_to=str(logo_png), output_width=320)
    print(f"{logo_png.name} {logo_png.stat().st_size}")
