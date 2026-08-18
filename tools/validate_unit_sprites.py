#!/usr/bin/env python3
"""Validate a generated unit against UNIT_ASSET_SPEC.md before wiring it in. (v2)

Pixel Lab reliably produces a few failure modes that are easy to miss by eye and
expensive to find later, so check them mechanically:

  1. canvas / alpha / empty frames / frame counts   - hard spec requirements
  2. palette discipline                              - per-set budget (see SPECS)
  3. foot line                                       - or the unit floats or sinks
  4. aim direction                                   - the weapon must point along
     the facing. Pixel Lab very often draws the *south* aim pose with the rifle
     levelled off to the side instead of foreshortened at the camera, and often
     omits the weapon entirely on *north*.
  5. muzzle flash in the aim-idle                    - the aim-idle is a loop; the
     weapon must never actually fire in it.
  6. transition endpoints                            - a *_to_<state> one-shot must
     land on that state's static rotation or the swap pops.
  7. metadata.json                                   - REQUIRED for hi-res sets
     (provenance: character ids + group id), reported for legacy sets.

v2: the single 60x60 assumption is gone. Every known unit folder has an entry
in SPECS with its real canvas, foot range and palette budget, so the 64x64
goblins and the 56x56 alt raider are finally validatable at all. Hi-res sets
(120/128/112, drawn at 1x) are recognised by canvas and get the hard spec:
palette gates, scaled thresholds, metadata.json required.

Enforcement tiers (so a standing defect in shipped art never starts blocking
an existing workflow):
  - legacy 60x60 entries: structural checks gate exactly as v1 did; the palette
    budget is informational only (Scout ships at ~387 colours and must not
    start failing).
  - legacy 64/56 entries: newly validatable - every finding is reported, but
    advisory by default. `--strict` turns them into hard gates.
  - hi-res entries: everything gates. This is the import gate for the hi-res
    program.

Usage:
    python tools/validate_unit_sprites.py assets/sprites/Rodar_Akai
    python tools/validate_unit_sprites.py assets/sprites/Civilian --no-weapon
    python tools/validate_unit_sprites.py assets/sprites/Goblin_SMG --strict

Exits non-zero if any gated check fails, so it can gate an import.
Writes <unit>/preview.html on a pass (house rule: a validated unit always
carries a current, playing preview).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from statistics import median

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow:  python -m pip install pillow")

DIRS = ["east", "south-east", "south", "south-west",
        "west", "north-west", "north", "north-east"]
# which way the weapon should stick out for each facing
SIDE = {"east": "right", "south-east": "right", "north-east": "right",
        "west": "left", "south-west": "left", "north-west": "left",
        "south": "none", "north": "none"}

# --------------------------------------------------------------------- specs
# Everything a per-set judgement needs. `advisory` lists check categories that
# report but do not gate (subset, or "*" for all - the newly-validatable tier).
# `display_scale` / `foot_anchor` are shared with make_char_viewer.py so the
# viewer and the validator agree on what "on-screen size" means.
ALL = "*"

def _legacy60(**kw):
    d = dict(canvas=(60, 60), foot_range=(12, 16),
             palette_warn=80, palette_fail=None,
             camera_slack=4, min_protrude=3, endpoint_max=40, flash_bias=8,
             metadata_required=False, weapon=True,
             advisory={"palette", "metadata"},
             display_scale=2, foot_anchor=15, tier="legacy-60")
    d.update(kw)
    return d

def _legacy(canvas, foot_anchor, **kw):
    d = _legacy60(canvas=canvas, foot_anchor=foot_anchor,
                  advisory=ALL, tier=f"legacy-{canvas[0]}")
    d.update(kw)
    return d

def _hires(canvas, foot_range, foot_anchor):
    # thresholds scale with the doubled canvas: linear ones x2, area ones x4
    return dict(canvas=canvas, foot_range=foot_range,
                palette_warn=128, palette_fail=160,
                camera_slack=8, min_protrude=6, endpoint_max=160, flash_bias=32,
                metadata_required=True, weapon=True,
                advisory=set(),
                display_scale=1, foot_anchor=foot_anchor, tier=f"hires-{canvas[0]}")

SPECS = {
    # legacy 60x60 - the v1 contract, palette now informational
    "Scout":               _legacy60(),
    "Scout_TeamLead":      _legacy60(),
    "Scout_MachineGunner": _legacy60(),
    "Goblin_BoltRifle":    _legacy60(),
    "Rodar_Akai":          _legacy60(),
    "Hero_MachineGunner":  _legacy60(),
    "Civilian":            _legacy60(weapon=False),
    # The five specialist Kestrels. Same 60-canvas contract as the rifleman
    # they were generated against. Without these entries they fell through to
    # the measured-canvas fallback, where EVERY finding is advisory - so the
    # five newest units in the game were the only ones nothing could gate.
    #
    # Each registers the facings Pixel Lab drew with the weapon levelled to a
    # flank rather than foreshortened. Their muzzle offsets in Unit.gd follow
    # the art for exactly those facings (see the band-scan note there), and
    # each unit's metadata.json carries the same fact under known_deviations.
    # Halvik and Fen have no registered north because theirs is not drawn
    # holding a weapon there at all, which the ordinary check passes.
    "Kestrel_Grenadier":   _legacy60(aim_levelled={"south": "right", "north": "left"}),
    "Kestrel_Marksman":    _legacy60(aim_levelled={"south": "right", "north": "left"}),
    "Kestrel_Breacher":    _legacy60(aim_levelled={"south": "right"}),
    "Kestrel_Medic":       _legacy60(aim_levelled={"south": "right", "north": "left"}),
    "Kestrel_Technician":  _legacy60(aim_levelled={"south": "right"}),
    # legacy 64/56 - newly validatable; advisory by default, --strict gates
    "Goblin":              _legacy((64, 64), 15),
    "Goblin_SMG":          _legacy((64, 64), 15),
    "Goblin_revolver":     _legacy((64, 64), 15),
    "Goblin_SMG_alt":      _legacy((56, 56), 14),
}

# hi-res sets are recognised by canvas, whatever the folder is called - a
# regenerated unit lands in the same assets/sprites/<Name>/ folder it replaces.
HIRES_PROFILES = {
    (120, 120): _hires((120, 120), (24, 32), 30),
    (128, 128): _hires((128, 128), (24, 32), 30),
    (112, 112): _hires((112, 112), (22, 30), 28),
}


def sprite_pngs(root: Path):
    """Every sprite under the unit, minus the generated preview sheet."""
    return sorted(p for p in root.rglob("*.png") if p.name != "preview.png")


def detect_canvas(root: Path):
    """The most common PNG size under the unit - one wrong-size frame must not
    flip the whole spec, so majority wins."""
    from collections import Counter
    sizes = Counter()
    for p in sprite_pngs(root)[:400]:
        with Image.open(p) as im:
            sizes[im.size] += 1
    return sizes.most_common(1)[0][0] if sizes else None


def resolve_spec(root: Path):
    """(spec, how-it-was-chosen). Hi-res canvas beats the name table: the
    hi-res program regenerates units in place."""
    canvas = detect_canvas(root)
    if canvas in HIRES_PROFILES:
        return HIRES_PROFILES[canvas], f"canvas {canvas[0]}x{canvas[1]} -> hi-res profile"
    if root.name in SPECS:
        return SPECS[root.name], f"SPECS[{root.name!r}]"
    if canvas:
        spec = _legacy(canvas, 15)
        return spec, (f"unknown unit, measured canvas {canvas[0]}x{canvas[1]} "
                      "- all checks advisory; add a SPECS entry")
    return _legacy60(), "no PNGs found - defaulting to legacy-60"


# ------------------------------------------------------------------ reporting
class Report:
    def __init__(self, spec, strict: bool):
        self.spec, self.strict = spec, strict
        self.fails: list[str] = []      # gated
        self.warns: list[str] = []      # advisory findings
        self.notes: list[str] = []

    def gated(self, category: str) -> bool:
        if self.strict:
            return True
        adv = self.spec["advisory"]
        return not (adv == ALL or category in adv)

    def finding(self, category: str, msg: str):
        if self.gated(category):
            self.fails.append(msg)
            print(f"  FAIL  {msg}")
        else:
            self.warns.append(msg)
            print(f"  warn  {msg}  [advisory]")

    def ok(self, msg):
        print(f"  ok    {msg}")

    def note(self, msg):
        self.notes.append(msg)


def load(p):
    return Image.open(p).convert("RGBA")


# ---------------------------------------------------------------- basic shape
def check_files(root: Path, r: Report):
    spec = r.spec
    canvas = tuple(spec["canvas"])
    print(f"\n[1] canvas, alpha, frame counts (spec canvas {canvas[0]}x{canvas[1]})")
    pngs = sprite_pngs(root)
    if not pngs:
        r.finding("files", f"no PNGs under {root}")
        return
    bad_size = bad_alpha = empty = 0
    palette_worst = 0
    for p in pngs:
        im = load(p)
        if im.size != canvas:
            bad_size += 1
        px = im.load()
        w, h = im.size
        alphas = {px[x, y][3] for x in range(w) for y in range(h)}
        if not alphas <= {0, 255}:
            bad_alpha += 1
        opaque = [c for c in im.get_flattened_data() if c[3] > 0]
        if not opaque:
            empty += 1
        else:
            palette_worst = max(palette_worst, len({c for c in opaque}))
    msg = f"{len(pngs)} PNGs, canvas {canvas[0]}x{canvas[1]}"
    (r.ok if not bad_size else lambda m: r.finding("canvas", m))(
        msg + ("" if not bad_size else f" - {bad_size} wrong size"))
    (r.ok if not bad_alpha else lambda m: r.finding("alpha", m))(
        "binary alpha" + ("" if not bad_alpha else f" - {bad_alpha} anti-aliased"))
    (r.ok if not empty else lambda m: r.finding("empty", m))(
        "no empty frames" + ("" if not empty else f" - {empty} blank"))

    warn_at, fail_at = spec["palette_warn"], spec["palette_fail"]
    if fail_at is not None and palette_worst > fail_at:
        r.finding("palette_hard",
                  f"palette max {palette_worst} colours/sprite (fail limit {fail_at})")
    elif palette_worst > warn_at:
        r.finding("palette",
                  f"palette max {palette_worst} colours/sprite (budget {warn_at})")
    else:
        r.ok(f"palette max {palette_worst} colours/sprite (budget {warn_at})")

    for anim in sorted(root.rglob("animations/*")):
        if not anim.is_dir():
            continue
        for d in DIRS:
            sub = anim / d
            if not sub.is_dir():
                r.finding("frames", f"{anim.relative_to(root)} missing direction {d}")
                continue
            n = len(list(sub.glob("*.png")))
            if n != 9:
                r.finding("frames",
                          f"{anim.relative_to(root)}/{d} has {n} frames, expected 9")


# ------------------------------------------------------------------ foot line
def check_feet(root: Path, r: Report):
    lo_want, hi_want = r.spec["foot_range"]
    print(f"\n[2] foot line (upright rotation sets; want {lo_want}-{hi_want}px below centre)")
    for rot in sorted(root.rglob("rotations")):
        name = rot.parent.name
        if "dead" in name.lower() or "cower" in name.lower():
            continue
        vals = []
        for d in DIRS:
            p = rot / f"{d}.png"
            if not p.exists():
                r.finding("frames", f"{rot.relative_to(root)} missing {d}.png")
                continue
            im = load(p)
            px = im.load()
            w, h = im.size
            ys = [y for y in range(h) for x in range(w) if px[x, y][3] > 0]
            if ys:
                vals.append(max(ys) - h // 2)
        if not vals:
            continue
        lo, hi = min(vals), max(vals)
        good = lo_want <= lo and hi <= hi_want
        (r.ok if good else lambda m: r.finding("feet", m))(
            f"{name}: feet {lo}-{hi}px below centre (want {lo_want}-{hi_want})")


# -------------------------------------------------------------- aim direction
def reach(p):
    """How far the silhouette protrudes past the dense 'body' columns, per side."""
    im = load(p)
    px = im.load()
    w, h = im.size
    col = [sum(1 for y in range(h) if px[x, y][3] > 0) for x in range(w)]
    used = [x for x in range(w) if col[x]]
    if not used:
        return None
    thresh = max(col) / 3.0
    body = [x for x in used if col[x] >= thresh]
    if not body:
        return None
    return min(body) - min(used), max(used) - max(body)


def check_aim(root: Path, r: Report):
    slack = r.spec["camera_slack"]
    min_pro = r.spec["min_protrude"]
    rots = [rt for rt in root.rglob("rotations")
            if "readytofire" in rt.parent.name.lower().replace("_", "")
            or "ready_to_fire" in rt.parent.name.lower()]
    if not rots:
        r.note("no ReadyToFire rotations found - skipped aim-direction check")
        return
    print("\n[3] aim direction (weapon must point along the facing)")
    for rot in rots:
        for d in DIRS:
            p = rot / f"{d}.png"
            if not p.exists():
                continue
            rr = reach(p)
            if rr is None:
                r.finding("aim", f"{d}: empty aim rotation")
                continue
            l, rt = rr
            side = "left" if l > rt else "right"
            want = SIDE[d]
            # A unit may REGISTER that a facing is drawn with the weapon
            # levelled to a flank instead of foreshortened at the camera. That
            # is a real deviation, not a pass: Pixel Lab draws it that way
            # often, and the fix is to make the muzzle offset follow the art so
            # the flash still leaves the barrel the player can see. Registering
            # it here checks the pose that was actually drawn, and keeps the
            # other six facings gated - muting the whole "aim" category for the
            # unit would also hide a missing weapon, which is what this check
            # is for.
            levelled = r.spec.get("aim_levelled", {})
            if d in levelled:
                r.note(f"{d}: drawn levelled {levelled[d]}, not foreshortened - "
                       f"registered deviation, muzzle offsets follow the art")
                want = levelled[d]
            if want == "none":
                if max(l, rt) > slack:
                    r.finding("aim", f"{d}: weapon sticks out {max(l, rt)}px to the "
                                     f"{side} - should point at/away from camera (<={slack}px)")
                else:
                    r.ok(f"{d}: foreshortened at camera (L{l} R{rt})")
            elif max(l, rt) < min_pro:
                r.finding("aim", f"{d}: no weapon protrusion (L{l} R{rt}) - weapon likely missing")
            elif side != want:
                r.finding("aim", f"{d}: protrudes {side}, expected {want} (L{l} R{rt})")
            else:
                r.ok(f"{d}: points {side} (L{l} R{rt})")


# --------------------------------------------------------------- muzzle flash
def hot_pixels(p):
    n = 0
    for r, g, b, a in load(p).get_flattened_data():
        if a == 0:
            continue
        if (r > 215 and g > 195 and b < 190 and (r + g) / 2 - b > 40) or \
           (r > 235 and g > 235 and b > 200):
            n += 1
    return n


def check_flash(root: Path, r: Report):
    bias = r.spec["flash_bias"]
    idles = [d for d in root.rglob("animations/*")
             if d.is_dir() and ("readytofire_idle" in d.name.lower().replace("-", "")
                                or "ready_to_fire_idle" in d.name.lower())]
    if not idles:
        r.note("no aim-idle set found - skipped muzzle-flash check")
        return
    print("\n[4] muzzle flash in aim-idle (the loop must never fire)")
    for idle in idles:
        for d in DIRS:
            frames = sorted((idle / d).glob("*.png"))
            if not frames:
                continue
            counts = [hot_pixels(f) for f in frames]
            med = median(counts)
            spikes = [i for i, c in enumerate(counts) if c > max(med * 2.0, med + bias)]
            if spikes:
                r.finding("flash", f"{d}: muzzle flash in frame(s) {spikes} (counts {counts})")
            else:
                r.ok(f"{d}: no flash")


# --------------------------------------------------------- transition endings
def silhouette_diff(a, b):
    ia, ib = load(a), load(b)
    if ia.size != ib.size:
        return None
    pa, pb = ia.load(), ib.load()
    w, h = ia.size
    return sum(1 for x in range(w) for y in range(h)
               if (pa[x, y][3] > 0) != (pb[x, y][3] > 0))


def check_transitions(root: Path, r: Report):
    limit = r.spec["endpoint_max"]
    print(f"\n[5] transition endpoints (one-shot must land on the target rotation; gap <= {limit}px)")
    targets = {}
    for rot in root.rglob("rotations"):
        targets[rot.parent.name.lower().replace("_", "").replace("-", "")] = rot
    found = False
    for anim in sorted(root.rglob("animations/*")):
        if not anim.is_dir() or "_to_" not in anim.name:
            continue
        key = anim.name.split("_to_")[-1].lower().replace("_", "").replace("-", "")
        rot = next((v for k, v in targets.items() if key in k or k in key), None)
        if rot is None:
            r.note(f"{anim.name}: no matching rotation set to compare against")
            continue
        found = True
        worst = 0
        for d in DIRS:
            frames = sorted((anim / d).glob("*.png"))
            tgt = rot / f"{d}.png"
            if not frames or not tgt.exists():
                continue
            diff = silhouette_diff(frames[-1], tgt)
            if diff is not None:
                worst = max(worst, diff)
        msg = f"{anim.name} -> {rot.parent.name}: worst endpoint gap {worst}px"
        (r.ok if worst <= limit else lambda m: r.finding("endpoint", m))(msg)
    if not found:
        r.note("no *_to_* transitions found")


# ------------------------------------------------------------------- metadata
def check_metadata(root: Path, r: Report):
    required = r.spec["metadata_required"]
    print("\n[6] metadata.json (provenance)" + ("  [REQUIRED for hi-res]" if required else ""))
    mf = root / "metadata.json"
    cat = "metadata_hard" if required else "metadata"
    if not mf.exists():
        if required:
            r.finding(cat, "metadata.json missing - hi-res sets must ship provenance")
        else:
            r.note("metadata.json missing (informational for legacy sets)")
        return
    try:
        m = json.loads(mf.read_text(encoding="utf-8"))
    except Exception as e:
        r.finding(cat, f"metadata.json unreadable: {e}")
        return
    problems = []
    if not m.get("group_id"):
        problems.append("no group_id")
    states = m.get("states") or []
    if not states:
        problems.append("no states")
    no_char = [s.get("folder", "?") for s in states
               if not (s.get("character") or {}).get("id")]
    if no_char:
        problems.append(f"state(s) without character id: {', '.join(map(str, no_char))}")
    if problems:
        if required:
            r.finding(cat, "metadata.json incomplete: " + "; ".join(problems))
        else:
            r.note("metadata.json: " + "; ".join(problems))
    else:
        r.ok(f"metadata.json: group {m['group_id'][:8]}, {len(states)} states with character ids")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("unit", type=Path)
    ap.add_argument("--no-weapon", action="store_true",
                    help="unarmed unit: skip aim-direction and muzzle-flash checks")
    ap.add_argument("--no-preview", action="store_true",
                    help="skip writing <unit>/preview.html on a pass")
    ap.add_argument("--strict", action="store_true",
                    help="advisory findings become hard failures (use when judging a regen)")
    a = ap.parse_args()
    root = a.unit
    if not root.is_dir():
        sys.exit(f"not a directory: {root}")

    spec, how = resolve_spec(root)
    r = Report(spec, a.strict)
    print(f"validating {root}")
    print(f"  spec: {spec['tier']} ({how})"
          + (" [strict]" if a.strict else ""))

    check_files(root, r)
    check_feet(root, r)
    if not a.no_weapon and spec["weapon"]:
        check_aim(root, r)
        check_flash(root, r)
    elif not spec["weapon"]:
        r.note("unarmed unit per SPECS - skipped aim-direction and muzzle-flash checks")
    check_transitions(root, r)
    check_metadata(root, r)

    for n in r.notes:
        print(f"\n  note: {n}")

    if r.fails:
        print(f"\nFAILED - {len(r.fails)} problem(s)"
              + (f", {len(r.warns)} advisory finding(s)" if r.warns else ""))
        print("no preview written - fix the problems and re-run")
        return 1

    print("\nPASS" + (f" - with {len(r.warns)} advisory finding(s)" if r.warns else ""))
    if not a.no_preview:
        # house rule: a validated unit always carries a current preview, and the
        # preview is the interactive viewer - every set actually playing
        sys.path.insert(0, str(Path(__file__).parent))
        from make_char_viewer import build_viewer
        out = build_viewer(root)
        print(f"preview -> {out} ({out.stat().st_size // 1024} KB) - open in a browser")
    return 0


if __name__ == "__main__":
    sys.exit(main())
