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

A THIRD detector looks for DEBRIS rather than light: a lump of pixels that is
not connected to the soldier at all, appears for part of the loop, and is gone
again by the end of it. Spent brass and ejection puffs are drawn that way, and
they say the same thing a flash says - the gun is working - without being
bright enough for either rule above to see. Brukk Meshan's north-west aim-idle
carries a detached 35-pixel object for five frames of nine, seven texels clear
of his shoulder and about as tall as his torso, which is very visible on a unit
whose whole job is standing still on overwatch.

Detached art is NOT a defect by itself and the check is deliberately narrow.
Every unit in the project has some - a dropped weapon separating from the body
is most of a death animation, and the biggest examples in the repo (96px on the
Goblin's corpse, 85px on the revolver's) are correct. So this looks only at the
aim-idle, only at components of at least DEBRIS_MIN_PIXELS, and only at ones
that blink; a permanent detached accessory is left alone.

It does flag two shipped units, and it is right about both: Rodar Akai's
north-west frame 8 carries a 13px puff of white smoke that is in no other
frame, and the revolver goblin's east cycle grows one behind his head across
frames 2-6. Neither is repaired here - they are older art and nobody asked -
but the report is the honest output, not a false negative to be tuned away.

Debris is DELETED rather than grafted. That is safe here precisely because it
is disconnected - erasing a separate component cannot take a pixel of the
soldier with it, which is the risk that made deletion the wrong answer for a
flash (see above: Dava's burst had overwritten her barrel).
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

# Debris: a detached lump this big or bigger, sitting at least this far clear
# of the soldier, that is not there for the whole loop. 10 and 3 keep shipped
# art untouched (Rodar's aim-idle strays are 3px, and his 13px one is a single
# transparent texel off his silhouette) while catching Meshan's 14-35px
# ejections, which sit 4-8 texels clear.
DEBRIS_MIN_PIXELS = 10
DEBRIS_MIN_GAP = 2

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


def components(path: Path):
    """Opaque connected components (8-connected), largest first."""
    im = load(path)
    px = im.load()
    w, h = im.size
    seen = [[False] * h for _ in range(w)]
    out = []
    for x0 in range(w):
        for y0 in range(h):
            if px[x0, y0][3] == 0 or seen[x0][y0]:
                continue
            stack = [(x0, y0)]
            seen[x0][y0] = True
            cells = []
            while stack:
                x, y = stack.pop()
                cells.append((x, y))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and not seen[nx][ny]                                 and px[nx, ny][3] > 0:
                            seen[nx][ny] = True
                            stack.append((nx, ny))
            out.append(cells)
    out.sort(key=len, reverse=True)
    return out


def debris_of(path: Path) -> list:
    """Detached lumps big enough and far enough out to read as ejecta."""
    comps = components(path)
    if len(comps) < 2:
        return []
    body = comps[0]
    bx = {c[0] for c in body}
    found = []
    for comp in comps[1:]:
        if len(comp) < DEBRIS_MIN_PIXELS:
            continue
        gap = min(max(abs(x - mx), abs(y - my))
                  for (x, y) in comp for (mx, my) in body)
        if gap >= DEBRIS_MIN_GAP:
            found.append(comp)
    return found


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


def sweep_debris(frames, d, fix, cleared) -> list:
    """Detached ejecta that is not there for the whole loop. Returns the frame
    indices carrying it; deletes them under --fix."""
    per_frame = [debris_of(f) for f in frames]
    hits = [i for i, lumps in enumerate(per_frame) if lumps]
    if not hits or len(hits) == len(frames):
        # Nothing, or something detached in EVERY frame - a permanent accessory
        # rather than ejecta, which this must not touch.
        return []
    if not fix:
        return hits
    # The size and distance thresholds decide whether this DIRECTION is
    # throwing ejecta. Once it is, every detached lump in it goes, however
    # small - the tail of a puff breaking up is the same puff, and Meshan's
    # north-west left a 9px lump and a scatter of single texels behind when
    # only the big ones were taken. Same rule the flash detectors use.
    for i in range(len(frames)):
        lumps = components(frames[i])[1:]
        if not lumps:
            continue
        im = load(frames[i]).copy()
        px = im.load()
        n = 0
        for lump in lumps:
            for (x, y) in lump:
                px[x, y] = (0, 0, 0, 0)
                n += 1
        im.save(frames[i])
        cleared.append("%s/%d(-%dpx)" % (d, i, n))
    return hits


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = Path(sys.argv[1])
    fix = "--fix" in sys.argv

    idles = [d for d in root.rglob("animations/*")
             if d.is_dir() and "readytofire_idle" in d.name.lower().replace("-", "")]
    if not idles:
        sys.exit("no aim-idle set under %s" % root)

    bad, patched, refused, cleared = 0, [], [], []
    for idle in idles:
        for d in DIRS:
            frames = sorted((idle / d).glob("frame_*.png"))
            if not frames:
                continue
            # Debris first: it is deleted rather than grafted, so clearing it
            # up front keeps it out of the brightness figures the flash rules
            # read, and out of any frame later used as a graft source.
            debris = sweep_debris(frames, d, fix, cleared)
            if debris:
                bad += 1
                print("  EJECTA %-11s frames %s  (detached lump(s) >=%dpx, >=%d "
                      "texels clear)%s"
                      % (d, debris, DEBRIS_MIN_PIXELS, DEBRIS_MIN_GAP,
                         "" if fix else " - rerun with --fix"))
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
