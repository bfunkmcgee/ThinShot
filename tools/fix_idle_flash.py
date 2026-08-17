#!/usr/bin/env python3
"""Take the gunfire out of an aim-idle loop.

    python tools/fix_idle_flash.py <unit_root> [--fix]

The aim-idle is the cycle a unit plays while it stands with its weapon up and
does nothing. It loops forever, so a muzzle flash drawn into it means the
soldier fires continuously from the moment it raises the weapon until it moves
- a defect that is invisible in any still and unmissable in motion.

Pixel Lab draws one anyway a fair share of the time: the prompt says "aiming"
and the model helpfully shows the weapon working.

DETECTION is colour plus blinking, and it needs both halves.

Colour alone does not work. Flash pixels are bright with almost no blue in
them - measured across these units, real bursts score 135-227 on
(r+g)/2 - b, in yellow (248,253,29) and orange (248,92,7). But bright blond
hair scores nearly as high: Rodar Akai lights up 9-14 pixels in every frame of
every direction and is not firing at all.

What separates them is that a flash BLINKS. A highlight painted into the
character is present in all nine frames; a gunshot is absent in at least one
and obvious in another. So a direction is only reported when some frame is
completely clean and another carries a real burst. Rodar never has a clean
frame in any direction - his hair is always there - and drops out. Dava's west
runs 0,0,8,23,5,18,22,13,0 and does not.

Position deliberately plays no part. An earlier version of this only looked
within a few texels of the muzzle, which is where a flash ought to be, and it
missed Sillae's east entirely: her burst is drawn at x10-15, behind her, while
her rifle ends at x49.

REPAIR grafts the burst's own bounding box from the nearest clean frame, and
touches nothing else - so the frame keeps its own breathing pose and the cycle
keeps moving.

Erasing the flash pixels instead does not work, though it looks like it should
- the burst is additive and sits on transparency. It is not only additive: on
Dava's west the flash overwrote the barrel from x10 to x16, and deleting those
pixels left her muzzle four texels short. The graft puts the barrel back
because it comes from a frame where the weapon was never fired.

Replacing the whole frame does not work either. The nearest clean frame stalls
the cycle for as many frames as were bad, and the frame's mirror across the
loop needs an unlit mirror to exist - Dava's south-east and west each fire in
six frames of nine, so most mirrors are lit too. The graft needs only one
clean frame anywhere in the cycle, which the detection rule guarantees.

A SECOND detector runs alongside it, because the first one has a blind spot of
its own: not every burst is saturated. Sillae's south-east fires a near-white
(250,251,233) that scores 17 on the yellow test and is invisible to it, and
Dava's south fires a pale cream that scores 78. Widening the colour test to
catch those is not an option - it then also catches the sunlit highlights on
every sand-coloured soldier in the game, and shipped units that are provably
clean light up forty transient pixels a frame.

So the second detector is validate_unit_sprites.check_flash's rule, imported
rather than restated: bright pixels counted per frame and compared against the
cycle's own MEDIAN. That finds a pale burst in one or two frames, and is blind
to one firing in six of nine because the median moves with it - which is
exactly the case the first detector handles. Neither rule subsumes the other,
so a direction is repaired if either one reports it.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from statistics import median  # noqa: E402

from validate_unit_sprites import DIRS, hot_pixels, load  # noqa: E402

# The flash palette: bright, and with the blue channel far below the other two.
FLASH_MIN_CHANNEL = 200
FLASH_YELLOW_EXCESS = 125

# How big a burst has to be for a direction to count as firing, so a stray
# texel or two of bright kit does not condemn one. This gates the DIRECTION
# only: once a direction is known to fire, every frame with any flash pixel at
# all is repaired, because a five-pixel spark still reads on screen and there
# is no reason to leave it behind.
FLASH_MIN_PIXELS = 6

# The median-relative rule's slack, matching validate_unit_sprites' 60-canvas
# spec so the two agree on what counts as a spike.
MEDIAN_BIAS = 8


def flash_pixels(path: Path) -> set:
    im = load(path)
    px = im.load()
    w, h = im.size
    out = set()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if max(r, g) >= FLASH_MIN_CHANNEL and (r + g) / 2 - b >= FLASH_YELLOW_EXCESS:
                out.add((x, y))
    return out


def bright_pixels(path: Path) -> set:
    """The looser "bright" set, for locating what the median rule flagged."""
    im = load(path)
    px = im.load()
    out = set()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if (r > 215 and g > 195 and b < 190 and (r + g) / 2 - b > 40) \
                    or (r > 235 and g > 235 and b > 200):
                out.add((x, y))
    return out


def _scan(frames):
    """Run both detectors over a direction's frames.

    Returns (flash sets, flash counts, bright counts, median, lit, by_colour,
    by_median).
    """
    sets = [flash_pixels(f) for f in frames]
    counts = [len(s) for s in sets]
    by_colour = []
    if any(c == 0 for c in counts) and max(counts) >= FLASH_MIN_PIXELS:
        by_colour = [i for i, c in enumerate(counts) if c > 0]
    hot = [hot_pixels(f) for f in frames]
    med = median(hot)
    by_median = [i for i, c in enumerate(hot)
                 if c > max(med * 2.0, med + MEDIAN_BIAS)]
    return (sets, counts, hot, med,
            sorted(set(by_colour) | set(by_median)), by_colour, by_median)


def _repair(frames, lit, clean, sets, patched, d) -> None:
    for i in lit:
        src_i = min(clean, key=lambda c: abs(c - i))
        # What to graft: the saturated burst if there is one, otherwise
        # whatever is bright here and is not bright in the source. The second
        # case is why the source is chosen first - a pale burst is only
        # identifiable by difference against an unfired frame.
        blob = set(sets[i]) or (bright_pixels(frames[i])
                                - bright_pixels(frames[src_i]))
        if not blob:
            continue
        xs = [p[0] for p in blob]
        ys = [p[1] for p in blob]
        # Grown by one: a burst's white-hot core reads as near-white and scores
        # nothing on the yellow test, but sits at its edge.
        box = (max(0, min(xs) - 1), max(0, min(ys) - 1),
               max(xs) + 2, max(ys) + 2)
        dst = load(frames[i]).copy()
        dst.paste(load(frames[src_i]).crop(box), (box[0], box[1]))
        dst.save(frames[i])
        patched.append("%s/%d<-%d" % (d, i, src_i))


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = Path(sys.argv[1])
    fix = "--fix" in sys.argv

    idles = [d for d in root.rglob("animations/*")
             if d.is_dir() and "readytofire_idle" in d.name.lower().replace("-", "")]
    if not idles:
        sys.exit("no aim-idle set under %s" % root)

    bad, patched, refused = 0, [], []
    for idle in idles:
        for d in DIRS:
            frames = sorted((idle / d).glob("frame_*.png"))
            if not frames:
                continue
            sets, counts, hot, med, lit, by_colour, by_median = _scan(frames)
            # A frame is safe to graft FROM only if it carries no saturated
            # burst and sits at or below the cycle's median brightness. Merely
            # being unflagged is not enough: Dava's south frame 1 ran 27 bright
            # against a median of 14 and slipped under the spike threshold by
            # one, and grafting from it would have moved the flash rather than
            # removed it.
            clean = [i for i in range(len(frames))
                     if i not in lit and counts[i] == 0 and hot[i] <= med]
            if not lit:
                note = ""
                if counts and min(counts) > 0:
                    note = "  (lit in every frame: paint, not gunfire)"
                elif any(counts):
                    note = "  (under %d px, too small to be a burst)" % FLASH_MIN_PIXELS
                print("  ok    %-12s %s%s" % (d, counts, note))
                continue
            bad += 1
            which = "+".join(
                [n for n, v in (("colour", by_colour), ("median", by_median)) if v])
            print("  FIRES %-12s frames %s  (%s)  flash %s  bright %s"
                  % (d, lit, which, counts, hot))
            if not fix:
                continue
            if not clean:
                refused.append("%s fires in all %d frames - nothing to graft from,"
                               " regenerate it" % (d, len(frames)))
                continue
            # Repairing moves the median, which can expose a milder burst that
            # was hiding under it - Dava's south went 2,3,8 first and then 1.
            # So repeat until both detectors are quiet or nothing more can be
            # done.
            for _round in range(len(frames)):
                if not lit:
                    break
                if not clean:
                    break
                _repair(frames, lit, clean, sets, patched, d)
                sets, counts, hot, med, lit, _bc, _bm = _scan(frames)
                clean = [i for i in range(len(frames))
                         if i not in lit and counts[i] == 0 and hot[i] <= med]
            if lit:
                refused.append("%s still firing at %s" % (d, lit))
            continue

    if not bad:
        print("\nRESULT: PASS (no aim-idle direction fires)")
        return
    if not fix:
        print("\n%d direction(s) fire while idling. Rerun with --fix." % bad)
        sys.exit(1)
    print("\npatched %d frame(s): %s" % (len(patched), ", ".join(patched)))
    if refused:
        print("REFUSED:")
        for x in refused:
            print("  %s" % x)
        print("RESULT: PARTIAL - regenerate the direction(s) above")
        sys.exit(1)
    print("RESULT: FIXED")


if __name__ == "__main__":
    main()
