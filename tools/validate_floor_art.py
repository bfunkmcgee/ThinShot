#!/usr/bin/env python3
"""Metric gate for floor sheets: the checks the eye misses and the board shows.

The two measured defects this exists to catch (2026-08 audit of the shipped
desert sheet): ~2px near-black rims on every diamond (ring/interior luminance
ratio ~0.60; healthy is >=0.90) and cross-boundary seam discontinuity 5.2x
the within-tile texture level (target <=1.5x). Plus the contract checks that
keep any sheet drop-in: mask identity, luminance spread, mid-tone band,
palette budget, lighting direction vs the sidecar's symmetric flags, and
sidecar structural completeness.

Usage:
    python tools/validate_floor_art.py <sheet.png> --sidecar <sheet.tiles.json> \\
        --style artgen/style.json [--report]

Output: one `METRIC <name> <value> <threshold> PASS|FAIL` line per check plus
detail lines. Exit 0 = gate passed, 1 = failed, 2 = usage error.
--report prints all metrics without failing (calibration mode).
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("needs Pillow:  python -m pip install pillow")

# ---- check constants (thresholds proper come from style.json) ----
RIM_RING_PX = 2            # the erosion ring the defect lives in
RIM_SHOULDER = (4, 8)      # the ground just past the rim gradient; comparing
                           # ring to this, not the whole interior, keeps a
                           # dark road/crack through the middle from skewing
SEAM_SAMPLES = 30          # crossings sampled per shared edge
SEAM_EDGE_TRIM = 0.15      # fraction of each edge end skipped (vertex junk)
SEAM_BAND_PX = 3           # profile reaches this far into each tile
BASELINE_STRIDE = 7        # interior anchor sampling stride for the baseline
RIDGE_DELTA = 30           # median5 - min3 above this = dark ridge pixel
RIDGE_WARN_PX = 40         # warn threshold, per transition tile
TALL_MASK_SLACK = 80       # px a tall (overhang) slot may deviate from the mask
LIGHT_DIR_SLACK = 0.5      # px of "wrong way" tolerated in the centroid offset
BASE_SLOT_COUNT = 18       # new-layout contract: per zone 4 base + 2 accents
BASE_PER_ZONE = {"base": 4, "accent": 2}

# diamond vertices of a 128x60 tile; the 4 abutting-neighbor screen offsets
VERTS = {"top": (64.0, 0.0), "right": (128.0, 30.0),
         "bottom": (64.0, 60.0), "left": (0.0, 30.0)}
NEIGHBORS = [((64, 30), ("right", "bottom")),   # down-right: A's SE edge
             ((-64, 30), ("left", "bottom")),   # down-left:  A's SW edge
             ((64, -30), ("top", "right")),     # up-right:   A's NE edge
             ((-64, -30), ("left", "top"))]     # up-left:    A's NW edge

fails: list[str] = []
warns: list[str] = []


def metric(name: str, value, threshold, passed: bool, warn_only=False):
    state = "PASS" if passed else ("WARN" if warn_only else "FAIL")
    print(f"METRIC {name} {value} {threshold} {state}")
    if not passed:
        (warns if warn_only else fails).append(name)


def detail(msg: str):
    print(f"  {msg}")


def lum(p) -> float:
    return (0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]) / 255.0


# ------------------------------------------------------------------ tile model
class Tile:
    """One diamond face: L map + mask + boundary distances, ready to measure."""

    def __init__(self, im: Image.Image):
        self.w, self.h = im.size
        data = list(im.get_flattened_data())
        self.mask = [1 if p[3] > 0 else 0 for p in data]
        self.L = [lum(p) if p[3] > 0 else 0.0 for p in data]
        self.colors = {p[:3] for p in data if p[3] > 0}
        self.dist = cheb_dist(self.mask, self.w, self.h)
        self.im = im

    def mirrored(self) -> "Tile":
        return Tile(self.im.transpose(Image.Transpose.FLIP_LEFT_RIGHT))

    def mean(self, min_dist=1) -> float:
        vals = [l for l, d in zip(self.L, self.dist) if d >= min_dist]
        return sum(vals) / len(vals) if vals else 0.0

    def sample(self, x: float, y: float):
        xi, yi = round(x), round(y)
        if 0 <= xi < self.w and 0 <= yi < self.h:
            i = yi * self.w + xi
            if self.mask[i]:
                return self.L[i]
        return None

    def centroid_offset(self):
        sw = sx = sy = mn = mx = my = 0.0
        for i, l in enumerate(self.L):
            if self.mask[i]:
                x, y = i % self.w, i // self.w
                sx += x * l; sy += y * l; sw += l
                mx += x; my += y; mn += 1
        if not sw or not mn:
            return (0.0, 0.0)
        return (sx / sw - mx / mn, sy / sw - my / mn)


def cheb_dist(alpha, w, h):
    """Chebyshev distance to nearest transparent px (OOB = transparent)."""
    INF = 1 << 20
    d = [0 if a == 0 else INF for a in alpha]
    for i in range(w):
        if d[i]:
            d[i] = 1
        if d[(h - 1) * w + i]:
            d[(h - 1) * w + i] = 1
    for y in range(h):
        if d[y * w]:
            d[y * w] = 1
        if d[y * w + w - 1]:
            d[y * w + w - 1] = 1
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if d[i] <= 1:
                continue
            best = d[i]
            if x > 0:
                best = min(best, d[i - 1] + 1)
            if y > 0:
                j = i - w
                best = min(best, d[j] + 1)
                if x > 0:
                    best = min(best, d[j - 1] + 1)
                if x < w - 1:
                    best = min(best, d[j + 1] + 1)
            d[i] = best
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            i = y * w + x
            if d[i] <= 1:
                continue
            best = d[i]
            if x < w - 1:
                best = min(best, d[i + 1] + 1)
            if y < h - 1:
                j = i + w
                best = min(best, d[j] + 1)
                if x > 0:
                    best = min(best, d[j - 1] + 1)
                if x < w - 1:
                    best = min(best, d[j + 1] + 1)
            d[i] = best
    return d


# --------------------------------------------------------------------- checks
def check_mask_identity(tiles, slots, mask, tw, th):
    worst = 0
    for i, (t, s) in enumerate(zip(tiles, slots)):
        diff = sum(1 for a, b in zip(t.mask, mask) if a != b)
        slack = TALL_MASK_SLACK if s.get("tall") else 0
        if diff > slack:
            detail(f"slot {i}: alpha differs from canonical mask by {diff}px"
                   + (" (tall)" if s.get("tall") else ""))
        worst = max(worst, diff if not s.get("tall") else 0)
    metric("mask_identity_diff_px", worst, 0, worst == 0)


def check_rim(tiles, thr):
    lo, hi = thr["rim_ratio_min"], thr["rim_ratio_max"]
    worst, worst_i = 1.0, -1
    for i, t in enumerate(tiles):
        ring = [l for l, d in zip(t.L, t.dist) if 1 <= d <= RIM_RING_PX]
        interior = [l for l, d in zip(t.L, t.dist)
                    if RIM_SHOULDER[0] <= d <= RIM_SHOULDER[1]]
        if not ring or not interior:
            continue
        ratio = (sum(ring) / len(ring)) / (sum(interior) / len(interior))
        detail(f"slot {i}: rim ratio {ratio:.3f}")
        if abs(ratio - 1.0) > abs(worst - 1.0):
            worst, worst_i = ratio, i
    metric("rim_ratio_worst", f"{worst:.3f}", f"{lo}..{hi}", lo <= worst <= hi)


def seam_tv(A: Tile, B: Tile, d, edge):
    """Total variation of the luminance profile crossing the shared edge:
    the seam should be no busier than the tiles' own texture."""
    p1, p2 = VERTS[edge[0]], VERTS[edge[1]]
    mag = math.hypot(*d)
    ux, uy = d[0] / mag, d[1] / mag
    tvs = []
    for k in range(SEAM_SAMPLES):
        t = SEAM_EDGE_TRIM + (1 - 2 * SEAM_EDGE_TRIM) * k / (SEAM_SAMPLES - 1)
        ex, ey = p1[0] + t * (p2[0] - p1[0]), p1[1] + t * (p2[1] - p1[1])
        prof = []
        for s in (-SEAM_BAND_PX, -2, -1, 1, 2, SEAM_BAND_PX):
            px, py = ex + s * ux, ey + s * uy
            v = A.sample(px, py) if s < 0 else B.sample(px - d[0], py - d[1])
            prof.append(v)
        if any(v is None for v in prof):
            continue
        diffs = [abs(b - a) for a, b in zip(prof, prof[1:])]
        tvs.append(sum(diffs) / len(diffs))
    return sum(tvs) / len(tvs) if tvs else None


def baseline_tv(tiles):
    """The same profile statistic measured wholly inside tiles."""
    dirs = [(64 / 70.71, 30 / 70.71), (64 / 70.71, -30 / 70.71)]
    tvs = []
    for t in tiles:
        for ux, uy in dirs:
            for y in range(0, t.h, BASELINE_STRIDE):
                for x in range(0, t.w, BASELINE_STRIDE):
                    if t.dist[y * t.w + x] < SEAM_BAND_PX + 4:
                        continue
                    prof = [t.sample(x + s * ux, y + s * uy)
                            for s in (-SEAM_BAND_PX, -2, -1, 1, 2, SEAM_BAND_PX)]
                    if any(v is None for v in prof):
                        continue
                    diffs = [abs(b - a) for a, b in zip(prof, prof[1:])]
                    tvs.append(sum(diffs) / len(diffs))
    return sum(tvs) / len(tvs) if tvs else None


def check_seams(tiles, slots, thr):
    """Every ordered pair of same-family tiles (plus mirrored copies of the
    symmetric ones) across all 4 abutting orientations."""
    zones = sorted({s["zone"] for s in slots})
    worst, worst_zone = 0.0, "-"
    for z in zones:
        idxs = [i for i, s in enumerate(slots) if s["zone"] == z]
        fam = []
        for i in idxs:
            fam.append(tiles[i])
            if slots[i].get("symmetric"):
                fam.append(tiles[i].mirrored())
        base = baseline_tv([tiles[i] for i in idxs])
        if not base:
            continue
        vals = []
        for A in fam:
            for B in fam:
                for d, edge in NEIGHBORS:
                    tv = seam_tv(A, B, d, edge)
                    if tv is not None:
                        vals.append(tv)
        ratio = (sum(vals) / len(vals)) / base if vals else 0.0
        detail(f"zone {z}: seam {ratio:.2f}x baseline "
               f"({len(fam)} variants, baseline TV {base:.4f})")
        if ratio > worst:
            worst, worst_zone = ratio, z
    metric("seam_ratio", f"{worst:.2f}", thr["seam_ratio_max"],
           worst <= thr["seam_ratio_max"])


def check_dark_ridge(tiles, label):
    """Transition tiles only: segmentation likes to paint internal borders
    where rim-fill can't reach. min/median filter residue finds them."""
    worst = 0
    for i, t in enumerate(tiles):
        gray = t.im.convert("L")
        med = gray.filter(ImageFilter.MedianFilter(5))
        mn = gray.filter(ImageFilter.MinFilter(3))
        md, mnd = list(med.get_flattened_data()), list(mn.get_flattened_data())
        count = sum(1 for j in range(t.w * t.h)
                    if t.dist[j] >= 5 and md[j] - mnd[j] > RIDGE_DELTA)
        if count > RIDGE_WARN_PX:
            detail(f"{label} {i}: {count} dark-ridge px")
        worst = max(worst, count)
    metric("dark_ridge_px", worst, RIDGE_WARN_PX, worst <= RIDGE_WARN_PX,
           warn_only=True)


def check_lum_spread(tiles, thr):
    means = [t.mean() for t in tiles]
    spread = max(means) - min(means) if means else 0.0
    metric("lum_spread", f"{spread:.4f}", thr["lum_spread_max"],
           spread <= thr["lum_spread_max"])


def check_transition_classes(tiles, set_tiles, thr):
    tol = thr["transition_class_tol"]
    means = [t.mean() for t in tiles]
    lows = [m for m, st in zip(means, set_tiles)
            if all(v == "lower" for v in st["corners"].values())]
    ups = [m for m, st in zip(means, set_tiles)
           if all(v == "upper" for v in st["corners"].values())]
    if not lows or not ups:
        detail("no pure-lower or pure-upper tile - cannot derive class targets")
        metric("transition_class_dev", "n/a", tol, False)
        return
    lo_m, up_m = sum(lows) / len(lows), sum(ups) / len(ups)
    detail(f"class means: lower {lo_m:.3f}, upper {up_m:.3f}")
    worst = 0.0
    for i, (m, st) in enumerate(zip(means, set_tiles)):
        n_low = sum(1 for v in st["corners"].values() if v == "lower")
        target = (n_low * lo_m + (4 - n_low) * up_m) / 4.0
        dev = abs(m - target)
        if dev > tol:
            detail(f"tile {i} ({n_low} lower corners): mean {m:.3f} vs target "
                   f"{target:.3f} (dev {dev:.3f})")
        worst = max(worst, dev)
    metric("transition_class_dev", f"{worst:.4f}", tol, worst <= tol)


def check_midtone(tiles, thr):
    lo, hi = thr["midtone_min"], thr["midtone_max"]
    bad = 0
    worst = None
    for i, t in enumerate(tiles):
        m = t.mean()
        if not lo <= m <= hi:
            detail(f"tile {i}: mean {m:.3f} outside {lo}..{hi}")
            bad += 1
        if worst is None or abs(m - 0.5) > abs(worst - 0.5):
            worst = m
    metric("midtone_worst", f"{worst:.3f}" if worst is not None else "n/a",
           f"{lo}..{hi}", bad == 0)


def check_palette(tiles, thr):
    cap = thr["palette_per_tile_max"]
    worst = 0
    for i, t in enumerate(tiles):
        n = len(t.colors)
        if n > cap:
            detail(f"tile {i}: {n} colors")
        worst = max(worst, n)
    metric("palette_max", worst, cap, worst <= cap)


def check_lighting(tiles, slots):
    bad = 0
    for i, (t, s) in enumerate(zip(tiles, slots)):
        dx, dy = t.centroid_offset()
        mag = math.hypot(dx, dy)
        if mag <= 2.0:
            continue
        up_left = dx <= LIGHT_DIR_SLACK and dy <= LIGHT_DIR_SLACK
        if not up_left:
            detail(f"slot {i}: centroid offset ({dx:+.1f},{dy:+.1f}) "
                   f"{mag:.1f}px does not point upper-left")
            bad += 1
        if s.get("symmetric"):
            detail(f"slot {i}: {mag:.1f}px asymmetric but sidecar says "
                   f"symmetric:true - it would be mirrored in game")
            bad += 1
    metric("lighting_violations", bad, 0, bad == 0)


def check_sidecar_structure(side, sheet_size, kind):
    bad = 0
    W, H = sheet_size
    rects = [s["rect"] for s in side.get("slots", [])] + \
            [t["rect"] for st in side.get("sets", []) for t in st["tiles"]]
    for r in rects:
        x, y, w, h = r
        if x < 0 or y < 0 or x + w > W or y + h > H:
            detail(f"rect {r} out of sheet bounds {W}x{H}")
            bad += 1
    if kind == "tiles":
        slots = side["slots"]
        if len(slots) != BASE_SLOT_COUNT:
            detail(f"{len(slots)} slots, contract wants {BASE_SLOT_COUNT} "
                   f"(legacy sheets report this until regenerated)")
            bad += 1
        for z in sorted({s["zone"] for s in slots}):
            for role, want in BASE_PER_ZONE.items():
                got = sum(1 for s in slots if s["zone"] == z and s["role"] == role)
                if got != want:
                    detail(f"zone {z}: {got} {role} slots, want {want}")
                    bad += 1
    elif kind == "tileset":
        for st in side["sets"]:
            combos = {}
            for t in st["tiles"]:
                c = t["corners"]
                key = (c["top"], c["right"], c["bottom"], c["left"])
                combos[key] = combos.get(key, 0) + 1
            if len(combos) != 16 or any(v != 1 for v in combos.values()):
                detail(f"set {st.get('lower')}->{st.get('upper')}: "
                       f"{len(combos)} distinct corner combos "
                       f"(dupes: {[k for k, v in combos.items() if v > 1]})")
                bad += 1
    elif kind == "paths":
        for st in side["sets"]:
            n_edges = sum(1 for t in st["tiles"] if "edges" in t)
            detail(f"path set: {n_edges} edge-mask tiles, "
                   f"{len(st['tiles']) - n_edges} stamps")
    metric("sidecar_structure_violations", bad, 0, bad == 0)


# ----------------------------------------------------------------------- main
def load_style(path: Path) -> dict:
    style = json.loads(path.read_text(encoding="utf-8"))
    mask_rel = style.get("diamond_mask", "artgen/reference/diamond_mask.png")
    for c in [Path(mask_rel), path.parent.parent / mask_rel, path.parent / mask_rel]:
        if c.exists():
            style["_mask_path"] = c
            return style
    sys.exit(f"diamond mask not found for {path}")


def crop_diamond(sheet: Image.Image, rect, th: int) -> Image.Image:
    """The bottom `th` rows of a slot rect - tall slots overhang upward."""
    x, y, w, h = rect
    return sheet.crop((x, y + h - th, x + w, y + h))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("sheet", type=Path)
    ap.add_argument("--sidecar", type=Path, required=True)
    ap.add_argument("--style", type=Path, required=True)
    ap.add_argument("--report", action="store_true",
                    help="print metrics without gating (calibration mode)")
    a = ap.parse_args()
    if not a.sheet.exists():
        sys.exit(2)

    style = load_style(a.style)
    thr = style["thresholds"]
    side = json.loads(a.sidecar.read_text(encoding="utf-8"))
    sheet = Image.open(a.sheet).convert("RGBA")
    tw, th = side.get("tile_size", [128, 60])

    mask_im = Image.open(style["_mask_path"]).convert("L")
    mask = [1 if v > 0 else 0 for v in mask_im.get_flattened_data()]

    kind = "tiles" if side.get("slots") else (
        "paths" if any(st.get("mode") == "edge" for st in side.get("sets", []))
        else "tileset")
    print(f"validating {a.sheet} ({kind}, {sheet.width}x{sheet.height})")

    slots = side.get("slots", [])
    set_tiles = [t for st in side.get("sets", []) for t in st["tiles"]]

    if kind == "tiles":
        tiles = [Tile(crop_diamond(sheet, s["rect"], th)) for s in slots]
        check_mask_identity(tiles, slots, mask, tw, th)
        check_rim(tiles, thr)
        check_seams(tiles, slots, thr)
        check_lum_spread(tiles, thr)
        check_midtone(tiles, thr)
        check_palette(tiles, thr)
        check_lighting(tiles, slots)
    else:
        tiles = [Tile(crop_diamond(sheet, t["rect"], th)) for t in set_tiles]
        fake_slots = [{"tall": False} for _ in tiles]
        check_mask_identity(tiles, fake_slots, mask, tw, th)
        check_rim(tiles, thr)
        if kind == "tileset":
            check_dark_ridge(tiles, "transition tile")
            check_transition_classes(tiles, set_tiles, thr)
        check_midtone(tiles, thr)
        check_palette(tiles, thr)
    check_sidecar_structure(side, sheet.size, kind)

    if warns:
        print(f"\n{len(warns)} warning(s): {', '.join(warns)}")
    if a.report:
        print(f"\nREPORT MODE - {len(fails)} would-be failure(s)"
              + (f": {', '.join(fails)}" if fails else ""))
        return 0
    if fails:
        print(f"\nFAILED - {len(fails)} check(s): {', '.join(fails)}")
        return 1
    print("\nPASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
