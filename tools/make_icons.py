"""
Vigía for macOS: the app icon and its twelve theme colours.
Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
Date: November 10, 2026
SPDX-License-Identifier: GPL-2.0-only

The drawing is the one of the Windows version (assets/vigia.png: the lighthouse of Debenne's
design for a lighthouse, c. 1815, The Met, CC0), recoloured the same way: only the coloured
background changes; each pixel's weight is its saturation and the new colour keeps the
original brightness, so edges and texture survive. Then the square is redrawn on the macOS
icon grid: an 824 px rounded square centred on a 1024 px canvas.

Writes:
  icono/icono-1024.png          the default (sky) icon; scripts/compilar.sh makes the .icns
  icono/accents/<key>.png       512 px, one per theme colour, for the Dock and the Theme window
  build/icon_sheet.png          a look at all of them
Keep the keys and colours in sync with Sources/Theme.swift.

Run:  python3 tools/make_icons.py      (needs numpy and Pillow)
"""
import pathlib
import numpy as np
from PIL import Image, ImageDraw

root = pathlib.Path(__file__).resolve().parents[1]
src = root / "assets" / "vigia.png"
(root / "icono" / "accents").mkdir(parents=True, exist_ok=True)
(root / "build").mkdir(exist_ok=True)

ACCENTS = {               # key: icon background (as in the Windows version)
    "gold":   "#C8961E",
    "purple": "#5B2A86",
    "sky":    "#3FA9E6",
    "ember":  "#E8602C",
    "red":    "#C8102E",
    "yellow": "#F2B705",
    "green":  "#1E9E4A",
    "teal":   "#00897B",
    "blue":   "#1F5FD1",
    "pink":   "#D81B79",
    "black":  "#1E1E20",
    "white":  "#F7F7F5",
}

CANVAS, BOX, RADIUS = 1024, 824, 185.4

im = Image.open(src).convert("RGBA")
a = np.asarray(im).astype(np.float32) / 255
rgb = a[..., :3]
mx, mn = rgb.max(-1), rgb.min(-1)
sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
w = np.clip((sat - 0.25) / 0.35, 0, 1)[..., None]
bg_mx = float(np.median(mx[(sat > 0.6) & (a[..., 3] > 0.99)]))
shade = (mx / bg_mx)[..., None]

# the macOS rounded square, drawn at 4x and reduced for smooth edges
m = Image.new("L", (BOX * 4, BOX * 4), 0)
ImageDraw.Draw(m).rounded_rectangle((0, 0, BOX * 4 - 1, BOX * 4 - 1), radius=RADIUS * 4, fill=255)
mask = m.resize((BOX, BOX), Image.LANCZOS)


def on_grid(img):
    """The square drawing, reduced to the 824 px box, cut to the macOS shape, on the 1024 canvas."""
    sq = img.convert("RGB").resize((BOX, BOX), Image.LANCZOS).convert("RGBA")
    sq.putalpha(mask)
    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    o = (CANVAS - BOX) // 2
    out.paste(sq, (o, o), sq)
    return out


sheet = Image.new("RGB", (6 * 170 + 20, 2 * 170 + 20), (246, 246, 248))
for i, (key, hexc) in enumerate(ACCENTS.items()):
    target = np.array([int(hexc[j:j + 2], 16) / 255 for j in (1, 3, 5)], dtype=np.float32)
    new = np.clip(target * shade, 0, 1)
    res = rgb * (1 - w) + new * w
    flat = Image.fromarray((np.concatenate([res, np.ones_like(a[..., 3:])], -1) * 255).round().astype(np.uint8), "RGBA")
    icon = on_grid(flat)
    icon.resize((512, 512), Image.LANCZOS).save(root / "icono" / "accents" / f"{key}.png", optimize=True)
    if key == "sky":
        icon.save(root / "icono" / "icono-1024.png", optimize=True)
    small = icon.resize((150, 150), Image.LANCZOS)
    sheet.paste(small, (20 + (i % 6) * 170, 20 + (i // 6) * 170), small)
sheet.save(root / "build" / "icon_sheet.png")
print("icons written:", ", ".join(ACCENTS))
