#!/usr/bin/env python3
"""Bring stray frames back onto the unit's canvas.

    python tools/recanvas_frames.py <unit_root> <canvas> [--fix]

Pixel Lab occasionally returns a job on a different canvas than the one it was
asked for - usually a backfill, where the retry loses the original request's
size. It is a quiet failure: the folder is complete, the frame count is right,
the art is correct, and the only symptom is that one direction of one animation
draws a few pixels bigger and lands off its diamond. Essa's aim-idle west came
back 64x64 in a 60x60 unit and nothing else noticed.

The repair is a centred crop or pad, which is the right transform because
Pixel Lab centres the figure horizontally and puts the feet a fixed distance
below centre; take the same number of pixels off (or add to) every edge and
both anchors are preserved. Essa's 64s had the feet at centre+16 and came out
of the crop at centre+16, matching her seven good directions.

It refuses to crop through the figure. If any opaque pixel sits in the margin
that would be removed, that frame is left alone and reported - a clipped
soldier is worse than an oversized one, and it means the frame was not merely
mis-sized and needs regenerating.
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow:  python -m pip install pillow")


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    root = Path(sys.argv[1])
    want = int(sys.argv[2])
    fix = "--fix" in sys.argv

    wrong, fixed, refused = [], [], []
    for p in sorted(root.rglob("*.png")):
        im = Image.open(p)
        if im.size == (want, want):
            continue
        w, h = im.size
        wrong.append((p, w, h))
        if w != h:
            refused.append("%s is %dx%d - not square" % (p.relative_to(root), w, h))
            continue
        pad = (w - want) // 2
        if (w - want) % 2:
            refused.append("%s is %dx%d - odd difference, cannot centre"
                           % (p.relative_to(root), w, h))
            continue
        im = im.convert("RGBA")
        if pad > 0:
            bb = im.split()[3].getbbox()
            if bb and (bb[0] < pad or bb[1] < pad
                       or bb[2] > w - pad or bb[3] > h - pad):
                refused.append("%s would clip the figure (bbox %s, margin %d)"
                               % (p.relative_to(root), bb, pad))
                continue
        if not fix:
            continue
        out = Image.new("RGBA", (want, want), (0, 0, 0, 0))
        out.paste(im.crop((pad, pad, w - pad, h - pad)) if pad > 0 else im,
                  (0, 0) if pad > 0 else (-pad, -pad))
        out.save(p)
        fixed.append(str(p.relative_to(root)))

    if not wrong:
        print("RESULT: PASS (every frame is %dx%d)" % (want, want))
        return
    print("%d frame(s) off canvas:" % len(wrong))
    for p, w, h in wrong[:12]:
        print("  %-70s %dx%d" % (p.relative_to(root), w, h))
    if len(wrong) > 12:
        print("  ... and %d more" % (len(wrong) - 12))
    if not fix:
        print("\nRerun with --fix.")
        sys.exit(1)
    print("\nresized %d" % len(fixed))
    if refused:
        print("REFUSED %d:" % len(refused))
        for x in refused:
            print("  %s" % x)
        print("RESULT: PARTIAL - regenerate the frame(s) above")
        sys.exit(1)
    print("RESULT: FIXED")


if __name__ == "__main__":
    main()
