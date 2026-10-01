# Draws assets/StudTexture.png: one tile of the blocky "stud" look used in
# Steal a Brainrot / Grow a Garden style lobbies. It's a transparent overlay
# (dark shadow lines + light highlights), so one image works on parts of any
# colour. Upload it in Studio and put its id in Config.Lobby.StudTexture.
#
#   python3 tools/make_stud_texture.py
import os, struct, zlib

SIZE = 128
INSET = 16  # gap between the tile edge and the stud square
EDGE = 7    # width of the square's outline


def pixel(x, y):
    """RGBA for one pixel of the tile."""
    # Thin groove along the tile edges (two tiles side by side = 2px groove)
    if x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1:
        return (0, 0, 0, 40)
    lo, hi = INSET, SIZE - INSET
    if lo <= x < hi and lo <= y < hi:
        # Square outline: shadow on the left and bottom (the "U" look),
        # highlight on the top and right; the inside stays the part colour.
        left, bottom = x < lo + EDGE, y >= hi - EDGE
        top, right = y < lo + EDGE, x >= hi - EDGE
        if left or bottom:
            return (0, 0, 0, 80)
        if top or right:
            return (255, 255, 255, 70)
        return (0, 0, 0, 0)
    return (0, 0, 0, 0)


def write_png(path, width, height, rgba):
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rgba)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "assets", "StudTexture.png")
    write_png(out, SIZE, SIZE, [[pixel(x, y) for x in range(SIZE)] for y in range(SIZE)])
    print("wrote", os.path.normpath(out))
