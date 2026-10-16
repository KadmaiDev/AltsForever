"""Draws the upgrade chevrons: media/up1.tga, up2.tga, up3.tga (one to three green
chevrons stacked, like rank stripes) for minor, decent and major upgrades.

    python tools/make_chevrons.py

Written as uncompressed 32-bit TGA with a bottom-left origin, like the other media files.
"""
import struct
from PIL import Image, ImageDraw

SIZE = 32          # final size, square
SS = 8             # supersampling for smooth edges
S = SIZE * SS
GREEN = (72, 235, 72, 255)
OUTLINE = (0, 0, 0, 220)
WIDTH = 0.12 * S   # stroke
BORDER = 0.07 * S  # dark edge around it, so it shows on any background
RISE = 0.22 * S    # how tall one chevron is
STEP = 0.25 * S    # from one chevron to the next


def chevrons(n):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    height = RISE + (n - 1) * STEP
    top = (S - height) / 2
    shapes = []
    for i in range(n):
        y = top + i * STEP
        shapes.append([(0.16 * S, y + RISE), (0.5 * S, y), (0.84 * S, y + RISE)])
    for pts in shapes:
        d.line(pts, fill=OUTLINE, width=int(WIDTH + 2 * BORDER), joint="curve")
    for pts in shapes:
        d.line(pts, fill=GREEN, width=int(WIDTH), joint="curve")
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def write_tga(img, path):
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    rows = []
    px = img.load()
    for y in range(h - 1, -1, -1):  # bottom row first
        for x in range(w):
            r, g, b, a = px[x, y]
            rows.append(struct.pack("BBBB", b, g, r, a))
    with open(path, "wb") as f:
        f.write(header + b"".join(rows))


if __name__ == "__main__":
    for n in (1, 2, 3):
        write_tga(chevrons(n), "media/up%d.tga" % n)
    print("ok")
