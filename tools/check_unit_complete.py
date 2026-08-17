#!/usr/bin/env python3
"""Verify a downloaded PixelLab character bundle is a complete unit.

    python tools/check_unit_complete.py artgen/staging/.../<unit>

A unit is 24 static rotations plus one 9-frame set per direction for every
animation (UNIT_ASSET_SPEC.md §3). This counts what is actually on disk and
names exactly what is missing, because the failure mode is quiet: individual
generation jobs fail, the download still succeeds, and the folder looks right
until an animation truncates mid-cycle in game.

The loader counts frames up until a file is missing, so a gap does not error -
it silently shortens the cycle. That is why this checks frame CONTINUITY from
000 and not merely the file count.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from measure_rotations import ORDER  # noqa: E402

FRAMES = 9
# The base state is called `Idle` in a downloaded bundle and is renamed after
# the unit on assembly (UNIT_ASSET_SPEC.md §4), so it is found rather than
# named and this works on a staging tree or a shipped one.
STATIC_SETS = ["ReadyToFire_Stance", "Dead_stance"]


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = Path(sys.argv[1])
    problems = []
    total = 0

    base = next((d for d in sorted(root.iterdir())
                 if d.is_dir() and d.name not in STATIC_SETS
                 and (d / "rotations").is_dir()), None)
    if base is None:
        sys.exit("no base state (a folder with rotations/) under %s" % root)
    rotation_sets = [base.name + "/rotations"] + \
                    [s + "/rotations" for s in STATIC_SETS]

    for rel in rotation_sets:
        d = root / rel
        if not d.is_dir():
            problems.append("%s: MISSING FOLDER" % rel)
            continue
        for name in ORDER:
            if (d / ("%s.png" % name)).exists():
                total += 1
            else:
                problems.append("%s/%s.png missing" % (rel, name))

    anim_roots = [base / "animations",
                  root / "ReadyToFire_Stance" / "animations"]
    sets = 0
    for ar in anim_roots:
        if not ar.is_dir():
            continue
        for s in sorted(p for p in ar.iterdir() if p.is_dir()):
            sets += 1
            for name in ORDER:
                d = s / name
                if not d.is_dir():
                    problems.append("%s/%s: NO DIRECTION" % (s.name, name))
                    continue
                # Continuity from frame_000, not just a count.
                n = 0
                while (d / ("frame_%03d.png" % n)).exists():
                    n += 1
                total += n
                if n != FRAMES:
                    problems.append("%s/%s: %d frames, want %d"
                                    % (s.name, name, n, FRAMES))

    expect = len(rotation_sets) * len(ORDER) + sets * len(ORDER) * FRAMES
    print("%s" % root)
    print("  %d animation set(s), %d png(s) on disk, %d expected"
          % (sets, total, expect))
    if problems:
        print("\n  %d problem(s):" % len(problems))
        for p in problems:
            print("    %s" % p)
        print("\nRESULT: FAIL")
        sys.exit(1)
    print("\nRESULT: PASS")


if __name__ == "__main__":
    main()
