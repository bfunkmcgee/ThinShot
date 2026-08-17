#!/usr/bin/env python3
"""Land the weapon-raise exactly on the aim pose it hands off to.

    python tools/seal_raise_transition.py <unit_root> [--fix]

`standing_idle_to_readyToFire` is a one-shot: it plays once and then the unit
holds the ReadyToFire rotation and loops the aim-idle on top of it. If the
animation's last frame is not that rotation, the figure snaps the instant the
animation ends. validate_unit_sprites.py check [5] measures the gap; the
shipped units sit at 0-6px and every Kestrel came in at 39-276.

Which end yields is the whole question, and it is decided by what else depends
on the frame:

  * The ReadyToFire rotation has dependents. Every aim-idle here begins on it
    exactly (measured: 0px in all 40 directions), the muzzle offsets in
    Unit.gd are measured off it, and it is the pose held on screen for as long
    as a unit stays in overwatch. So it does not move.
  * The raise animation's last frame has none. It is on screen for 1/36 s.

So the animation yields: its final frame is replaced by the rotation. Note
this does not remove the pose change - that difference exists either way. It
moves it from after the animation, where it reads as a glitch, to inside it,
where it reads as the last 28ms of a fast motion.

The death transition is sealed the other way round - there the corpse rotation
yields to the animation's final frame - for the same reason read in reverse:
the Dead_stance rotation has no other dependents while the death animation is
the richer artefact. See tools/check_dead_stance.py --all.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_unit_sprites import DIRS, silhouette_diff  # noqa: E402

ANIM = "standing_idle_to_readyToFire"
ROT = "ReadyToFire_Stance"


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = Path(sys.argv[1])
    fix = "--fix" in sys.argv

    found = sorted(root.glob("*/animations/%s" % ANIM))
    if not found:
        sys.exit("no %s animation under %s" % (ANIM, root))
    anim = found[0]
    rot = root / ROT / "rotations"
    if not rot.is_dir():
        sys.exit("no %s/rotations under %s" % (ROT, root))

    worst, patched = 0, []
    for d in DIRS:
        frames = sorted((anim / d).glob("frame_*.png"))
        target = rot / ("%s.png" % d)
        if not frames or not target.exists():
            print("  %-12s missing" % d)
            continue
        gap = silhouette_diff(frames[-1], target)
        if gap is None:
            print("  %-12s canvas mismatch - run recanvas_frames.py first" % d)
            continue
        worst = max(worst, gap)
        if gap == 0:
            print("  ok    %-12s already sealed" % d)
            continue
        step = silhouette_diff(frames[-2], frames[-1]) if len(frames) > 1 else None
        print("  gap   %-12s %4dpx to the aim rotation (last step within the "
              "animation was %spx)" % (d, gap, step))
        if fix:
            shutil.copyfile(target, frames[-1])
            patched.append(d)

    if worst == 0:
        print("\nRESULT: PASS (the raise lands on the aim pose in all eight)")
        return
    if not fix:
        print("\nworst gap %dpx. Rerun with --fix." % worst)
        sys.exit(1)
    print("\nsealed %d direction(s): %s" % (len(patched), ", ".join(patched)))
    print("RESULT: FIXED")


if __name__ == "__main__":
    main()
