#!/usr/bin/env python3
"""The generation-loop gate battery: judge frames BEFORE a human looks at them.

    python tools/judge_frames.py rotations <dir> [--sheet out.png] [--zoom 5]
    python tools/judge_frames.py anim <dir> [--gif out.gif] [--fps 8] [--zoom 5]

`rotations` mode expects eight <direction>.png files; `anim` mode expects
eight <direction>/frame_%03d.png trees (the downloaded-bundle shape).

Grown out of the brute and machine-gunner loops (2026-08-23/24), where every
one of these gates caught a real defect that the spec-number checks in
measure_rotations.py are blind to:

  row-0 amputation   >=6 opaque pixels touching canvas row 0 means a raised
                     weapon is CLIPPED - the generator fills its canvas, and
                     language never stops it. Regenerate or rotate; never ship.
  glint / flash      any near-white pixel (min(R,G,B) > 200) on a unit that
                     is not currently firing. On a rotation it reads as a
                     metal glint and looks fine - and then the animator reads
                     it as "this weapon sparks" and grows it into muzzle
                     flash in every animation seeded from that frame. On an
                     animation frame it IS muzzle flash. Both are defects.
  carry-side sweep   centroid-x of the top 14 figure rows only (the full-body
                     centroid is polluted by armour and false-positives),
                     printed per direction so a carried weapon teleporting
                     between hands shows as a sign flip. Applies to CARRIED
                     stances only - an AIMED weapon correctly switches sides
                     as the facing swings.
  feet line          per direction. Within one direction of an animation the
                     feet may bob by design (a stride); between directions a
                     spread is normal (the assembler levels it) but is
                     printed so a rescale does not hide behind it.
  loop seam          anim mode: pixel delta from the last frame back to frame
                     0, next to the per-step deltas. A seam far above the
                     step range is a visible pop at the loop point.

The verdict lines are advisory except AMPUTATED and FLASH, which exit 1: both
mean pixels are wrong, not merely questionable. The sheet/GIF is the artifact
a human judges - the numbers exist so the human only judges plausible frames.
"""
from __future__ import annotations

import argparse
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("judge_frames.py needs Pillow:  pip install Pillow")

ORDER = ["south", "south-west", "west", "north-west",
         "north", "north-east", "east", "south-east"]
ROW0_LIMIT = 6       # opaque pixels on row 0 before it counts as amputation
GLINT_FLOOR = 200    # min(R,G,B) above this = near-white
CARRY_ROWS = 14      # rows below the figure's crown used for the carry sweep
BG = (43, 40, 34, 255)
INK = (200, 195, 180, 255)


def opaque(px, w, h):
    return [(x, y) for y in range(h) for x in range(w) if px[x, y][3] > 8]


def gate(im):
    """Return the numbers one frame is judged on."""
    px = im.load()
    w, h = im.size
    op = opaque(px, w, h)
    top = min(y for _, y in op)
    feet = max(y for _, y in op)
    row0 = sum(1 for x in range(w) if px[x, 0][3] > 8)
    glint = sum(1 for x, y in op if min(px[x, y][:3]) > GLINT_FLOOR)
    band = [(x, y) for x, y in op if y < top + CARRY_ROWS]
    carry = sum(x for x, _ in band) / len(band) - w / 2
    return {"top": top, "feet": feet, "row0": row0, "glint": glint, "carry": carry}


def diff(a, b):
    if a.size != b.size:
        return -1
    pa, pb = a.load(), b.load()
    w, h = a.size
    return sum(1 for y in range(h) for x in range(w)
               if (pa[x, y][3] > 8) != (pb[x, y][3] > 8)
               or (pa[x, y][3] > 8 and pa[x, y][:3] != pb[x, y][:3]))


def verdict(g):
    flags = []
    if g["row0"] >= ROW0_LIMIT:
        flags.append("AMPUTATED")
    elif g["top"] == 0:
        flags.append("kisses")
    if g["glint"]:
        flags.append("FLASH")
    return " ".join(flags) if flags else "clean"


def judge_rotations(root, sheet, zoom):
    failed = False
    print(f"{'dir':11s} canvas    top feet row0 glint carry-x  verdict")
    ims = {}
    for d in ORDER:
        im = Image.open(os.path.join(root, d + ".png")).convert("RGBA")
        ims[d] = im
        g = gate(im)
        v = verdict(g)
        failed = failed or "AMPUTATED" in v or "FLASH" in v
        print(f"{d:11s} {im.size[0]}x{im.size[1]:<5} {g['top']:3d} {g['feet']:4d} "
              f"{g['row0']:4d} {g['glint']:5d} {g['carry']:+7.1f}  {v}")
    if sheet:
        pad = 12
        cw = max(im.size[0] for im in ims.values()) * zoom
        ch = max(im.size[1] for im in ims.values()) * zoom
        out = Image.new("RGBA", ((cw + pad) * 8 + pad, ch + pad + 18), BG)
        draw = ImageDraw.Draw(out)
        for i, d in enumerate(ORDER):
            im = ims[d]
            big = im.resize((im.size[0] * zoom, im.size[1] * zoom), Image.NEAREST)
            out.alpha_composite(big, (pad + i * (cw + pad), pad + ch - big.size[1]))
            draw.text((pad + i * (cw + pad), ch + pad + 2), d, fill=INK)
        out.save(sheet)
        print(f"sheet -> {sheet}")
    return failed


def judge_anim(root, gif, fps, zoom):
    failed = False
    print(f"{'dir':11s} frames canvas    feet-range row0 glint/frame  peak  seam")
    stacks = {}
    for d in ORDER:
        folder = os.path.join(root, d)
        names = sorted(f for f in os.listdir(folder) if f.endswith(".png"))
        ims = [Image.open(os.path.join(folder, f)).convert("RGBA") for f in names]
        stacks[d] = ims
        gates = [gate(im) for im in ims]
        feet = [g["feet"] for g in gates]
        glints = [g["glint"] for g in gates]
        row0 = max(g["row0"] for g in gates)
        deltas = [diff(ims[i], ims[i + 1]) for i in range(len(ims) - 1)]
        seam = diff(ims[-1], ims[0])
        flags = ""
        if row0 >= ROW0_LIMIT:
            flags, failed = flags + " AMPUTATED", True
        if any(glints):
            flags, failed = flags + " FLASH", True
        print(f"{d:11s} {len(ims):5d}  {ims[0].size[0]}x{ims[0].size[1]:<5} "
              f"{min(feet)}-{max(feet):<6} {row0:4d} {glints}  {max(deltas):5d} {seam:5d}{flags}")
    if gif:
        pad = 12
        cw = max(im.size[0] for ims in stacks.values() for im in ims) * zoom
        ch = max(im.size[1] for ims in stacks.values() for im in ims) * zoom
        count = max(len(ims) for ims in stacks.values())
        # ... then hold two beats on frame 0: the in-game snap back to idle,
        # which is where a one-shot that fails to return to neutral shows.
        seq = list(range(count)) + [0, 0]
        frames = []
        for i in seq:
            fr = Image.new("RGBA", ((cw + pad) * 8 + pad, ch + pad + 18), BG)
            draw = ImageDraw.Draw(fr)
            for j, d in enumerate(ORDER):
                ims = stacks[d]
                im = ims[min(i, len(ims) - 1)]
                px = im.load()
                feet = max(y for y in range(im.size[1]) for x in range(im.size[0])
                           if px[x, y][3] > 8)
                big = im.resize((im.size[0] * zoom, im.size[1] * zoom), Image.NEAREST)
                # feet-normalised so the assembler's future leveling does not
                # read as animation bob while judging
                y = pad + ch - (feet + 1) * zoom
                fr.alpha_composite(big, (pad + j * (cw + pad), y))
                draw.text((pad + j * (cw + pad), ch + pad + 2), d, fill=INK)
            frames.append(fr.convert("P", palette=Image.ADAPTIVE))
        frames[0].save(gif, save_all=True, append_images=frames[1:],
                       duration=int(1000 / fps), loop=0, disposal=2)
        print(f"gif -> {gif} ({fps} fps, two-beat snap-back tail)")
    return failed


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("mode", choices=["rotations", "anim"])
    ap.add_argument("root")
    ap.add_argument("--sheet", help="rotations mode: write an NxZOOM compass sheet")
    ap.add_argument("--gif", help="anim mode: write an all-directions GIF")
    ap.add_argument("--fps", type=float, default=8.0)
    ap.add_argument("--zoom", type=int, default=5)
    args = ap.parse_args()
    if args.mode == "rotations":
        failed = judge_rotations(args.root, args.sheet, args.zoom)
    else:
        failed = judge_anim(args.root, args.gif, args.fps, args.zoom)
    print("RESULT: " + ("FAIL" if failed else "PASS"))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
