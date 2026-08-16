#!/usr/bin/env python3
"""Build a preview pane for a batch of generated 8-direction rotations.

    python tools/make_batch_preview.py artgen/staging/kestrels-2026-08-16-r2

Writes <batch>/preview.html. Open it straight from disk.

Images are referenced by RELATIVE PATH rather than embedded, deliberately: a
re-roll that overwrites <unit>/rotations/*.png shows up on refresh without
rebuilding the page. Same reasoning as tools/make_char_viewer.py.

What the pane is for is judging a batch against the art it has to stand next
to, so it carries the things that decide that:

  * every unit's eight facings at a zoom you choose, nearest-neighbour
  * the shipped anchor pinned beside each row on demand, same zoom
  * the floor tones the game actually draws on, sampled from the tile sheets,
    because a sprite judged on a checkerboard is judged against nothing
  * the feet band drawn over each sprite - the 12-16px below canvas centre
    that Unit.SPRITE_SPECS anchors off, which is the single measurement most
    likely to be wrong and least likely to be noticed
  * the measurements from tools/measure_rotations.py, per unit

A folder whose name starts with "_" is the anchor: shown, never graded.
"""
from __future__ import annotations

import html
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from measure_rotations import (  # noqa: E402
    FEET_MAX, FEET_MIN, ORDER, SPEC_H, measure, verdict)

# Mean tone of each shipped floor sheet, sampled off assets/Tiles/Environments.
# A unit that reads on the dark UI and vanishes on salt has not been checked.
GROUNDS = [
    ("desert", "#a58e71"), ("salt", "#9c998e"), ("ash", "#6b6564"),
    ("night", "#161310"), ("checker", "checker"),
]
LABEL = {"east": "E", "south-east": "SE", "south": "S", "south-west": "SW",
         "west": "W", "north-west": "NW", "north": "N", "north-east": "NE"}


def canvas_of(folder: Path) -> int:
    import struct
    f = folder / "rotations" / "south.png"
    b = f.read_bytes()
    return int.from_bytes(b[20:24], "big")


def unit_block(unit: Path, anchor: Path | None) -> str:
    m = measure(unit)
    is_anchor = unit.name.startswith("_")
    fails, warns = ([], []) if is_anchor else verdict(m)
    state = ("anchor" if is_anchor
             else ("flag" if fails else ("warn" if warns else "pass")))
    canvas = canvas_of(unit)

    cells = []
    for d in ORDER:
        rel = "%s/rotations/%s.png" % (unit.name, d)
        pair = ""
        if anchor is not None and not is_anchor:
            pair = ('<img class="ghost" src="%s/rotations/%s.png" alt="">'
                    % (anchor.name, d))
        cells.append(
            '<figure class="cell"><div class="stage">'
            '%s<img class="sprite" src="%s" alt="%s facing %s">'
            '<div class="feet"></div><div class="mid"></div>'
            '</div><figcaption>%s</figcaption></figure>'
            % (pair, rel, html.escape(unit.name), d, LABEL[d]))

    chips = [
        '<li><b>%d&ndash;%d</b> figure h <i>(spec %d)</i></li>'
        % (m["h"][0], m["h"][1], SPEC_H),
        '<li><b>%d&ndash;%d</b> feet <i>(spec %d&ndash;%d)</i></li>'
        % (m["feet"][0], m["feet"][1], FEET_MIN, FEET_MAX),
        '<li><b>%d</b> colours</li>' % m["colours"],
        '<li>%s alpha</li>' % ("binary" if not m["soft"] else "%d soft" % m["soft"]),
        '<li><b>%d&times;%d</b> canvas</li>' % (canvas, canvas),
    ]
    tag = ("anchor" if is_anchor
           else ("on spec" if not (fails or warns) else "; ".join(fails + warns)))
    title = unit.name.lstrip("_").replace("_", " ")
    return (
        '<article class="unit %s" data-canvas="%d">'
        '<header><h2>%s <span class="pill %s">%s</span></h2>'
        '<ul class="chips">%s</ul></header>'
        '<div class="row">%s</div></article>'
        % (state, canvas, html.escape(title), state, html.escape(tag),
           "".join(chips), "".join(cells)))


CSS = """
:root{
  --ground:#100e0c; --panel:#1a1714; --edge:#2c2721; --ink:#ece5d6;
  --muted:#948a79; --olive:#8aa25c; --dust:#c9a44c; --slate:#5c6f74;
  --zoom:3; --canvas:60px;
}
@media (prefers-color-scheme: light){
  :root{ --ground:#f6f2e9; --panel:#fffdf8; --edge:#ded6c6; --ink:#211d18;
         --muted:#6d6455; --olive:#5f7539; --dust:#94700f; --slate:#41565c; }
}
:root[data-theme="dark"]{ --ground:#100e0c; --panel:#1a1714; --edge:#2c2721;
  --ink:#ece5d6; --muted:#948a79; --olive:#8aa25c; --dust:#c9a44c; --slate:#5c6f74; }
:root[data-theme="light"]{ --ground:#f6f2e9; --panel:#fffdf8; --edge:#ded6c6;
  --ink:#211d18; --muted:#6d6455; --olive:#5f7539; --dust:#94700f; --slate:#41565c; }

*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);
  font:15px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;
  padding:0 0 5rem}
.wrap{max-width:1500px;margin:0 auto;padding:0 clamp(.75rem,2.5vw,2rem)}

header.top{padding:clamp(1.25rem,3vw,2.25rem) 0 1rem}
.eyebrow{font:600 10.5px/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  letter-spacing:.22em;text-transform:uppercase;color:var(--muted);margin:0 0 .6rem}
h1{font-size:clamp(1.35rem,2.6vw,1.8rem);margin:0 0 .4rem;letter-spacing:-.015em;
  font-weight:650;text-wrap:balance}
.sub{margin:0;color:var(--muted);max-width:70ch;font-size:.95rem}

.bar{position:sticky;top:0;z-index:5;background:var(--ground);
  border-bottom:1px solid var(--edge);padding:.7rem 0;margin-bottom:1.25rem;
  display:flex;flex-wrap:wrap;gap:1.25rem;align-items:center}
.grp{display:flex;align-items:center;gap:.45rem}
.grp>span{font:600 10px/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  letter-spacing:.16em;text-transform:uppercase;color:var(--muted)}
button{font:inherit;font-size:.82rem;color:var(--ink);background:var(--panel);
  border:1px solid var(--edge);border-radius:3px;padding:.3rem .62rem;
  cursor:pointer;line-height:1.3}
button:hover{border-color:var(--muted)}
button[aria-pressed="true"]{border-color:var(--olive);color:var(--olive)}
button:focus-visible{outline:2px solid var(--dust);outline-offset:2px}
.sw{width:26px;height:26px;padding:0;border-radius:3px}

.unit{border:1px solid var(--edge);border-left:3px solid var(--edge);
  border-radius:4px;background:var(--panel);padding:.9rem 1rem 1.1rem;
  margin:0 0 .9rem}
.unit.pass{border-left-color:var(--olive)}
.unit.flag{border-left-color:var(--dust)}
.unit.warn{border-left-color:var(--slate)}
.pill.warn{color:var(--slate);border-color:var(--slate)}
.unit.anchor{border-left-color:var(--slate)}
.unit h2{margin:0;font-size:1rem;font-weight:650;display:flex;
  align-items:center;gap:.55rem;flex-wrap:wrap}
.pill{padding:.14rem .45rem;border-radius:2px;border:1px solid;
  font:600 10.5px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
.pill.pass{color:var(--olive);border-color:var(--olive)}
.pill.flag{color:var(--dust);border-color:var(--dust)}
.pill.anchor{color:var(--slate);border-color:var(--slate)}
.chips{list-style:none;display:flex;flex-wrap:wrap;gap:.35rem .45rem;
  margin:.55rem 0 .85rem;padding:0}
.chips li{font:11px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  color:var(--muted);border:1px solid var(--edge);border-radius:2px;
  padding:.14rem .45rem}
.chips b{color:var(--ink)} .chips i{font-style:normal;opacity:.65}

.row{display:flex;flex-wrap:wrap;gap:.4rem;overflow-x:auto}
.cell{margin:0;display:flex;flex-direction:column;align-items:center;gap:.25rem}
.stage{position:relative;
  width:calc(var(--canvas) * var(--zoom));
  height:calc(var(--canvas) * var(--zoom));
  border-radius:3px;overflow:hidden;background:var(--stage-bg,#161310)}
body.checker .stage{background:
  linear-gradient(45deg,rgba(128,128,128,.13) 25%,transparent 25%,
    transparent 75%,rgba(128,128,128,.13) 75%) 0 0/16px 16px,
  linear-gradient(45deg,rgba(128,128,128,.13) 25%,transparent 25%,
    transparent 75%,rgba(128,128,128,.13) 75%) 8px 8px/16px 16px}
.stage img{position:absolute;inset:0;width:100%;height:100%;
  image-rendering:pixelated}
.ghost{opacity:0;transition:opacity .12s}
body.compare .ghost{opacity:.34}
.feet,.mid{position:absolute;left:0;right:0;display:none;pointer-events:none}
body.guides .feet,body.guides .mid{display:block}
.mid{top:50%;border-top:1px dashed rgba(200,190,170,.45)}
.feet{top:calc(50% + (12 / var(--canvas-n)) * 100%);
  height:calc((4 / var(--canvas-n)) * 100%);
  background:rgba(138,162,92,.20);
  border-top:1px solid rgba(138,162,92,.7);
  border-bottom:1px solid rgba(138,162,92,.7)}
figcaption{font:10px/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  letter-spacing:.08em;color:var(--muted)}

footer{margin-top:1.5rem;padding-top:1rem;border-top:1px solid var(--edge);
  color:var(--muted);font-size:.86rem;max-width:76ch}
footer code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  color:var(--ink);font-size:.88em}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
"""

JS = """
const root = document.documentElement, body = document.body;
function press(group, val){
  document.querySelectorAll('[data-'+group+']').forEach(b =>
    b.setAttribute('aria-pressed', String(b.dataset[group] === val)));
}
document.querySelectorAll('[data-zoom]').forEach(b => b.onclick = () => {
  root.style.setProperty('--zoom', b.dataset.zoom); press('zoom', b.dataset.zoom);
});
document.querySelectorAll('[data-bg]').forEach(b => b.onclick = () => {
  const v = b.dataset.bg;
  body.classList.toggle('checker', v === 'checker');
  root.style.setProperty('--stage-bg', v === 'checker' ? 'transparent' : v);
  press('bg', v);
});
document.querySelectorAll('[data-toggle]').forEach(b => b.onclick = () => {
  const on = body.classList.toggle(b.dataset.toggle);
  b.setAttribute('aria-pressed', String(on));
});
// Each unit's guides are a percentage of ITS canvas, so a batch that mixes
// 60px and 120px sets still draws the band in the right place.
document.querySelectorAll('.unit').forEach(u =>
  u.style.setProperty('--canvas-n', u.dataset.canvas));
document.querySelectorAll('.unit').forEach(u => {
  const c = u.dataset.canvas + 'px';
  u.querySelectorAll('.stage').forEach(s => s.style.setProperty('--canvas', c));
});
"""


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    batch = Path(sys.argv[1])
    units = sorted(p for p in batch.iterdir()
                   if p.is_dir() and (p / "rotations").is_dir())
    if not units:
        sys.exit("no <unit>/rotations/ under %s" % batch)
    anchor = next((u for u in units if u.name.startswith("_")), None)
    # Anchor last: it is the thing being compared against, not the subject.
    ordered = [u for u in units if u is not anchor] + ([anchor] if anchor else [])

    zoom_btns = "".join(
        '<button data-zoom="%d" aria-pressed="%s">%d&times;</button>'
        % (z, "true" if z == 3 else "false", z) for z in (1, 2, 3, 4, 6))
    bg_btns = "".join(
        '<button class="sw" data-bg="%s" aria-pressed="%s" title="%s" '
        'style="background:%s"></button>'
        % (v, "true" if n == "night" else "false", n,
           ("repeating-conic-gradient(#8886 0 25%, transparent 0 50%) 0 0/12px 12px"
            if v == "checker" else v))
        for n, v in GROUNDS)

    page = (
        '<title>%s &mdash; sprite preview</title>\n'
        '<style>%s</style>\n'
        '<div class="wrap">\n'
        '<header class="top"><p class="eyebrow">Sandline &middot; staged, not imported</p>'
        '<h1>%s</h1>'
        '<p class="sub">Every facing at the zoom you pick, nearest-neighbour. '
        'The grounds are the mean tones of the shipped floor sheets, so a unit '
        'is judged against what it will actually stand on. <b>Compare</b> '
        'ghosts the shipped rifleman under each sprite at the same zoom; '
        '<b>Guides</b> draws canvas centre and the 12&ndash;16px feet band that '
        '<code>SPRITE_SPECS</code> anchors off.</p></header>\n'
        '<div class="bar">'
        '<div class="grp"><span>Zoom</span>%s</div>'
        '<div class="grp"><span>Ground</span>%s</div>'
        '<div class="grp"><span>Overlay</span>'
        '<button data-toggle="compare" aria-pressed="false">Compare</button>'
        '<button data-toggle="guides" aria-pressed="false">Guides</button>'
        '</div></div>\n'
        '%s\n'
        '<footer>Images are referenced by relative path &mdash; re-roll a unit '
        'into <code>&lt;unit&gt;/rotations/</code> and refresh. Numbers come '
        'from <code>tools/measure_rotations.py</code>; the anchor row is '
        'measured but never graded. Standing rotations only &mdash; a shippable '
        'unit also needs ready-to-fire and dead rotations plus eight animation '
        'sets.</footer>\n'
        '</div>\n<script>%s</script>\n'
        % (html.escape(batch.name), CSS, html.escape(batch.name),
           zoom_btns, bg_btns,
           "\n".join(unit_block(u, anchor) for u in ordered), JS))

    out = batch / "preview.html"
    out.write_text(page, encoding="utf-8")
    print("wrote %s (%d units)" % (out, len(units)))


if __name__ == "__main__":
    main()
