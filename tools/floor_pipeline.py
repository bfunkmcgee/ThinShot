#!/usr/bin/env python3
"""Post-process raw PixelLab tiles into Sandline floor sheets + sidecars.

Raw generations arrive as square 1:1 diamonds (128x128, or 96x96 from the
isometric tileset/path modes). This tool runs the proven post chain per tile
and composes the sheet the engine actually reads. The chain, in order:

  1. rim inward-fill      - segmentation mode paints ~2px near-black rims on
                            the diamond edge; replace every opaque pixel near
                            the alpha boundary with its nearest interior color
  2. --zoom-crop          - optional fallback: scale 1.08 + center-crop, for
                            art whose rim is a gradient the fill can't reach
  3. crop to diamond bbox - the generator sometimes returns 1:1 diamonds and
                            sometimes pre-squashed 2:1 ones (verified records
                            do both); the alpha bbox is the diamond either way
  4. resize to 128x60     - one Lanczos resize is simultaneously the 2:1
                            squash (1:1 input), the x4/3 upscale (96px modes)
                            and a no-op (pre-squashed 128 input)
  5. diamond alpha mask   - the canonical 128x60 mask; all sheets tile because
                            all sheets share this exact silhouette
  6. edge harmonization   - outer 6px band blended toward the sheet's shared
                            mean color (0% at 6px, 35% at the edge)
  7. luminance normalize  - tiles/paths: pull to the shared mean keeping 15%
                            own deviation (ash: desat 0.45, mean 0.40);
                            tileset: per-corner-class targets - NEVER a single
                            global mean, that would erase the transition
  8. palette clamp        - median-cut to <=96 colors per tile if over

Usage:
    python tools/floor_pipeline.py post --raw <dir> --out <sheet.png> \\
        --style artgen/style.json --kind tiles --biome desert \\
        --slots-map slots.json --sidecar-out <sheet.tiles.json>
    python tools/floor_pipeline.py post --raw <one.png> --out <sheet.png> \\
        --style artgen/style.json --kind tiles --biome desert \\
        --slot 3 --into existing.png
    python tools/floor_pipeline.py preview --sheet <sheet.png> \\
        --sidecar <sheet.tiles.json> --out <patch.png>

kind=tileset needs --rules (corner metadata translated to JSON); kind=paths
takes --rules with per-tile edge bitmask entries. See artgen/PIPELINE.md.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from collections import deque
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow:  python -m pip install pillow")

LANCZOS = Image.Resampling.LANCZOS

# Defaults if style.json lacks a key; style.json is the real authority.
RIM_BAND = 3            # px from alpha boundary that get inward-filled
RIM_INTERIOR = 4        # px from boundary where "interior" color starts
EDGE_BAND = 6           # harmonization band width
EDGE_MAX_BLEND = 0.35   # blend toward sheet mean at the outermost pixel
KEEP_DEVIATION = 0.15   # own luminance deviation a tile keeps
ZOOM_CROP = 1.08
SYM_MAX_PX = 2.0        # brightness-centroid offset for "symmetric"
PREVIEW_W, PREVIEW_H = 12, 8
ACCENT_CHANCE = 0.07    # Board.gd ACCENT_CHANCE
ACCENT_SPACING = 2      # Board.gd ACCENT_MIN_SPACING (Chebyshev)


def lum(p) -> float:
    return (0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]) / 255.0


def numkey(p: Path):
    m = re.search(r"(\d+)", p.stem)
    return (int(m.group(1)) if m else 1 << 30, p.name)


# ---------------------------------------------------------------- pixel plumbing
def cheb_dist(alpha: list[int], w: int, h: int) -> list[int]:
    """Chebyshev distance to the nearest transparent pixel; out-of-bounds
    counts as transparent. Two-pass 8-neighbor chamfer (exact for Chebyshev)."""
    INF = 1 << 20
    d = [0 if a == 0 else INF for a in alpha]
    for i in range(w):                       # canvas border touches "outside"
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
            if x > 0 and d[i - 1] + 1 < best:
                best = d[i - 1] + 1
            if y > 0:
                j = i - w
                if d[j] + 1 < best:
                    best = d[j] + 1
                if x > 0 and d[j - 1] + 1 < best:
                    best = d[j - 1] + 1
                if x < w - 1 and d[j + 1] + 1 < best:
                    best = d[j + 1] + 1
            d[i] = best
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            i = y * w + x
            if d[i] <= 1:
                continue
            best = d[i]
            if x < w - 1 and d[i + 1] + 1 < best:
                best = d[i + 1] + 1
            if y < h - 1:
                j = i + w
                if d[j] + 1 < best:
                    best = d[j] + 1
                if x > 0 and d[j - 1] + 1 < best:
                    best = d[j - 1] + 1
                if x < w - 1 and d[j + 1] + 1 < best:
                    best = d[j + 1] + 1
            d[i] = best
    return d


def flood_fill_colors(data: list, w: int, h: int, targets: set[int],
                      sources: set[int]) -> None:
    """Give every pixel index in `targets` the color of its nearest pixel in
    `sources` (multi-source BFS, 8-neighborhood), in place."""
    src = {}
    q = deque()
    for i in sources:
        src[i] = i
        q.append(i)
    reach = targets | sources
    while q:
        i = q.popleft()
        x, y = i % w, i // w
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if not dx and not dy:
                    continue
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if j in reach and j not in src:
                        src[j] = src[i]
                        q.append(j)
    for i in targets:
        if i in src and src[i] != i:
            c = data[src[i]]
            data[i] = (c[0], c[1], c[2], data[i][3])


def rim_fill(im: Image.Image, band: int, interior: int) -> Image.Image:
    """Stage 1: replace the near-boundary ring with nearest interior color."""
    w, h = im.size
    data = list(im.get_flattened_data())
    dist = cheb_dist([p[3] for p in data], w, h)
    targets = {i for i, d in enumerate(dist) if 1 <= d <= band}
    sources = {i for i, d in enumerate(dist) if d >= interior}
    if not sources or not targets:
        return im
    flood_fill_colors(data, w, h, targets, sources)
    out = Image.new("RGBA", (w, h))
    out.putdata(data)
    return out


def zoom_crop(im: Image.Image, scale: float) -> Image.Image:
    w, h = im.size
    zw, zh = round(w * scale), round(h * scale)
    z = im.resize((zw, zh), LANCZOS)
    ox, oy = (zw - w) // 2, (zh - h) // 2
    return z.crop((ox, oy, ox + w, oy + h))


def apply_mask(im: Image.Image, mask: list[int], w: int, h: int) -> Image.Image:
    """Stage 5: force the canonical silhouette. Pixels the mask wants but the
    tile lacks are filled from the nearest opaque pixel; everything outside
    goes transparent; all alpha becomes binary."""
    data = list(im.get_flattened_data())
    holes = {i for i in range(w * h) if mask[i] and data[i][3] == 0}
    if holes:
        sources = {i for i in range(w * h) if mask[i] and data[i][3] > 0}
        flood_fill_colors(data, w, h, holes, sources)
    out = []
    for i, p in enumerate(data):
        out.append((p[0], p[1], p[2], 255) if mask[i] else (0, 0, 0, 0))
    res = Image.new("RGBA", (w, h))
    res.putdata(out)
    return res


def desaturate(im: Image.Image, amount: float) -> Image.Image:
    """Blend toward per-pixel gray; amount is the surviving saturation."""
    data = [
        p if p[3] == 0 else tuple(
            [round(g + amount * (c - g)) for c, g in zip(p[:3], [lum(p) * 255] * 3)]
            + [p[3]])
        for p in im.get_flattened_data()
    ]
    out = Image.new("RGBA", im.size)
    out.putdata(data)
    return out


def edge_harmonize(im: Image.Image, mask_dist: list[int], mean_rgb, band: int,
                   max_blend: float) -> Image.Image:
    """Stage 6: outer band eased toward the sheet mean so any two tiles meet
    on nearly the same color. 0% at `band` px, max_blend at the edge."""
    w, h = im.size
    data = list(im.get_flattened_data())
    mr, mg, mb = mean_rgb
    for i, p in enumerate(data):
        d = mask_dist[i]
        if p[3] == 0 or d > band - 1:
            continue
        f = max_blend * (band - d) / (band - 1)
        data[i] = (round(p[0] * (1 - f) + mr * f),
                   round(p[1] * (1 - f) + mg * f),
                   round(p[2] * (1 - f) + mb * f), p[3])
    out = Image.new("RGBA", (w, h))
    out.putdata(data)
    return out


def masked_mean_lum(im: Image.Image) -> float:
    ls = [lum(p) for p in im.get_flattened_data() if p[3] > 0]
    return sum(ls) / len(ls) if ls else 0.0


def masked_mean_rgb(ims: list[Image.Image]):
    r = g = b = n = 0
    for im in ims:
        for p in im.get_flattened_data():
            if p[3] > 0:
                r += p[0]; g += p[1]; b += p[2]; n += 1
    return (r / n, g / n, b / n) if n else (128, 128, 128)


def apply_gain(im: Image.Image, gain: float) -> Image.Image:
    data = [
        p if p[3] == 0 else
        (min(255, round(p[0] * gain)), min(255, round(p[1] * gain)),
         min(255, round(p[2] * gain)), p[3])
        for p in im.get_flattened_data()
    ]
    out = Image.new("RGBA", im.size)
    out.putdata(data)
    return out


def palette_clamp(im: Image.Image, cap: int) -> Image.Image:
    data = list(im.get_flattened_data())
    ops = [(i, p) for i, p in enumerate(data) if p[3] > 0]
    if len({p[:3] for _, p in ops}) <= cap:
        return im
    flat = Image.new("RGB", (len(ops), 1))
    flat.putdata([p[:3] for _, p in ops])
    q = flat.quantize(colors=cap, method=Image.Quantize.MEDIANCUT).convert("RGB")
    for (i, p), c in zip(ops, q.get_flattened_data()):
        data[i] = (c[0], c[1], c[2], p[3])
    out = Image.new("RGBA", im.size)
    out.putdata(data)
    return out


def centroid_offset(im: Image.Image) -> tuple[float, float]:
    """Brightness centroid minus mask centroid, in px. Small = mirrorable."""
    sw = sx = sy = mn = mx = my = 0.0
    w, _ = im.size
    for i, p in enumerate(im.get_flattened_data()):
        if p[3] > 0:
            x, y = i % w, i // w
            l = lum(p)
            sx += x * l; sy += y * l; sw += l
            mx += x; my += y; mn += 1
    if not sw or not mn:
        return (0.0, 0.0)
    return (sx / sw - mx / mn, sy / sw - my / mn)


# ------------------------------------------------------------------- style/io
def load_style(path: Path) -> dict:
    style = json.loads(path.read_text(encoding="utf-8"))
    mask_rel = style.get("diamond_mask", "artgen/reference/diamond_mask.png")
    candidates = [Path(mask_rel), path.parent.parent / mask_rel, path.parent / mask_rel]
    for c in candidates:
        if c.exists():
            style["_mask_path"] = c
            break
    else:
        sys.exit(f"diamond mask not found (tried {[str(c) for c in candidates]})")
    style["_style_dir"] = path.parent
    return style


def load_mask(style: dict):
    im = Image.open(style["_mask_path"]).convert("L")
    w, h = im.size
    mask = [1 if v > 0 else 0 for v in im.get_flattened_data()]
    return mask, w, h


def style_hash(style: dict) -> str:
    h = hashlib.sha1()
    for name in ["STYLE.md", "style.json"]:
        f = style["_style_dir"] / name
        if f.exists():
            h.update(f.read_bytes())
    return h.hexdigest()


def slot_rect(style: dict, index: int, cols: int | None = None):
    grid = style["sheet_grid"]
    tile = style["tile"]
    cols = cols or grid["cols"]
    col, row = index % cols, index // cols
    return [col * tile["stride"], grid["rows_y"][row], tile["w"], tile["h"]]


def sheet_size(style: dict, n_slots: int):
    grid, tile = style["sheet_grid"], style["tile"]
    rows = math.ceil(n_slots / grid["cols"])
    w = (grid["cols"] - 1) * tile["stride"] + tile["w"]
    h = grid["rows_y"][rows - 1] + tile["h"] + grid["rows_y"][0]
    return w, h, rows


# ----------------------------------------------------------------------- post
def stage_a(path: Path, style: dict, mask, mw, mh, args) -> Image.Image:
    """Everything before sheet-wide statistics: rim fill, crop, resize, mask."""
    post = style.get("post", {})
    im = Image.open(path).convert("RGBA")
    im = rim_fill(im, post.get("rim_fill_band_px", RIM_BAND),
                  post.get("rim_fill_interior_px", RIM_INTERIOR))
    bbox = im.getchannel("A").getbbox()
    if bbox:
        im = im.crop(bbox)   # the diamond, whether 1:1, 2:1 or 96px-capped
        ratio = im.height / im.width
        if not (0.85 <= ratio <= 1.15 or 0.40 <= ratio <= 0.60):
            print(f"  note: {path.name} diamond bbox {im.width}x{im.height} is "
                  f"neither 1:1 nor 2:1 - overhanging detail? resizing anyway")
    if args.zoom_crop:
        im = zoom_crop(im, post.get("zoom_crop_scale", ZOOM_CROP))
    im = im.resize((mw, mh), LANCZOS)   # squash / upscale / no-op, all in one
    im = apply_mask(im, mask, mw, mh)
    biome_cfg = style["biomes"].get(args.biome or "", {})
    if "desat" in biome_cfg:
        im = desaturate(im, biome_cfg["desat"])
    return im


def corner_targets(rules: dict, tiles: list, means: list[float], tol: float,
                   keep: float):
    """Per-corner-class luminance targets for a transition set. Pure tiles
    define the two class means; mixed tiles get a corner-count-weighted blend.
    A single global mean here would flatten the transition into mud."""
    corner_of = {t["index"]: t["corners"] for t in rules["tiles"]}
    lows, ups = [], []
    for i, m in enumerate(means):
        c = corner_of.get(i)
        if not c:
            continue
        n_low = sum(1 for v in c.values() if v == "lower")
        if n_low == 4:
            lows.append(m)
        elif n_low == 0:
            ups.append(m)
    lower_mean = rules.get("lower_mean", sum(lows) / len(lows) if lows else sum(means) / len(means))
    upper_mean = rules.get("upper_mean", sum(ups) / len(ups) if ups else sum(means) / len(means))
    targets = []
    for i, m in enumerate(means):
        c = corner_of.get(i)
        if not c:
            targets.append(sum(means) / len(means))
            continue
        n_low = sum(1 for v in c.values() if v == "lower")
        t = (n_low * lower_mean + (4 - n_low) * upper_mean) / 4.0
        dev = max(-0.8 * tol, min(0.8 * tol, keep * (m - t)))
        targets.append(t + dev)     # kept deviation clamped inside the class band
    return targets, lower_mean, upper_mean


def cmd_post(a):
    style = load_style(Path(a.style))
    mask, mw, mh = load_mask(style)
    post = style.get("post", {})
    thr = style["thresholds"]
    keep = post.get("keep_deviation", KEEP_DEVIATION)
    biome_cfg = style["biomes"].get(a.biome or "", {})

    raw = Path(a.raw)
    files = [raw] if raw.is_file() else sorted(raw.glob("*.png"), key=numkey)
    if not files:
        sys.exit(f"no PNGs under {raw}")
    if a.slot is not None and len(files) != 1:
        sys.exit(f"--slot regen expects exactly one raw tile, found {len(files)}")

    rules = json.loads(Path(a.rules).read_text(encoding="utf-8")) if a.rules else None
    if a.kind == "tileset" and not rules:
        sys.exit("--kind tileset needs --rules (corner metadata JSON)")
    slots_map = json.loads(Path(a.slots_map).read_text(encoding="utf-8")) if a.slots_map else {}

    print(f"post: {len(files)} raw tile(s), kind={a.kind} biome={a.biome or '-'}")
    tiles = [stage_a(f, style, mask, mw, mh, a) for f in files]

    # ---- sheet-wide statistics ----
    if a.into:
        # single-slot regen: statistics come from the sheet being repaired
        existing = Image.open(a.into).convert("RGBA")
        grid = style["sheet_grid"]
        pool = []
        for row, ry in enumerate(grid["rows_y"]):
            if ry + mh > existing.height:
                break
            for col in range(grid["cols"]):
                x, y, w, h = slot_rect(style, row * grid["cols"] + col)
                tile = existing.crop((x, y, x + w, y + h))
                if tile.getchannel("A").getextrema()[1] > 0:
                    pool.append(tile)
        if not pool:
            sys.exit(f"--into sheet {a.into} has no populated slots")
        mean_rgb = masked_mean_rgb(pool)
        batch_mean = sum(masked_mean_lum(t) for t in pool) / len(pool)
    else:
        mean_rgb = masked_mean_rgb(tiles)
        batch_mean = sum(masked_mean_lum(t) for t in tiles) / len(tiles)

    means = [masked_mean_lum(t) for t in tiles]
    shared = biome_cfg.get("lum_mean", batch_mean)
    if a.kind == "tileset":
        targets, lo_m, up_m = corner_targets(rules, tiles, means,
                                             thr["transition_class_tol"], keep)
        print(f"  corner classes: lower={lo_m:.3f} upper={up_m:.3f}")
    else:
        targets = [shared + keep * (m - batch_mean) for m in means]
    print(f"  raw means {min(means):.3f}..{max(means):.3f} "
          f"(spread {max(means) - min(means):.3f}) -> target around {shared:.3f}")

    # ---- normalize, then harmonize, then clamp ----
    # Normalization first: harmonizing before it blends edges toward the RAW
    # batch mean, which biases every ring brighter/darker than its own tile
    # (measured +10% on dense-crack tiles) - exactly the lattice the rim
    # check exists to catch, just inverted.
    mask_dist = cheb_dist(mask, mw, mh)
    band = post.get("edge_band_px", EDGE_BAND)
    blend = post.get("edge_band_max_blend", EDGE_MAX_BLEND)
    normed = []
    for t, target in zip(tiles, targets):
        m = masked_mean_lum(t)
        normed.append(apply_gain(t, target / m if m else 1.0))
    if not a.into:
        mean_rgb = masked_mean_rgb(normed)   # sheet color AFTER normalization
    out_tiles = []
    for t in normed:
        t = edge_harmonize(t, mask_dist, mean_rgb, band, blend)
        t = palette_clamp(t, thr["palette_per_tile_max"])
        out_tiles.append(t)
    final_means = [masked_mean_lum(t) for t in out_tiles]
    print(f"  final means {min(final_means):.3f}..{max(final_means):.3f} "
          f"(spread {max(final_means) - min(final_means):.3f})")

    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    # ---- single-slot regen path ----
    if a.into:
        sheet = Image.open(a.into).convert("RGBA")
        x, y, w, h = slot_rect(style, a.slot)
        sheet.paste(out_tiles[0], (x, y))
        sheet.save(out)
        print(f"  slot {a.slot} replaced in {a.into} -> {out}")
        return

    # ---- layout ----
    n = len(out_tiles)
    w, h, rows = sheet_size(style, n)
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rects = []
    for i, t in enumerate(out_tiles):
        x, y, tw, th = slot_rect(style, i)
        sheet.paste(t, (x, y))
        rects.append([x, y, tw, th])
    sheet.save(out)
    print(f"  sheet {w}x{h} ({n} slots, {rows} rows) -> {out}")

    # ---- sidecar ----
    if not a.sidecar_out:
        return
    sym_max = post.get("symmetric_centroid_max_px", SYM_MAX_PX)
    slots = []
    sets = []
    metrics = {"slot_mean_lum": [round(m, 4) for m in final_means]}
    if a.kind == "tiles":
        for i, t in enumerate(out_tiles):
            info = slots_map.get(str(i), {})
            dx, dy = centroid_offset(t)
            slots.append({
                "rect": rects[i],
                "zone": info.get("zone", "B"),
                "role": info.get("role", "base"),
                "symmetric": math.hypot(dx, dy) <= sym_max,
                "tall": False,
            })
    elif a.kind == "tileset":
        corner_of = {t["index"]: t["corners"] for t in rules["tiles"]}
        sets.append({
            "lower": rules.get("lower", "A"),
            "upper": rules.get("upper", "B"),
            "tiles": [{"rect": rects[i], "corners": corner_of[i]}
                      for i in range(n) if i in corner_of],
        })
    elif a.kind == "paths":
        entries = []
        edge_of = {t["index"]: t for t in (rules or {}).get("tiles", [])}
        for i in range(n):
            e = edge_of.get(i, {})
            if "edges" in e:
                entries.append({"rect": rects[i], "edges": e["edges"]})
            else:
                entries.append({"rect": rects[i], "role": e.get("role", "stamp")})
        sets.append({"mode": "edge", "tiles": entries})
    sidecar = {
        "sheet": out.name,
        "tile_size": [mw, mh],
        "slots": slots,
        "sets": sets,
        "provenance": {
            "batch": a.batch_name,
            "job_ids": a.job_id or [],
            "seed": a.seed,
            "style_hash": style_hash(style),
        },
        "metrics": metrics,
    }
    Path(a.sidecar_out).write_text(json.dumps(sidecar, indent=2), encoding="utf-8")
    print(f"  sidecar -> {a.sidecar_out}")


# -------------------------------------------------------------------- preview
def hash01(x: int, y: int, salt: int) -> float:
    """Board.gd _hash01, verbatim: the preview must pick like the engine."""
    return (abs(x * 92821 + y * 31337 + salt * 53987) % 997) / 997.0


def vnoise(x: float, y: float, seed: int) -> float:
    def rnd(ix, iy):
        n = (ix * 92821 + iy * 31337 + seed * 53987) & 0x7FFFFFFF
        n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF
        return ((n ^ (n >> 16)) % 9973) / 9973.0
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = rnd(ix, iy), rnd(ix + 1, iy)
    c, d = rnd(ix, iy + 1), rnd(ix + 1, iy + 1)
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy


def crop_slot(sheet: Image.Image, rect) -> Image.Image:
    x, y, w, h = rect
    return sheet.crop((x, y, x + w, y + h))


def cmd_preview(a):
    sheet = Image.open(a.sheet).convert("RGBA")
    side = json.loads(Path(a.sidecar).read_text(encoding="utf-8"))
    tw, th = side["tile_size"]
    hw, hh = tw // 2, th // 2
    W, H = PREVIEW_W, PREVIEW_H
    ox, oy = (H - 1) * hw + hw, hh
    canvas = Image.new("RGBA", ((W + H) * hw + tw // 4, (W + H) * hh + th),
                       (26, 23, 19, 255))

    def paste(tile: Image.Image, cx: int, cy: int, flip: bool):
        if flip:
            tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        px = ox + (cx - cy) * hw - hw
        py = oy + (cx + cy) * hh - hh - (tile.height - th)
        canvas.alpha_composite(tile, (px, py))

    if side.get("slots"):
        zones = sorted({s["zone"] for s in side["slots"]})
        fam = {z: [i for i, s in enumerate(side["slots"])
                   if s["zone"] == z and s["role"] == "base"] for z in zones}
        acc = {z: [i for i, s in enumerate(side["slots"])
                   if s["zone"] == z and s["role"] == "accent"] for z in zones}
        vals = sorted(vnoise(x * 0.35, y * 0.35, 7)
                      for y in range(H) for x in range(W))
        t1, t2 = vals[len(vals) // 3], vals[2 * len(vals) // 3]
        accents: list[tuple[int, int]] = []
        for y in range(H):
            for x in range(W):
                v = vnoise(x * 0.35, y * 0.35, 7)
                zi = 0 if v < t1 else (1 if v < t2 else 2)
                z = zones[min(zi, len(zones) - 1)]
                family = fam[z] or [0]
                idx = family[int(hash01(x, y, 1) * len(family)) % len(family)]
                if acc[z] and hash01(x, y, 2) < ACCENT_CHANCE and all(
                        max(abs(px - x), abs(py - y)) > ACCENT_SPACING
                        for px, py in accents):
                    idx = acc[z][int(hash01(x, y, 4) * len(acc[z])) % len(acc[z])]
                    accents.append((x, y))
                s = side["slots"][idx]
                flip = s["symmetric"] and hash01(x, y, 3) < 0.5
                paste(crop_slot(sheet, s["rect"]), x, y, flip)
    elif side.get("sets"):
        st = side["sets"][0]
        if st.get("mode") == "edge":
            sys.exit("preview: path (edge-mode) sidecars have no board preview yet")
        by_corners = {}
        for t in st["tiles"]:
            c = t["corners"]
            key = (c["top"], c["right"], c["bottom"], c["left"])
            by_corners[key] = t["rect"]
        # vertex grid: lower on the left half, noise-wobbled boundary
        vert = {}
        for vy in range(H + 1):
            for vx in range(W + 1):
                wob = (vnoise(vy * 0.5, vx * 0.5, 11) - 0.5) * 3.0
                vert[(vx, vy)] = "lower" if vx + wob < W / 2 else "upper"
        for y in range(H):
            for x in range(W):
                key = (vert[(x, y)], vert[(x + 1, y)],
                       vert[(x + 1, y + 1)], vert[(x, y + 1)])
                rect = by_corners.get(key)
                if rect is None:
                    continue
                paste(crop_slot(sheet, rect), x, y, False)
    else:
        sys.exit("sidecar has neither slots nor sets - nothing to preview")

    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    print(f"preview {canvas.width}x{canvas.height} -> {out}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("post", help="post-process raw tiles into a sheet + sidecar")
    p.add_argument("--raw", required=True, help="raw tile dir (or a single PNG with --slot)")
    p.add_argument("--out", required=True, help="sheet PNG to write")
    p.add_argument("--style", required=True, help="artgen/style.json")
    p.add_argument("--kind", required=True, choices=["tiles", "tileset", "paths"])
    p.add_argument("--biome", default=None)
    p.add_argument("--slot", type=int, default=None, help="single-slot regen index")
    p.add_argument("--into", default=None, help="existing sheet the regen slots into")
    p.add_argument("--sidecar-out", default=None)
    p.add_argument("--slots-map", default=None,
                   help='JSON: {"0": {"zone": "A", "role": "base"}, ...}')
    p.add_argument("--rules", default=None,
                   help="corner/edge metadata JSON (tileset and paths kinds)")
    p.add_argument("--zoom-crop", action="store_true",
                   help="fallback: 1.08 zoom + center-crop before the squash")
    p.add_argument("--batch-name", default=None)
    p.add_argument("--job-id", action="append", default=None)
    p.add_argument("--seed", type=int, default=None)
    p.set_defaults(fn=cmd_post)

    p = sub.add_parser("preview", help="synthetic 12x8 board patch from a finished sheet")
    p.add_argument("--sheet", required=True)
    p.add_argument("--sidecar", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(fn=cmd_preview)

    a = ap.parse_args()
    if getattr(a, "slot", None) is not None and not getattr(a, "into", None):
        ap.error("--slot needs --into <existing sheet>")
    a.fn(a)


if __name__ == "__main__":
    main()
