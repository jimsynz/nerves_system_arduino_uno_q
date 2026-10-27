"""Nerves logo boot animation for the Arduino UNO Q LED matrix.

Writes the user boot animation image the ArduinoCore-zephyr loader reads at
flash 0x080D0000: four little-endian uint32 {0xBA, len_loop, len_end, 0},
then the loop frames, then the end frames. Frames are 8 rows x 13 columns of
8-bit grey, row-major; the loader plays them at ~60 fps and quantises the
grey into 8 bins, of which bins 5-7 are fully on.

usage: make_nerves_anim.py <out.bin> [--preview]
"""

import struct
import sys

ROWS, COLS = 8, 13
X_OFFSET = 1  # the 11-column logo sits in the middle of the 13 columns

DARK = 110  # the logo's slate stroke
LIGHT = 255  # the logo's light blue stroke

# Each stroke in the order it is drawn, as (x, y) on the 11x8 logo grid.
DARK_PATH = (
    [(1, 7), (0, 7)]
    + [(0, y) for y in range(6, 0, -1)]
    + [(x, 0) for x in range(1, 5)]
    + [(5, 1), (6, 2), (7, 3)]
)
LIGHT_PATH = (
    [(2, 3), (3, 4), (4, 5), (5, 6), (6, 7)]
    + [(x, 7) for x in range(7, 10)]
    + [(10, y) for y in range(6, 0, -1)]
    + [(9, 0), (8, 0)]
)


def frame(lit):
    pixels = bytearray(ROWS * COLS)
    for (x, y), level in lit.items():
        pixels[y * COLS + x + X_OFFSET] = level
    return bytes(pixels)


def full_logo(scale=1.0):
    lit = {p: int(DARK * scale) for p in DARK_PATH}
    lit.update({p: int(LIGHT * scale) for p in LIGHT_PATH})
    return lit


def trace(frames_per_pixel=3):
    lit = {}
    frames = []
    for path, level in ((DARK_PATH, DARK), (LIGHT_PATH, LIGHT)):
        for point in path:
            lit[point] = level
            frames += [frame(lit)] * frames_per_pixel
    return frames


def fade(frames, start, stop):
    return [frame(full_logo(start + (stop - start) * i / (frames - 1))) for i in range(frames)]


def loop():
    return trace() + [frame(full_logo())] * 60 + fade(30, 1.0, 0.0) + [frame({})] * 10


def end():
    return fade(15, 0.0, 1.0) + [frame(full_logo())] * 30 + fade(45, 1.0, 0.0)


def preview(frames, every):
    glyph = {0: ".", DARK: "d", LIGHT: "L"}
    for i in range(0, len(frames), every):
        print(f"frame {i}")
        f = frames[i]
        for y in range(ROWS):
            print(" ".join(glyph.get(v, "+") for v in f[y * COLS:(y + 1) * COLS]))


loop_frames, end_frames = loop(), end()
loop_bytes, end_bytes = b"".join(loop_frames), b"".join(end_frames)
image = struct.pack("<4I", 0xBA, len(loop_bytes), len(end_bytes), 0) + loop_bytes + end_bytes
assert len(image) <= 192 * 1024, "too big for the bootanimation partition"
with open(sys.argv[1], "wb") as out:
    out.write(image)
print(f"{len(image)} bytes: {len(loop_frames)} loop frames ({len(loop_frames) / 60:.1f} s), "
      f"{len(end_frames)} end frames ({len(end_frames) / 60:.1f} s)")
if "--preview" in sys.argv:
    preview([frame(full_logo())], 1)
