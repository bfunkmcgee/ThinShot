#!/usr/bin/env python3
"""Contact-sheet builder for floor sheets (make_char_viewer.py pattern).

Emits an index.html for the user AND flat PNGs beside it for Claude to Read:

    <name>_slots.png    every slot at 2x with index/zone/role captions
    <name>_seams.png    per-zone 3x3 patches composited at true iso offsets
                        with the engine's real selection rules (variant hash,
                        mirror only when the sidecar says symmetric), an
                        accent-in-context patch, and transition boundary
                        strips when a transition sheet is given
    <name>_compare.png  new slots over old slots, aligned by index

Usage:
    python tools/make_tile_viewer.py <sheet.png> --sidecar <sheet.tiles.json> \\
        [--compare <old_sheet.png>] \\
        [--transitions <t.png> --t-sidecar <t.tiles.json>] \\
        -o artgen/staging/<batch>/preview/index.html

The HTML references the sheet by relative path - rerun a generation, refresh
the page, see the new art.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("needs Pillow:  python -m pip install pillow")

NEAREST = Image.Resampling.NEAREST
PATCH = 3                  # 3x3 seam patches
HW, HH = 64, 30            # half tile: true iso neighbor offsets are (+-64,+-30)
SCALE = 2                  # flat PNGs render at 2x
BG = (26, 23, 19, 255)
INK = (232, 226, 214)
DIM = (155, 145, 132)
# legacy 10-slot grid for --compare sheets (515x386); the desert tall slot's
# diamond bottom-60 lands on the same rect as the flat table
LEGACY_RECTS = [(x, y, 128, 60) for y in (34, 163, 292) for x in (0, 129, 258, 387)][:10]
LEGACY_ORDER = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]


def hash01(x: int, y: int, salt: int) -> float:
    """Board.gd _hash01, verbatim."""
    return (abs(x * 92821 + y * 31337 + salt * 53987) % 997) / 997.0


def crop(sheet: Image.Image, rect) -> Image.Image:
    x, y, w, h = rect
    return sheet.crop((x, y, x + w, y + h))


def diamond(sheet: Image.Image, rect, th=60) -> Image.Image:
    x, y, w, h = rect
    return sheet.crop((x, y + h - th, x + w, y + h))


def compose_patch(picks) -> Image.Image:
    """picks: {(x,y): (tile_img, flip)} composited at true iso offsets."""
    xs = [x for x, y in picks]
    ys = [y for x, y in picks]
    n = max(xs) + 1, max(ys) + 1
    ox = (n[1] - 1) * HW + HW
    w = (n[0] + n[1]) * HW + HW
    h = (n[0] + n[1]) * HH + HH * 2
    out = Image.new("RGBA", (w, h), BG)
    for y in range(n[1]):
        for x in range(n[0]):
            if (x, y) not in picks:
                continue
            tile, flip = picks[(x, y)]
            if flip:
                tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            px = ox + (x - y) * HW - HW
            py = HH + (x + y) * HH - HH - (tile.height - 60)
            out.alpha_composite(tile, (px, py))
    return out


def stack(blocks, pad=10) -> Image.Image:
    """[(label, image)] -> one labeled vertical strip."""
    w = max(im.width for _, im in blocks) + 2 * pad
    h = sum(im.height + 16 + pad for _, im in blocks) + pad
    out = Image.new("RGBA", (w, h), BG)
    d = ImageDraw.Draw(out)
    y = pad
    for label, im in blocks:
        d.text((pad, y), label, fill=INK)
        out.alpha_composite(im, (pad, y + 14))
        y += im.height + 16 + pad
    return out


def scale2(im: Image.Image) -> Image.Image:
    return im.resize((im.width * SCALE, im.height * SCALE), NEAREST)


# --------------------------------------------------------------- PNG builders
def build_slots_png(sheet, slots, out_path):
    cell_w, cap_h = 128 * SCALE + 12, 26
    cell_h = 66 * SCALE + cap_h + 12
    cols = 4
    rows = (len(slots) + cols - 1) // cols
    out = Image.new("RGBA", (cols * cell_w + 12, rows * cell_h + 12), BG)
    d = ImageDraw.Draw(out)
    for i, s in enumerate(slots):
        tile = scale2(crop(sheet, s["rect"]))
        cx = 12 + (i % cols) * cell_w
        cy = 12 + (i // cols) * cell_h + (66 * SCALE - tile.height)
        out.alpha_composite(tile, (cx, cy))
        cap = (f"{i}  zone {s.get('zone', '?')} {s.get('role', '?')}"
               + ("  sym" if s.get("symmetric") else "")
               + ("  tall" if s.get("tall") else ""))
        d.text((cx, 12 + (i // cols) * cell_h + 66 * SCALE + 4), cap, fill=INK)
    out.save(out_path)


def build_seams_png(sheet, slots, t_sheet, t_side, out_path):
    zones = sorted({s["zone"] for s in slots})
    blocks = []
    for z in zones:
        base = [i for i, s in enumerate(slots) if s["zone"] == z and s["role"] == "base"]
        acc = [i for i, s in enumerate(slots) if s["zone"] == z and s["role"] == "accent"]
        if not base:
            continue
        picks = {}
        for y in range(PATCH):
            for x in range(PATCH):
                i = base[int(hash01(x, y, 1) * len(base)) % len(base)]
                flip = slots[i].get("symmetric") and hash01(x, y, 3) < 0.5
                picks[(x, y)] = (diamond(sheet, slots[i]["rect"]), flip)
        blocks.append((f"zone {z}: 3x3 base patch (real selection + mirror rules)",
                       scale2(compose_patch(picks))))
        for k, ai in enumerate(acc):
            picks2 = dict(picks)
            picks2[(1, 1)] = (crop(sheet, slots[ai]["rect"]), False)
            blocks.append((f"zone {z}: accent slot {ai} in context",
                           scale2(compose_patch(picks2))))
    if t_sheet is not None:
        for st in t_side.get("sets", []):
            if st.get("mode") == "edge":
                continue
            by_c = {}
            for t in st["tiles"]:
                c = t["corners"]
                by_c[(c["top"], c["right"], c["bottom"], c["left"])] = t["rect"]
            picks = {}
            w, h = 4, 3
            for y in range(h):
                for x in range(w):
                    def v(vx, vy):
                        return "lower" if vx < w / 2 else "upper"
                    key = (v(x, y), v(x + 1, y), v(x + 1, y + 1), v(x, y + 1))
                    if key in by_c:
                        picks[(x, y)] = (diamond(t_sheet, by_c[key]), False)
            blocks.append((f"transition {st.get('lower')} -> {st.get('upper')}: "
                           "boundary strip", scale2(compose_patch(picks))))
    if blocks:
        stack(blocks).save(out_path)
        return True
    return False


def build_compare_png(sheet, slots, old_sheet, out_path):
    if old_sheet.size == (515, 386):
        old_rects = LEGACY_RECTS
    else:
        old_rects = [s["rect"] for s in slots]
    n = max(len(slots), len(old_rects))
    cell_w = 128 * SCALE + 8
    row_h = 66 * SCALE + 20
    out = Image.new("RGBA", (n * cell_w + 8, 2 * row_h + 30), BG)
    d = ImageDraw.Draw(out)
    d.text((8, 4), "new", fill=INK)
    d.text((8, row_h + 18), "old (shipped)", fill=DIM)
    for i in range(n):
        if i < len(slots):
            t = scale2(crop(sheet, slots[i]["rect"]))
            out.alpha_composite(t, (8 + i * cell_w, 18 + (66 * SCALE - t.height)))
        if i < len(old_rects):
            t = scale2(crop(old_sheet, list(old_rects[i])))
            out.alpha_composite(t, (8 + i * cell_w, row_h + 32))
        d.text((8 + i * cell_w, 4), "", fill=DIM)
    out.save(out_path)


# ----------------------------------------------------------------------- HTML
HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>__NAME__ - tile sheet</title>
<style>
  :root { --bg:#14120f; --panel:#1e1b17; --line:#332e27; --ink:#e8e2d6;
          --dim:#9b9184; --accent:#d8a24a; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--ink);
         font:13px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace; }
  header { position:sticky; top:0; z-index:10; background:var(--panel);
           border-bottom:1px solid var(--line); padding:10px 16px;
           display:flex; flex-wrap:wrap; gap:14px; align-items:center; }
  h1 { font-size:14px; margin:0 12px 0 0; color:var(--accent); font-weight:600; }
  label { color:var(--dim); display:inline-flex; align-items:center; gap:6px; }
  input[type=range],button { background:#2a2620; color:var(--ink);
    border:1px solid var(--line); border-radius:4px; padding:3px 7px; font:inherit; }
  button { cursor:pointer; }
  button:hover { border-color:var(--accent); }
  main { padding:16px; }
  h2 { font-size:12px; color:var(--dim); font-weight:600; letter-spacing:.08em;
       text-transform:uppercase; margin:22px 0 8px; }
  .grid { display:flex; flex-wrap:wrap; gap:10px; }
  .cell { background:#100e0c; border:1px solid var(--line); border-radius:5px;
          padding:6px; }
  .cell.light { background:#cfc8ba; }
  .cell.sand { background:#c2a878; }
  .tile { image-rendering:pixelated; background-repeat:no-repeat; }
  .cap { color:var(--dim); font-size:11px; margin-top:4px; }
  .cell.light .cap, .cell.sand .cap { color:#4a4238; }
  img.flat { image-rendering:pixelated; max-width:100%; border:1px solid var(--line);
             border-radius:5px; }
</style>
</head>
<body>
<header>
  <h1>__NAME__</h1>
  <label>zoom <input type="range" id="zoom" min="1" max="6" step="1" value="2">
    <span id="zoomv">2x</span></label>
  <button id="bg">bg</button>
  <span style="color:var(--dim)">__META__</span>
</header>
<main>
  <h2>slots</h2>
  <div class="grid" id="slots"></div>
  <div id="flats"></div>
</main>
<script>
const SHEET = "__SHEET__";
const SHEET_W = __SHEET_W__, SHEET_H = __SHEET_H__;
const SLOTS = __SLOTS__;
const FLATS = __FLATS__;
let zoom = 2, bgMode = 0;
const BGS = ['', 'light', 'sand'];

function render() {
  const g = document.getElementById('slots');
  g.innerHTML = '';
  SLOTS.forEach((s, i) => {
    const [x, y, w, h] = s.rect;
    const cell = document.createElement('div');
    cell.className = 'cell ' + BGS[bgMode];
    const t = document.createElement('div');
    t.className = 'tile';
    t.style.width = (w * zoom) + 'px';
    t.style.height = (h * zoom) + 'px';
    t.style.backgroundImage = 'url(' + SHEET + ')';
    t.style.backgroundSize = (SHEET_W * zoom) + 'px ' + (SHEET_H * zoom) + 'px';
    t.style.backgroundPosition = (-x * zoom) + 'px ' + (-y * zoom) + 'px';
    const cap = document.createElement('div');
    cap.className = 'cap';
    cap.textContent = i + '  zone ' + (s.zone || '?') + ' ' + (s.role || '') +
      (s.symmetric ? ' sym' : '') + (s.tall ? ' tall' : '');
    cell.append(t, cap);
    g.append(cell);
  });
  const f = document.getElementById('flats');
  f.innerHTML = '';
  FLATS.forEach(([title, src]) => {
    const h = document.createElement('h2');
    h.textContent = title;
    const img = document.createElement('img');
    img.className = 'flat';
    img.src = src;
    f.append(h, img);
  });
}
document.getElementById('zoom').oninput = e => {
  zoom = +e.target.value;
  document.getElementById('zoomv').textContent = zoom + 'x';
  render();
};
document.getElementById('bg').onclick = () => { bgMode = (bgMode + 1) % 3; render(); };
render();
</script>
</body>
</html>
"""


def relpath(p: Path, start: Path) -> str:
    return os.path.relpath(p.resolve(), start.resolve()).replace("\\", "/")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("sheet", type=Path)
    ap.add_argument("--sidecar", type=Path, required=True)
    ap.add_argument("--compare", type=Path, default=None,
                    help="shipped sheet to diff against")
    ap.add_argument("--transitions", type=Path, default=None)
    ap.add_argument("--t-sidecar", type=Path, default=None)
    ap.add_argument("-o", "--out", type=Path, required=True,
                    help="index.html path; flat PNGs land beside it")
    a = ap.parse_args()
    if bool(a.transitions) != bool(a.t_sidecar):
        ap.error("--transitions and --t-sidecar go together")

    sheet = Image.open(a.sheet).convert("RGBA")
    side = json.loads(a.sidecar.read_text(encoding="utf-8"))
    slots = side.get("slots", [])
    if not slots and side.get("sets"):
        # a transition/path sheet viewed directly: synthesize slot entries
        slots = [{"rect": t["rect"], "zone": "-",
                  "role": ",".join(f"{k}:{v[0]}" for k, v in t["corners"].items())
                  if "corners" in t else t.get("role", "edge")}
                 for st in side["sets"] for t in st["tiles"]]

    out_dir = a.out.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    name = a.sheet.stem
    flats = []

    slots_png = out_dir / f"{name}_slots.png"
    build_slots_png(sheet, slots, slots_png)
    flats.append(("slots at 2x", slots_png.name))
    print(f"wrote {slots_png}")

    t_sheet = Image.open(a.transitions).convert("RGBA") if a.transitions else None
    t_side = json.loads(a.t_sidecar.read_text(encoding="utf-8")) if a.t_sidecar else {}
    if side.get("slots"):
        seams_png = out_dir / f"{name}_seams.png"
        if build_seams_png(sheet, side["slots"], t_sheet, t_side, seams_png):
            flats.append(("seam patches (iso composite, real rules)", seams_png.name))
            print(f"wrote {seams_png}")

    if a.compare:
        old = Image.open(a.compare).convert("RGBA")
        compare_png = out_dir / f"{name}_compare.png"
        build_compare_png(sheet, slots, old, compare_png)
        flats.append(("new vs shipped", compare_png.name))
        print(f"wrote {compare_png}")

    html = (HTML
            .replace("__NAME__", name)
            .replace("__SHEET__", relpath(a.sheet, out_dir))
            .replace("__SHEET_W__", str(sheet.width))
            .replace("__SHEET_H__", str(sheet.height))
            .replace("__SLOTS__", json.dumps(slots))
            .replace("__FLATS__", json.dumps(flats))
            .replace("__META__", f"{len(slots)} slots - {sheet.width}x{sheet.height}"))
    a.out.write_text(html, encoding="utf-8")
    print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
