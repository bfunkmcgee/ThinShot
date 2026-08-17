#!/usr/bin/env python3
"""Find corpses that are still standing up.

    python tools/check_dead_stance.py <unit_root> [--fix | --all]

`<unit_root>` is a downloaded PixelLab character bundle: `Dead_stance/rotations/`
beside `Idle/animations/standing_idle_to_dead/`.

Why this exists: `create_character_state` with "lying dead on the ground"
preserves the source pose in some directions and lays the body down in others.
On the first Kestrel it came back lying in 5 of 8 and still standing in south,
south-west and north. A unit that falls over at the end of its death animation
and then pops upright as the corpse rotation takes over is the kind of bug that
survives every still-image review and is obvious the first time somebody dies.

The test is the bounding box, not the pixels: a body lying on the ground is
WIDER than it is tall, and a standing one is not. That reads the pose without
knowing anything about the art.

`--fix` replaces the offending direction with the final frame of that
direction's death animation, which is by definition the pose the unit just
landed in. UNIT_ASSET_SPEC.md §4 permits it as long as the deviation is written
into a `note` on the state in metadata.json - several shipped units did exactly
this. It is a slightly flatter read than a purpose-drawn corpse, which is the
price of it always being available and perfectly continuous.

`--all` substitutes all eight rather than only the standing ones, and is the
better default. Fixing only the standing directions leaves the rest holding a
separately-drawn corpse, so the body visibly JUMPS the instant the death
animation ends and the rotation takes over - validate_unit_sprites.py check [6]
measures exactly that, and every Kestrel failed it at 500-700px after a
--fix pass while Rodar Akai, whose corpses are all eight death frames, is
clean. Continuity beats the marginally better drawing.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from measure_rotations import ORDER, read_png  # noqa: E402


def bbox(path: Path) -> tuple:
    w, h, ch, rows = read_png(path)
    min_x, max_x, min_y, max_y = w, -1, h, -1
    for y in range(h):
        row = rows[y]
        for x in range(w):
            alpha = row[x * ch + 3] if ch == 4 else 255
            if alpha == 0:
                continue
            min_x = min(min_x, x); max_x = max(max_x, x)
            min_y = min(min_y, y); max_y = max(max_y, y)
    if max_y < 0:
        return (0, 0)
    return (max_x - min_x + 1, max_y - min_y + 1)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = Path(sys.argv[1])
    take_all = "--all" in sys.argv
    fix = take_all or "--fix" in sys.argv
    dead = root / "Dead_stance" / "rotations"
    if not dead.is_dir():
        sys.exit("no Dead_stance/rotations under %s" % root)
    # Staging bundles call the base state `Idle`; once assembled into
    # assets/sprites it is named after the unit, so find it rather than assume.
    found = sorted(root.glob("*/animations/standing_idle_to_dead"))
    if not found:
        sys.exit("no standing_idle_to_dead animation under %s" % root)
    death_anim = found[0]

    print("%-13s %-6s %-6s %s" % ("direction", "w", "h", "verdict"))
    print("-" * 52)
    standing = []
    for d in ORDER:
        f = dead / ("%s.png" % d)
        if not f.exists():
            print("%-13s %-6s %-6s MISSING" % (d, "-", "-"))
            standing.append(d)
            continue
        w, h = bbox(f)
        upright = w <= h
        if upright:
            standing.append(d)
        print("%-13s %-6d %-6d %s" % (d, w, h, "STANDING" if upright else "lying"))

    if standing:
        print("\n%d direction(s) still standing: %s"
              % (len(standing), ", ".join(standing)))
    elif not take_all:
        print("\nRESULT: PASS (all eight are lying down)")
        return

    if not fix:
        print("RESULT: FAIL - rerun with --fix to substitute the death animation's "
              "final frame, or --all to take all eight from it and get a "
              "continuous transition as well")
        sys.exit(1)

    patched = []
    for d in (ORDER if take_all else standing):
        src = death_anim / d / "frame_008.png"
        if not src.exists():
            frames = sorted((death_anim / d).glob("frame_*.png")) if (death_anim / d).is_dir() else []
            if not frames:
                print("  cannot fix %s - no death animation frames" % d)
                continue
            src = frames[-1]
        shutil.copyfile(src, dead / ("%s.png" % d))
        patched.append("%s <- %s" % (d, src.name))
    print("\npatched %d: %s" % (len(patched), "; ".join(patched)))
    print("RECORD THIS in metadata.json as a note on the Dead_stance state.")
    print("RESULT: FIXED")


if __name__ == "__main__":
    main()
