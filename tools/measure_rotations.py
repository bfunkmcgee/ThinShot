#!/usr/bin/env python3
"""Measure a folder of 8-direction rotations against the shipped figure spec.

    python tools/measure_rotations.py artgen/staging/<batch>

Prints one row per <unit>/rotations/ folder found, and exits non-zero if any
unit misses the spec. Made for the generation loop: a new character sprite is
judged on numbers before anybody spends 576 animation frames on it.

What is checked, and why each one matters (UNIT_ASSET_SPEC.md sections 1 and 5):

  feet           12-16 px below canvas centre, and this is the HARD gate.
                 Unit.SPRITE_SPECS anchors the sprite off it; wrong, and the
                 unit floats above its cell or sinks into it no matter how good
                 the drawing is.
  figure height  ~30 px, and softer than it looks. Measured across the first
                 three Kestrel batches, every generated unit put its feet on
                 the same row as the shipped rifleman and differed only at the
                 CROWN: a soft cap came out at 30, a hood at 32, a steel helmet
                 at 33. That is headwear, not scale. So height over budget is a
                 warning when the feet are anchored correctly and a failure only
                 when they are not - otherwise the tool reports a helmet as a
                 90% oversized soldier, which it did, at some length.
  alpha          binary. Soft edges fringe against the sand.
  palette        <=128 colours. The budget is what keeps the house style flat.

Bounding boxes include held props, which is deliberate: an antenna or a raised
rifle that spikes the box is exactly the thing that will overlap the tile above.
"""
from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

ORDER = ["east", "south-east", "south", "south-west",
         "west", "north-west", "north", "north-east"]

# Measured off the shipped rifleman, which is the anchor every new Kestrel is
# generated against.
SPEC_H = 30
H_TOLERANCE = 2
FEET_MIN, FEET_MAX = 12, 16
MAX_COLOURS = 128


def read_png(path: Path):
    data = path.read_bytes()
    pos = 8
    idat = b""
    width = height = ctype = None
    while pos < len(data):
        length = int.from_bytes(data[pos:pos + 4], "big")
        chunk = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if chunk == b"IHDR":
            width, height = struct.unpack(">II", body[:8])
            ctype = body[9]
        elif chunk == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    channels = 4 if ctype == 6 else 3
    stride = width * channels
    rows = []
    prev = bytearray(stride)
    i = 0
    for _ in range(height):
        filt = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = prev[x]
            c = prev[x - channels] if x >= channels else 0
            if filt == 1:
                line[x] = (line[x] + a) & 255
            elif filt == 2:
                line[x] = (line[x] + b) & 255
            elif filt == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 255
        rows.append(bytes(line))
        prev = line
    return width, height, channels, rows


def measure(folder: Path) -> dict:
    heights, feet, widths = [], [], []
    colours = set()
    soft = 0
    missing = []
    for name in ORDER:
        f = folder / "rotations" / ("%s.png" % name)
        if not f.exists():
            missing.append(name)
            continue
        w, h, ch, rows = read_png(f)
        min_x, max_x, min_y, max_y = w, -1, h, -1
        for y in range(h):
            row = rows[y]
            for x in range(w):
                px = row[x * ch:x * ch + ch]
                alpha = px[3] if ch == 4 else 255
                if alpha == 0:
                    continue
                if alpha != 255:
                    soft += 1
                colours.add(bytes(px[:3]))
                min_x = min(min_x, x); max_x = max(max_x, x)
                min_y = min(min_y, y); max_y = max(max_y, y)
        if max_y < 0:
            missing.append("%s (blank)" % name)
            continue
        heights.append(max_y - min_y + 1)
        widths.append(max_x - min_x + 1)
        feet.append(max_y - h // 2)
    return {
        "h": (min(heights), max(heights)) if heights else (0, 0),
        "w": (min(widths), max(widths)) if widths else (0, 0),
        "feet": (min(feet), max(feet)) if feet else (0, 0),
        "colours": len(colours), "soft": soft, "missing": missing,
    }


def verdict(m: dict) -> tuple:
    """(failures, warnings) - what makes this set unusable, and what to look at.

    The split matters. A set whose feet are anchored and whose crown is a few
    pixels high wears a hat; a set whose feet are wrong cannot be dropped into
    the game at all. Reporting both as "FAIL" taught the reader to ignore the
    word, which is worse than not checking.
    """
    fails, warns = [], []
    if m["missing"]:
        fails.append("missing %s" % ", ".join(m["missing"]))
    anchored = FEET_MIN <= m["feet"][0] and m["feet"][1] <= FEET_MAX
    if not anchored:
        fails.append("feet %d-%d, want %d-%d"
                     % (m["feet"][0], m["feet"][1], FEET_MIN, FEET_MAX))
    if m["soft"]:
        fails.append("%d soft-alpha pixels" % m["soft"])
    if m["colours"] > MAX_COLOURS:
        fails.append("%d colours" % m["colours"])

    over = m["h"][1] - SPEC_H
    if over > H_TOLERANCE:
        note = "+%dpx over the rifleman's crown" % over
        # Feet on the right row and a tall crown is a hat, which is allowed to
        # differ; feet already wrong means the whole figure is mis-scaled.
        (warns if anchored else fails).append(note)
    if m["h"][0] < SPEC_H - H_TOLERANCE - 4:
        fails.append("%dpx shorter than the rifleman" % (SPEC_H - m["h"][0]))
    return fails, warns


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = Path(sys.argv[1])
    units = sorted(p for p in root.iterdir()
                   if p.is_dir() and (p / "rotations").is_dir())
    if not units:
        sys.exit("no <unit>/rotations/ under %s" % root)

    print("spec: figure %d±%d tall, feet %d-%d below centre, binary alpha, "
          "<=%d colours\n" % (SPEC_H, H_TOLERANCE, FEET_MIN, FEET_MAX, MAX_COLOURS))
    print("%-30s %-9s %-9s %-8s %-7s %s"
          % ("unit", "fig h", "fig w", "feet", "cols", "verdict"))
    print("-" * 96)
    failed = 0
    warned = 0
    for unit in units:
        m = measure(unit)
        fails, warns = verdict(m)
        # The shipped anchor is measured but never judged - it defines the spec.
        anchor = unit.name.startswith("_")
        if anchor:
            note = "(anchor)"
        elif fails:
            failed += 1
            note = "FAIL  " + "; ".join(fails + warns)
        elif warns:
            warned += 1
            note = "warn  " + "; ".join(warns)
        else:
            note = "PASS"
        print("%-30s %2d-%-6d %2d-%-6d %2d-%-5d %-7d %s"
              % (unit.name[:30], m["h"][0], m["h"][1], m["w"][0], m["w"][1],
                 m["feet"][0], m["feet"][1], m["colours"], note))
    print()
    if failed:
        print("RESULT: FAIL (%d unit(s), %d warning(s))" % (failed, warned))
    else:
        print("RESULT: PASS%s"
              % ("" if not warned else " (%d warning(s) - headwear, not scale)" % warned))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
