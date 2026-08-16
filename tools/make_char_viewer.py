#!/usr/bin/env python3
"""Build a standalone HTML character test screen for a generated unit.

    python tools/make_char_viewer.py assets/sprites/Rodar_Akai
    python tools/make_char_viewer.py assets/sprites/Civilian
    python tools/make_char_viewer.py assets/sprites/Rodar_Akai --compare assets/sprites/Rodar_Akai_old

Writes tools/charviewer_<Unit>.html (or <unit>/preview.html via build_viewer).
Open it straight from disk - it references the PNGs by relative path rather
than embedding them, so re-running a generation and refreshing the page shows
the new art immediately.

Density-aware since the hi-res program: each unit renders at its own display
scale (legacy 60/64/56 sheets at 2x, hi-res 120/128/112 sheets at 1x), taken
from the validator's per-set spec table when available, so a hi-res unit and
a legacy unit occupy the same on-screen size at the same zoom.

`--compare <old_unit_root>` is the judge-gate view for the hi-res probe and
pilot: it renders the old set at its scale beside the new set at its scale -
per state, per rotation, and per animation set - so a regen is approved (or
bounced) on a single page.
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

DIRS = ["north-west", "north", "north-east",
        "west", None, "east",
        "south-west", "south", "south-east"]
ORDER = ["east", "south-east", "south", "south-west",
         "west", "north-west", "north", "north-east"]

# playback rates and loop/one-shot behaviour, from UNIT_ASSET_SPEC.md section 3
SETS = {
    "standing_idle": (8, True),
    "standing_idle_alt": (8, True),
    "standing_idle_walk": (18, True),
    "standing_idle_to_readyToFire": (36, False),
    "standing-readyToFire_idle": (8, True),
    "standing_idle_to_dead": (14, False),
    "standing_idle_damage": (18, False),
    "standing_idle_reload": (14, False),
    "cower_idle": (8, True),
}


def png_size(p: Path):
    """Width/height straight out of the IHDR - no imaging library needed."""
    with open(p, "rb") as f:
        head = f.read(24)
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def unit_spec(unit: Path) -> dict:
    """{canvas, dscale, footfrac} for the unit. Single source of truth is the
    validator's per-set spec table (SPECS / HIRES_PROFILES); if that import
    is unavailable (no Pillow), fall back to inferring from the canvas size:
    >=96px is hi-res drawn at 1x, everything else is legacy at 2x."""
    canvas = None
    for p in unit.rglob("*.png"):
        if p.name in ("preview.png",):
            continue
        s = png_size(p)
        if s:
            canvas = s[0]
            break
    canvas = canvas or 60
    try:
        sys.path.insert(0, str(Path(__file__).parent))
        from validate_unit_sprites import resolve_spec
        spec, _ = resolve_spec(unit)
        canvas = spec["canvas"][0]
        dscale = spec["display_scale"]
        anchor = spec["foot_anchor"]
    except Exception:
        dscale = 1 if canvas >= 96 else 2
        anchor = {56: 14, 112: 28, 120: 30, 128: 32}.get(canvas, 15)
    return {"name": unit.name, "canvas": canvas, "dscale": dscale,
            "footfrac": (canvas / 2 + anchor) / canvas}


def state_rank(label: str) -> int:
    """standing first, dead last, everything else in between - reads as a
    progression rather than an alphabetical jumble."""
    low = label.lower()
    if low == "standing":
        return 0
    if "dead" in low:
        return 2
    return 1


def scan(unit: Path, html_dir: Path):
    rotations, anims = {}, {}
    found = []
    for rot in sorted(unit.rglob("rotations")):
        frames = {d: rot / f"{d}.png" for d in ORDER if (rot / f"{d}.png").exists()}
        if frames:
            # the base state's folder repeats the unit name, which reads oddly
            # in a list next to Dead_stance / ReadyToFire_Stance
            label = "standing" if rot.parent.name == unit.name else rot.parent.name
            found.append((label, frames))
    for label, frames in sorted(found, key=lambda kv: (state_rank(kv[0]), kv[0])):
        rotations[label] = {d: relpath(p, html_dir) for d, p in frames.items()}
    for anim in sorted(unit.rglob("animations/*")):
        if not anim.is_dir():
            continue
        per_dir = {}
        for d in ORDER:
            fs = sorted((anim / d).glob("*.png"), key=lambda p: p.name)
            if fs:
                per_dir[d] = [relpath(p, html_dir) for p in fs]
        if per_dir:
            fps, loop = SETS.get(anim.name, (12, True))
            anims[anim.name] = {"fps": fps, "loop": loop, "dirs": per_dir}
    return rotations, anims


def relpath(p: Path, start: Path) -> str:
    import os
    return os.path.relpath(p.resolve(), start.resolve()).replace("\\", "/")


HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>__TITLE__</title>
<style>
  :root {
    --bg:#14120f; --panel:#1e1b17; --line:#332e27; --ink:#e8e2d6; --dim:#9b9184;
    --accent:#d8a24a;
  }
  * { box-sizing:border-box; }
  [hidden] { display:none !important; }   /* label is inline-flex, which would win otherwise */
  body {
    margin:0; background:var(--bg); color:var(--ink);
    font:13px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace;
  }
  header {
    position:sticky; top:0; z-index:10; background:var(--panel);
    border-bottom:1px solid var(--line); padding:10px 16px;
    display:flex; flex-wrap:wrap; gap:14px; align-items:center;
  }
  h1 { font-size:14px; margin:0 12px 0 0; color:var(--accent); font-weight:600; }
  label { color:var(--dim); display:inline-flex; align-items:center; gap:6px; }
  select,input[type=range],button {
    background:#2a2620; color:var(--ink); border:1px solid var(--line);
    border-radius:4px; padding:3px 7px; font:inherit;
  }
  button { cursor:pointer; }
  button:hover { border-color:var(--accent); }
  button.on { background:var(--accent); color:#1a160f; border-color:var(--accent); }
  main { padding:16px; }
  .grid {
    display:grid; grid-template-columns:repeat(3,max-content);
    gap:10px; justify-content:start;
  }
  /* keep a one-shot readable as a single filmstrip rather than letting it wrap */
  .row { display:flex; flex-wrap:nowrap; gap:10px; overflow-x:auto; padding-bottom:4px;
         align-items:flex-end; }
  .cell { background:#100e0c; border:1px solid var(--line); border-radius:5px; padding:4px; }
  .cell.center { background:transparent; border:none; }
  .cell.old { border-color:#6a5232; }
  .pair { display:flex; gap:4px; align-items:flex-end; }
  .cap { color:var(--dim); font-size:11px; text-align:center; margin-top:3px; }
  .stage { position:relative; overflow:hidden; }
  .stage img {
    position:absolute; inset:0; width:100%; height:100%;
    image-rendering:pixelated; display:none;
  }
  .stage img.show { display:block; }
  .guide { position:absolute; left:0; right:0; pointer-events:none; }
  /* red reads against both the dark panel and the sand swatch */
  .guide.foot { border-top:1px dashed rgba(255,72,72,.75); }
  .guide.mid { position:absolute; top:0; bottom:0; border-left:1px dashed rgba(255,72,72,.35); }
  section { margin-bottom:26px; }
  h2 { font-size:12px; color:var(--dim); font-weight:600; letter-spacing:.08em;
       text-transform:uppercase; margin:0 0 8px; }
  .meta { color:var(--dim); font-size:11px; margin-left:auto; }
  .sand { background:#c2a878 !important; }
  .checker {
    background-image:linear-gradient(45deg,#2a2620 25%,transparent 25%),
      linear-gradient(-45deg,#2a2620 25%,transparent 25%),
      linear-gradient(45deg,transparent 75%,#2a2620 75%),
      linear-gradient(-45deg,transparent 75%,#2a2620 75%) !important;
    background-size:12px 12px !important;
    background-position:0 0,0 6px,6px -6px,-6px 0 !important;
  }
</style>
</head>
<body>
<header>
  <h1>__TITLE__</h1>
  <label>view
    <select id="view">
      <option value="spin">rotating states (turntable)</option>
      <option value="spinanim">rotating animations (turntable)</option>
      <option value="set">one set, all 8 facings</option>
      <option value="all">all sets, one facing</option>
      <option value="rot">static rotations</option>
    </select>
  </label>
  <label id="setwrap">set <select id="set"></select></label>
  <label id="dirwrap" hidden>facing <select id="dir"></select></label>
  <label>zoom <input type="range" id="zoom" min="2" max="10" step="1" value="5"><span id="zoomv">5x</span></label>
  <label>speed <input type="range" id="speed" min="10" max="200" step="5" value="100"><span id="speedv">100%</span></label>
  <button id="play" class="on">pause</button>
  <button id="step">step</button>
  <button id="guides">guides</button>
  <button id="bg">bg</button>
  <span class="meta" id="meta"></span>
</header>
<main id="out"></main>
<script>
const ROT = __ROT__;
const ANIM = __ANIM__;
const ORDER = __ORDER__;
const LAYOUT = __LAYOUT__;
const USPEC = __USPEC__;   // {name, canvas, dscale, footfrac} for the unit shown
const CMP = __CMP__;       // null, or the same shape + {rot, anim} for the OLD unit

const $ = id => document.getElementById(id);
const SPIN_FPS = 4;      // slow enough to read each facing as it comes round
let zoom = 5, playing = true, speed = 1, showGuides = false, bgMode = 0;
let cells = [];           // {imgs, frames, fps, loop, t, i}
let last = performance.now();

const setSel = $('set'), dirSel = $('dir'), viewSel = $('view');
if (CMP) {
  // the judge gate: old art at its density beside new art at its density
  viewSel.add(new Option('compare old vs new', 'compare'), 0);
  viewSel.value = 'compare';
}
Object.keys(ANIM).forEach(n => setSel.add(new Option(n, n)));
ORDER.forEach(d => dirSel.add(new Option(d, d)));
dirSel.value = 'south';

// ?view=rot&set=standing_idle_walk&facing=north&zoom=6&guides=1&bg=1&paused=1
const q = new URLSearchParams(location.search);
if (q.has('view')) viewSel.value = q.get('view');
if (q.has('set') && ANIM[q.get('set')]) setSel.value = q.get('set');
if (q.has('facing')) dirSel.value = q.get('facing');
if (q.has('zoom')) { zoom = +q.get('zoom'); $('zoom').value = zoom; $('zoomv').textContent = zoom + 'x'; }
if (q.get('guides') === '1') { showGuides = true; $('guides').classList.add('on'); }
if (q.has('bg')) { bgMode = +q.get('bg') % 3; $('bg').classList.toggle('on', bgMode !== 0); }
if (q.get('paused') === '1') { playing = false; $('play').classList.remove('on'); $('play').textContent = 'play'; }

// density-aware cell size: canvas texels x the unit's display scale, so a
// legacy 60@2x and a hi-res 120@1x occupy identical pixels at the same zoom.
// zoom 5 keeps its historical meaning: 5x texel size on a legacy sheet.
function cellPx(spec) { return Math.round(spec.canvas * spec.dscale * zoom / 2); }

function stage(px) {
  const d = document.createElement('div');
  d.className = 'stage';
  d.style.width = d.style.height = px + 'px';
  return d;
}

function addGuides(st, px, spec) {
  if (!showGuides) return;
  const foot = document.createElement('div');   // ground line: where the feet must land
  foot.className = 'guide foot';
  foot.style.top = (spec.footfrac * px) + 'px';
  const mid = document.createElement('div');
  mid.className = 'guide mid';
  mid.style.left = (px / 2) + 'px';
  st.append(foot, mid);
}

function bgClass(el) {
  el.classList.remove('sand', 'checker');
  if (bgMode === 1) el.classList.add('sand');
  if (bgMode === 2) el.classList.add('checker');
}

// `labels`, when given, names each frame (the facing, for a turntable) and the
// caption tracks it live so a paused spin still says which angle you are on
function makeCell(label, frames, fps, loop, labels, spec, cls) {
  spec = spec || USPEC;
  const px = cellPx(spec);
  const wrap = document.createElement('div');
  wrap.className = 'cell' + (cls ? ' ' + cls : '');
  const st = stage(px);
  bgClass(st);
  const imgs = frames.map((src, i) => {
    const im = document.createElement('img');
    im.src = src; im.alt = label + ' ' + i;
    if (i === 0) im.className = 'show';
    return im;
  });
  st.append(...imgs);
  addGuides(st, px, spec);
  const cap = document.createElement('div');
  cap.className = 'cap';
  cap.textContent = labels ? label + ' - ' + labels[0] : label;
  wrap.append(st, cap);
  cells.push({ imgs, n: frames.length, fps, loop, t: 0, i: 0, hold: 0,
               cap, base: label, labels: labels || null });
  return wrap;
}

function renderCompare(out) {
  // states: old & new turning side by side, then the statics per facing
  for (const name of Object.keys(ROT)) {
    const sec = document.createElement('section');
    const h = document.createElement('h2');
    h.textContent = name + ' - old ' + CMP.canvas + 'px @' + CMP.dscale +
      'x vs new ' + USPEC.canvas + 'px @' + USPEC.dscale + 'x';
    const row = document.createElement('div');
    row.className = 'row';
    const oldF = CMP.rot[name] || {};
    const newF = ROT[name] || {};
    const seq = ORDER.filter(d => newF[d] || oldF[d]);
    const oseq = seq.filter(d => oldF[d]), nseq = seq.filter(d => newF[d]);
    if (oseq.length) row.append(makeCell('old', oseq.map(d => oldF[d]), SPIN_FPS, true, oseq, CMP, 'old'));
    if (nseq.length) row.append(makeCell('new', nseq.map(d => newF[d]), SPIN_FPS, true, nseq, USPEC));
    for (const d of seq) {
      const pair = document.createElement('div');
      pair.className = 'pair';
      if (oldF[d]) pair.append(makeCell(d + ' old', [oldF[d]], 1, true, null, CMP, 'old'));
      if (newF[d]) pair.append(makeCell(d + ' new', [newF[d]], 1, true, null, USPEC));
      row.append(pair);
    }
    sec.append(h, row);
    out.append(sec);
  }
  // animations: each set played through all facings, old beside new, in sync
  for (const name of Object.keys(ANIM)) {
    const a = ANIM[name], o = CMP.anim[name];
    const sec = document.createElement('section');
    const h = document.createElement('h2');
    h.textContent = name + ' - ' + a.fps + ' fps - old vs new, all facings';
    const row = document.createElement('div');
    row.className = 'row';
    const build = (src, spec, cls, cap) => {
      const seq = ORDER.filter(d => src.dirs[d]);
      const frames = [], labels = [];
      seq.forEach(d => src.dirs[d].forEach((f, i) => {
        frames.push(f); labels.push(d + ' f' + i);
      }));
      if (frames.length) row.append(makeCell(cap, frames, a.fps, true, labels, spec, cls));
    };
    if (o) build(o, CMP, 'old', 'old');
    build(a, USPEC, null, 'new');
    sec.append(h, row);
    out.append(sec);
  }
  $('meta').textContent = 'compare: ' + CMP.name + ' (old) vs ' + USPEC.name + ' (new)';
}

function render() {
  cells = [];
  const out = $('out');
  out.innerHTML = '';
  const view = viewSel.value;
  $('setwrap').hidden = view !== 'set';
  $('dirwrap').hidden = view !== 'all';

  if (view === 'compare' && CMP) {
    renderCompare(out);
  } else if (view === 'spin') {
    // each state turns through its 8 facings in place: the view that exposes
    // identity drift, a weapon jumping sides, or a palette shift between angles
    const sec = document.createElement('section');
    const h = document.createElement('h2');
    h.textContent = 'states turning through all 8 facings - ' + SPIN_FPS + ' fps';
    const row = document.createElement('div');
    row.className = 'row';
    for (const [name, frames] of Object.entries(ROT)) {
      const seq = ORDER.filter(d => frames[d]);
      if (seq.length) row.append(makeCell(name, seq.map(d => frames[d]), SPIN_FPS, true, seq));
    }
    sec.append(h, row);
    out.append(sec);
    $('meta').textContent = Object.keys(ROT).length + ' states turning';
  } else if (view === 'spinanim') {
    // play a set right through, then step to the next facing and play again
    const sec = document.createElement('section');
    const h = document.createElement('h2');
    h.textContent = 'each animation played once per facing, cycling through all 8';
    const row = document.createElement('div');
    row.className = 'row';
    for (const [name, a] of Object.entries(ANIM)) {
      const seq = ORDER.filter(d => a.dirs[d]);
      const frames = [], labels = [];
      seq.forEach(d => a.dirs[d].forEach((f, i) => {
        frames.push(f); labels.push(d + ' f' + i);
      }));
      if (frames.length) row.append(makeCell(name, frames, a.fps, true, labels));
    }
    sec.append(h, row);
    out.append(sec);
    $('meta').textContent = Object.keys(ANIM).length + ' sets x 8 facings';
  } else if (view === 'set') {
    const name = setSel.value, a = ANIM[name];
    const sec = document.createElement('section');
    const h = document.createElement('h2');
    h.textContent = name + ' - ' + a.fps + ' fps - ' + (a.loop ? 'loop' : 'one-shot');
    const g = document.createElement('div');
    g.className = 'grid';
    LAYOUT.forEach(d => {
      if (d === null) {
        const spacer = document.createElement('div');
        spacer.className = 'cell center';
        g.append(spacer);
        return;
      }
      const f = a.dirs[d];
      g.append(f ? makeCell(d, f, a.fps, a.loop) : document.createElement('div'));
    });
    sec.append(h, g);
    out.append(sec);
    $('meta').textContent = Object.keys(a.dirs).length + ' facings x ' +
      (a.dirs[ORDER[0]] || []).length + ' frames';
  } else if (view === 'all') {
    const d = dirSel.value;
    for (const [name, a] of Object.entries(ANIM)) {
      if (!a.dirs[d]) continue;
      const sec = document.createElement('section');
      const h = document.createElement('h2');
      h.textContent = name + ' - ' + a.fps + ' fps - ' + (a.loop ? 'loop' : 'one-shot');
      const row = document.createElement('div');
      row.className = 'row';
      row.append(makeCell(d, a.dirs[d], a.fps, a.loop));
      // also lay the frames out flat so a one-shot can be read end to end
      a.dirs[d].forEach((src, i) => {
        row.append(makeCell('f' + i, [src], 1, true));
      });
      sec.append(h, row);
      out.append(sec);
    }
    $('meta').textContent = Object.keys(ANIM).length + ' sets';
  } else {
    for (const [name, frames] of Object.entries(ROT)) {
      const sec = document.createElement('section');
      const h = document.createElement('h2');
      h.textContent = name + ' / rotations';
      const row = document.createElement('div');
      row.className = 'row';
      ORDER.forEach(d => { if (frames[d]) row.append(makeCell(d, [frames[d]], 1, true)); });
      sec.append(h, row);
      out.append(sec);
    }
    $('meta').textContent = Object.keys(ROT).length + ' rotation sets';
  }
}

function tick(now) {
  const dt = (now - last) / 1000;
  last = now;
  if (playing) {
    for (const c of cells) {
      if (c.n < 2) continue;
      c.t += dt * c.fps * speed;
      if (c.t >= 1) {
        const adv = Math.floor(c.t);
        c.t -= adv;
        let next = c.i + adv;
        if (!c.loop && next >= c.n - 1) {
          // hold the final pose briefly so the ending is readable, then replay
          next = c.n - 1;
          c.hold += dt + adv / (c.fps * speed);
          if (c.hold > 0.6) { next = 0; c.hold = 0; }
        } else {
          next %= c.n;
        }
        if (next !== c.i) {
          c.imgs[c.i].classList.remove('show');
          c.imgs[next].classList.add('show');
          c.i = next;
          if (c.labels) c.cap.textContent = c.base + ' - ' + c.labels[next];
        }
      }
    }
  }
  requestAnimationFrame(tick);
}

$('zoom').oninput = e => { zoom = +e.target.value; $('zoomv').textContent = zoom + 'x'; render(); };
$('speed').oninput = e => { speed = +e.target.value / 100; $('speedv').textContent = e.target.value + '%'; };
$('play').onclick = e => { playing = !playing; e.target.classList.toggle('on', playing); e.target.textContent = playing ? 'pause' : 'play'; };
$('step').onclick = () => {
  playing = false; $('play').classList.remove('on'); $('play').textContent = 'play';
  for (const c of cells) {
    if (c.n < 2) continue;
    c.imgs[c.i].classList.remove('show');
    c.i = (c.i + 1) % c.n;
    c.imgs[c.i].classList.add('show');
    if (c.labels) c.cap.textContent = c.base + ' - ' + c.labels[c.i];
  }
};
$('guides').onclick = e => { showGuides = !showGuides; e.target.classList.toggle('on', showGuides); render(); };
$('bg').onclick = e => { bgMode = (bgMode + 1) % 3; e.target.classList.toggle('on', bgMode !== 0); render(); };
viewSel.onchange = setSel.onchange = dirSel.onchange = render;

render();
requestAnimationFrame(tick);
</script>
</body>
</html>
"""


def build_viewer(unit: Path, out: Path | None = None, compare: Path | None = None) -> Path:
    """Write the viewer for `unit`. Defaults to <unit>/preview.html, so the
    preview lives beside the art it describes and travels with it in the repo.
    With `compare`, the old unit is scanned too and the page opens on the
    side-by-side judge view (default output moves to tools/ in that case)."""
    if out is None:
        out = (Path(__file__).parent / f"charviewer_compare_{unit.name}.html"
               if compare else unit / "preview.html")
    out.parent.mkdir(parents=True, exist_ok=True)

    rotations, anims = scan(unit, out.parent)
    if not anims and not rotations:
        raise SystemExit(f"found no rotations or animations under {unit}")
    uspec = unit_spec(unit)

    cmp_json = "null"
    title = unit.name
    if compare:
        old_rot, old_anim = scan(compare, out.parent)
        if not old_anim and not old_rot:
            raise SystemExit(f"found no rotations or animations under {compare}")
        cspec = unit_spec(compare)
        cspec["rot"], cspec["anim"] = old_rot, old_anim
        cmp_json = json.dumps(cspec)
        title = f"{compare.name} (old) vs {unit.name} (new)"

    html = (HTML
            .replace("__TITLE__", title)
            .replace("__ROT__", json.dumps(rotations))
            .replace("__ANIM__", json.dumps(anims))
            .replace("__ORDER__", json.dumps(ORDER))
            .replace("__LAYOUT__", json.dumps(DIRS))
            .replace("__USPEC__", json.dumps(uspec))
            .replace("__CMP__", cmp_json))
    out.write_text(html, encoding="utf-8")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("unit", type=Path)
    ap.add_argument("-o", "--out", type=Path, default=None)
    ap.add_argument("--compare", type=Path, default=None, metavar="OLD_UNIT_ROOT",
                    help="also scan an old version of the unit and open on the "
                         "old-vs-new judge view (old at its scale, new at its)")
    a = ap.parse_args()
    if not a.unit.is_dir():
        sys.exit(f"not a directory: {a.unit}")
    if a.compare and not a.compare.is_dir():
        sys.exit(f"not a directory: {a.compare}")
    out = build_viewer(a.unit, a.out, a.compare)
    rotations, anims = scan(a.unit, out.parent)
    spec = unit_spec(a.unit)
    n = sum(len(f) for a_ in anims.values() for f in a_["dirs"].values())
    print(f"wrote {out}")
    print(f"  {a.unit.name}: canvas {spec['canvas']}px, display {spec['dscale']}x")
    if a.compare:
        c = unit_spec(a.compare)
        print(f"  vs {a.compare.name}: canvas {c['canvas']}px, display {c['dscale']}x")
    print(f"  {len(rotations)} rotation sets, {len(anims)} animation sets, {n} frames")
    for name, a_ in anims.items():
        print(f"    {name:32} {len(a_['dirs'])} facings @ {a_['fps']}fps "
              f"{'loop' if a_['loop'] else 'one-shot'}")


if __name__ == "__main__":
    main()
