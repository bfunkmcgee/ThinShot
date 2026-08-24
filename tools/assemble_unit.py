#!/usr/bin/env python3
"""Assemble approved staging frames into a canonical unit folder.

    python tools/assemble_unit.py <manifest.json> [--force]

The manifest names the unit and points every set at its approved staging
folder (staging is gitignored, so the manifest lives beside the staging and
travels with it):

    {
      "unit": "Goblin_MG",
      "canvas": 64,
      "feet": 47,
      "idle_rotations":  "artgen/staging/mg-tests/canonical48/Idle",
      "ready_rotations": "artgen/staging/mg-tests/composite/ReadyToFire/rotations",
      "sets": {
        "standing_idle":                "artgen/staging/mg-tests/anim_approved/standing_idle",
        "standing_idle_alt":            "...",
        "standing_idle_walk":           "...",
        "standing_idle_to_readyToFire": "...",
        "standing_idle_damage":         "...",
        "standing_idle_reload":         "...",
        "standing_idle_to_dead":        "...",
        "standing-readyToFire_idle":    "..."
      }
    }

Rotation folders hold eight <direction>.png; set folders hold eight
<direction>/frame_%03d.png trees, canvas sizes free to vary (the animator
grows canvases to fit motion, and that is fine - it is normalised here).

What the assembler enforces, in order (UNIT_ASSET_SPEC.md sections 1, 3, 5):

  binary alpha     every pixel forced to 0 or 255 (threshold 128)
  one transform    per (set, direction): frame 0's feet land on the manifest
    per stack      feet row and its bbox centre on the canvas centre, the
                   SAME shift applied to all frames of that direction - so a
                   stride's bob survives and the ground line does not - then
                   clamped so the union of the stack fits, and REFUSED if
                   clamping would clip a pixel
  endpoint seals   one-shots that return to neutral start ON the idle
                   rotation; the raise starts on idle and LANDS on the aim
                   rotation; the aim-idle starts on the aim rotation; the
                   death starts on idle - so validate_unit_sprites.py's
                   endpoint check passes by construction, not by luck
  the corpse       Dead_stance/rotations ARE standing_idle_to_dead's last
                   frames (the check_dead_stance.py convention): the death
                   hand-off is exact because the two files are the same file

It does NOT write metadata.json - provenance needs the PixelLab character
ids and the honest notes about repairs, which only the person who ran the
generation has. The tool prints a reminder instead.

After assembling: validate_unit_sprites.py, then the wiring recipe (spec
section 5). The generation program that produces the staging folders this
consumes is spec section 7.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("assemble_unit.py needs Pillow:  pip install Pillow")

ORDER = ["east", "south-east", "south", "south-west",
         "west", "north-west", "north", "north-east"]
FRAMES = 9

# Which rotation seals which end of which set. "start"/"end" name the
# rotation key in the manifest sense: idle or ready.
SEALS = {
    "standing_idle":                {"start": "idle"},
    "standing_idle_alt":            {"start": "idle"},
    "standing_idle_walk":           {"start": "idle"},
    "standing_idle_damage":         {"start": "idle"},
    "standing_idle_reload":         {"start": "idle"},
    "standing_idle_to_readyToFire": {"start": "idle", "end": "ready"},
    "standing_idle_to_dead":        {"start": "idle"},
    "standing-readyToFire_idle":    {"start": "ready"},
}
# The aim state's folder differs from the base state's.
READY_SETS = {"standing-readyToFire_idle"}


def load_bin(path, counter):
    im = Image.open(path).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if 0 < a < 255:
                counter[0] += 1
                px[x, y] = (r, g, b, 255 if a >= 128 else 0)
    return im


def bbox(im):
    px = im.load()
    w, h = im.size
    xs = [x for y in range(h) for x in range(w) if px[x, y][3] > 0]
    ys = [y for y in range(h) for x in range(w) if px[x, y][3] > 0]
    return min(xs), min(ys), max(xs), max(ys)


def opaque(im):
    px = im.load()
    w, h = im.size
    return sum(1 for y in range(h) for x in range(w) if px[x, y][3] > 0)


def place(frames, canvas, feet_y, label):
    x0, y0, x1, y1 = bbox(frames[0])
    dx = canvas // 2 - (x0 + x1) // 2
    dy = feet_y - y1
    boxes = [bbox(f) for f in frames]
    dx = max(dx, -min(b[0] for b in boxes))
    dx = min(dx, canvas - 1 - max(b[2] for b in boxes))
    dy = max(dy, -min(b[1] for b in boxes))
    dy = min(dy, canvas - 1 - max(b[3] for b in boxes))
    out = []
    for f in frames:
        o = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        o.alpha_composite(f, (dx, dy))
        if opaque(o) != opaque(f):
            sys.exit(f"{label}: figure cannot fit a {canvas}px canvas even "
                     f"after clamping - this is a regeneration problem, not a "
                     f"placement one")
        out.append(o)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("manifest")
    ap.add_argument("--force", action="store_true",
                    help="overwrite an existing assets/sprites/<unit> folder")
    ap.add_argument("--out", default=None,
                    help="write somewhere other than assets/sprites/<unit> "
                         "(a dry-run target, or a diff-against-shipped check)")
    args = ap.parse_args()

    with open(args.manifest) as f:
        m = json.load(f)
    unit = m["unit"]
    canvas = int(m["canvas"])
    feet_y = int(m["feet"])
    dest = args.out or os.path.join("assets", "sprites", unit)
    if os.path.exists(dest) and not args.force and not args.out:
        sys.exit(f"{dest} exists - pass --force to replace it, or --out for a dry run")

    missing = [k for k in SEALS if k not in m["sets"]]
    if missing:
        sys.exit("manifest is missing sets: " + ", ".join(missing))

    semi = [0]

    def save(im, *parts):
        p = os.path.join(dest, *parts)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        im.save(p)

    rot = {"idle": {}, "ready": {}}
    for key, src in [("idle", m["idle_rotations"]), ("ready", m["ready_rotations"])]:
        for d in ORDER:
            im = load_bin(os.path.join(src, d + ".png"), semi)
            rot[key][d] = place([im], canvas, feet_y, f"{key} rotation {d}")[0]
    for d in ORDER:
        save(rot["idle"][d], unit, "rotations", d + ".png")
        save(rot["ready"][d], "ReadyToFire_Stance", "rotations", d + ".png")

    written = 16
    dead = {}
    for name, src in m["sets"].items():
        seal = SEALS[name]
        for d in ORDER:
            frames = [load_bin(os.path.join(src, d, "frame_%03d.png" % i), semi)
                      for i in range(FRAMES)]
            outs = place(frames, canvas, feet_y, f"{name} {d}")
            outs[0] = rot[seal["start"]][d]
            if "end" in seal:
                outs[-1] = rot[seal["end"]][d]
            if name == "standing_idle_to_dead":
                dead[d] = outs[-1]
            folder = "ReadyToFire_Stance" if name in READY_SETS else unit
            for i, o in enumerate(outs):
                save(o, folder, "animations", name, d, "frame_%03d.png" % i)
                written += 1
    for d in ORDER:
        save(dead[d], "Dead_stance", "rotations", d + ".png")
        written += 1

    print(f"{unit}: {written} frames -> {dest}")
    print(f"semi-transparent pixels binarised: {semi[0]}")
    print("next: write metadata.json (character ids + repair notes - only you "
          "have them), then python tools/validate_unit_sprites.py " + dest)


if __name__ == "__main__":
    main()
