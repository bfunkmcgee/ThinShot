#!/usr/bin/env python3
"""Manifest-driven bookkeeping for PixelLab generation batches.

Claude makes the MCP calls; this tool owns the file state, so a batch is
resumable from disk alone after any crash or MCP disconnect. All state lives
in <batch>/manifest.json, written atomically (tmp + rename).

    python tools/pixellab_batch.py init --batch artgen/staging/desert-01 \
        --kind biome --biome desert --balance 6798
    python tools/pixellab_batch.py add-job --batch <dir> --job-id abc123 \
        --tool create_tiles_pro --targets "slots 0-9" --params params.json --cost 10
    python tools/pixellab_batch.py set-status --batch <dir> --job-id abc123 \
        --status completed --url tile_0=https://... --url tile_1=https://...
    python tools/pixellab_batch.py download --batch <dir>
    python tools/pixellab_batch.py status --batch <dir>
    python tools/pixellab_batch.py review --batch <dir> --job-id abc123 \
        --slot 3 --verdict regen --reason "rim survives on SE edge"
    python tools/pixellab_batch.py set-validation --batch <dir> --pass
    python tools/pixellab_batch.py promote --batch <dir> \
        --to assets/Tiles/Environments/Desert --as-reference artgen/reference/desert
    python tools/pixellab_batch.py close --batch <dir> --balance 6770

Unit batches (`--kind unit`, the hi-res regeneration program) stage one
subtree per unit - artgen/staging/units-hires-<date>/<UnitName>/ with its own
raw/ post/ preview/ - and the manifest carries the PixelLab provenance per
unit: character ids per state, animation group ids, and which job made which
state. Promote copies each unit's post/ tree onto assets/sprites/<UnitName>/,
archiving every file it overwrites into the batch's backup_originals/ first:

    python tools/pixellab_batch.py init --batch artgen/staging/units-hires-2026-08-20 \
        --kind unit --units Rodar_Akai,Scout --balance 5796
    python tools/pixellab_batch.py set-unit --batch <dir> --unit Rodar_Akai \
        --group-id <uuid> --character main=<char_uuid> --character dead=<char_uuid> \
        --anim-group standing_idle=<uuid>
    python tools/pixellab_batch.py add-job --batch <dir> --job-id abc123 \
        --unit Rodar_Akai --state main --tool create_character \
        --targets "main rotations" --params params.json
    python tools/pixellab_batch.py promote --batch <dir> --unit Rodar_Akai

The download stage uses plain urllib (per-tile storage URLs need no auth).
Map objects expire 8h after generation - download on completion, always.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

MANIFEST = "manifest.json"
SUBDIRS = ["raw", "post", "preview"]
KINDS = ["biome", "transitions", "paths", "props", "unit"]
UNIT_PROMOTE_ROOT = Path("assets/sprites")
STATUSES = ["processing", "completed", "failed"]
VERDICTS = ["accept", "regen"]
DOWNLOAD_TIMEOUT = 60          # seconds per URL
DOWNLOAD_RETRIES = 1           # extra attempts after the first failure
# the tile storage 403s urllib's default Python-urllib/3.x agent
DOWNLOAD_UA = "Mozilla/5.0 (Sandline pixellab_batch)"


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def die(msg: str, code: int = 1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def sha1_file(p: Path) -> str:
    h = hashlib.sha1()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def find_artgen(batch: Path) -> Path | None:
    """The artgen root, from the batch path (…/artgen/staging/<batch>) or cwd."""
    for parent in [batch, *batch.resolve().parents]:
        if parent.name == "artgen" and (parent / "STYLE.md").exists():
            return parent
    local = Path("artgen")
    if (local / "STYLE.md").exists():
        return local
    return None


def style_hash(batch: Path) -> str:
    """sha1 over STYLE.md + style.json - pins which style a batch was made under."""
    artgen = find_artgen(batch)
    if artgen is None:
        return "unknown"
    h = hashlib.sha1()
    for name in ["STYLE.md", "style.json"]:
        f = artgen / name
        if f.exists():
            h.update(f.read_bytes())
    return h.hexdigest()


def load(batch: Path) -> dict:
    mf = batch / MANIFEST
    if not mf.exists():
        die(f"no {MANIFEST} in {batch} - run init first")
    return json.loads(mf.read_text(encoding="utf-8"))


def save(batch: Path, m: dict):
    """Atomic write: the manifest must never be half a file."""
    mf = batch / MANIFEST
    tmp = mf.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(m, indent=2), encoding="utf-8")
    os.replace(tmp, mf)


def job_by_id(m: dict, job_id: str) -> dict:
    for j in m["jobs"]:
        if j["job_id"] == job_id:
            return j
    die(f"no job {job_id} in manifest (jobs: {[j['job_id'] for j in m['jobs']]})")


def pending_jobs(m: dict) -> list[dict]:
    """Jobs still needing action: not yet completed/failed, or completed with
    URLs not yet safely on disk."""
    out = []
    for j in m["jobs"]:
        if j["status"] not in ("completed", "failed"):
            out.append(j)
        elif j["status"] == "completed":
            missing = [n for n in j["urls"] if n not in j["downloaded"]]
            if missing:
                out.append(j)
    return out


# ------------------------------------------------------------------- commands
def _unit_skeleton():
    """Per-unit provenance the hi-res program requires: which PixelLab
    character made which state, which animation groups, which jobs."""
    return {"group_id": None, "characters": {}, "animation_groups": {},
            "state_jobs": {}}


def _add_unit_dirs(batch: Path, name: str):
    for d in SUBDIRS:
        (batch / name / d).mkdir(parents=True, exist_ok=True)


def cmd_init(a):
    batch = Path(a.batch)
    if (batch / MANIFEST).exists():
        die(f"{batch} already has a manifest - refusing to re-init")
    if a.kind != "unit" and a.biome is None:
        die("--biome is required for non-unit kinds")
    units = [u for u in (a.units or "").split(",") if u]
    if a.kind != "unit" and units:
        die("--units only makes sense with --kind unit")
    batch.mkdir(parents=True, exist_ok=True)
    if a.kind == "unit":
        # one staging subtree per unit; the batch root holds only the manifest
        for u in units:
            _add_unit_dirs(batch, u)
    else:
        for d in SUBDIRS:
            (batch / d).mkdir(exist_ok=True)
    m = {
        "batch": batch.name,
        "kind": a.kind,
        "biome": a.biome if a.biome is not None else "-",
        "created": now(),
        "balance_start": a.balance,
        "balance_end": None,
        "style_hash": style_hash(batch),
        "jobs": [],
        "validation": {"pass": None, "report": ""},
        "review": {"slots": {}},
    }
    if a.kind == "unit":
        m["units"] = {u: _unit_skeleton() for u in units}
    save(batch, m)
    print(f"initialized {batch} (kind={a.kind} biome={m['biome']} "
          f"balance_start={a.balance} style_hash={m['style_hash'][:12]})"
          + (f" units={','.join(units)}" if units else ""))


def cmd_add_unit(a):
    batch = Path(a.batch)
    m = load(batch)
    if m["kind"] != "unit":
        die(f"add-unit only applies to --kind unit batches (this is {m['kind']})")
    if a.unit in m.get("units", {}):
        die(f"unit {a.unit} already in manifest")
    m.setdefault("units", {})[a.unit] = _unit_skeleton()
    _add_unit_dirs(batch, a.unit)
    save(batch, m)
    print(f"added unit {a.unit} ({batch / a.unit}/raw|post|preview)")


def _unit_entry(m: dict, name: str) -> dict:
    units = m.get("units", {})
    if name not in units:
        die(f"no unit {name} in manifest (units: {sorted(units)})")
    return units[name]


def cmd_set_unit(a):
    """Record PixelLab provenance for a unit as ids become known."""
    batch = Path(a.batch)
    m = load(batch)
    u = _unit_entry(m, a.unit)
    if a.group_id:
        u["group_id"] = a.group_id
    for kv in a.character or []:
        state, _, cid = kv.partition("=")
        if not cid:
            die(f"bad --character (want state=char_id): {kv}")
        u["characters"][state] = cid
    for kv in a.anim_group or []:
        name, _, gid = kv.partition("=")
        if not gid:
            die(f"bad --anim-group (want name=group_id): {kv}")
        u["animation_groups"][name] = gid
    save(batch, m)
    print(f"unit {a.unit}: group={u['group_id']} "
          f"{len(u['characters'])} character(s), "
          f"{len(u['animation_groups'])} animation group(s)")


def cmd_add_job(a):
    batch = Path(a.batch)
    m = load(batch)
    if any(j["job_id"] == a.job_id for j in m["jobs"]):
        die(f"job {a.job_id} already recorded")
    params = Path(a.params)
    if not params.exists():
        die(f"params file not found: {params} - save the exact request first")
    if a.unit:
        # per-state job bookkeeping for unit batches
        u = _unit_entry(m, a.unit)
        state = a.state or "-"
        u["state_jobs"].setdefault(state, []).append(a.job_id)
    elif a.state:
        die("--state needs --unit")
    m["jobs"].append({
        "job_id": a.job_id,
        "tool": a.tool,
        "targets": a.targets,
        "params_file": str(params),
        "params_sha1": sha1_file(params),
        "cost": a.cost,
        "status": "submitted",
        "submitted": now(),
        "urls": {},
        "downloaded": {},
        "regen_of": a.regen_of,
        "unit": a.unit,
        "state": a.state,
    })
    save(batch, m)
    print(f"recorded job {a.job_id} ({a.tool} -> {a.targets})"
          + (f" [unit {a.unit}/{a.state or '-'}]" if a.unit else ""))


def cmd_set_status(a):
    batch = Path(a.batch)
    m = load(batch)
    j = job_by_id(m, a.job_id)
    j["status"] = a.status
    j[a.status] = now()
    for u in a.url or []:
        name, _, url = u.partition("=")
        if not url.startswith("http"):
            die(f"bad --url (want name=https://...): {u}")
        j["urls"][name] = url
    save(batch, m)
    print(f"job {a.job_id}: {a.status}" +
          (f", {len(j['urls'])} urls recorded" if j["urls"] else ""))


def cmd_download(a):
    batch = Path(a.batch)
    m = load(batch)
    raw = batch / "raw"
    raw.mkdir(exist_ok=True)
    fetched = skipped = failed = 0
    for j in m["jobs"]:
        if j["status"] != "completed":
            continue
        # a unit job's files land in that unit's own raw/, not the batch root's
        j_raw = (batch / j["unit"] / "raw") if j.get("unit") else raw
        for name, url in j["urls"].items():
            dest = j_raw / f"{name}.png"   # names may carry subdirs: base/tile_0
            dest.parent.mkdir(parents=True, exist_ok=True)
            if name in j["downloaded"] and dest.exists():
                skipped += 1
                continue
            ok = False
            for attempt in range(1 + DOWNLOAD_RETRIES):
                try:
                    req = urllib.request.Request(url, headers={"User-Agent": DOWNLOAD_UA})
                    with urllib.request.urlopen(req, timeout=DOWNLOAD_TIMEOUT) as r:
                        data = r.read()
                    dest.write_bytes(data)
                    ok = True
                    break
                except Exception as e:
                    print(f"  {name}: attempt {attempt + 1} failed - {e}")
            if ok:
                j["downloaded"][name] = {"sha1": sha1_file(dest), "ts": now()}
                fetched += 1
                print(f"  {name}.png <- job {j['job_id']} ({dest.stat().st_size // 1024} KB)")
            else:
                failed += 1
        save(batch, m)   # after every job, so a crash loses nothing fetched
    print(f"download: {fetched} fetched, {skipped} already on disk, {failed} failed")
    if failed:
        sys.exit(1)


def cmd_status(a):
    batch = Path(a.batch)
    m = load(batch)
    print(f"batch {m['batch']}  kind={m['kind']} biome={m['biome']} "
          f"created={m['created']}")
    print(f"  balance {m['balance_start']} -> {m['balance_end']}   "
          f"style {m['style_hash'][:12]}")
    for name, u in m.get("units", {}).items():
        jobs = sum(len(v) for v in u["state_jobs"].values())
        print(f"  unit {name}: group={u['group_id'] or '-'} "
              f"{len(u['characters'])} char id(s), "
              f"{len(u['animation_groups'])} anim group(s), {jobs} job(s)")
    v = m["validation"]
    print(f"  validation: {'-' if v['pass'] is None else ('PASS' if v['pass'] else 'FAIL')}")
    slots = m["review"]["slots"]
    if slots:
        acc = sum(1 for s in slots.values() if s["verdict"] == "accept")
        print(f"  review: {acc}/{len(slots)} slots accepted")
    print(f"  {'job_id':<14} {'tool':<24} {'status':<10} {'dl':>5}  targets")
    for j in m["jobs"]:
        dl = f"{len(j['downloaded'])}/{len(j['urls'])}" if j["urls"] else "-"
        regen = f"  (regen of {j['regen_of']})" if j.get("regen_of") else ""
        print(f"  {j['job_id']:<14} {j['tool']:<24} {j['status']:<10} {dl:>5}  "
              f"{j['targets']}{regen}")
    pend = pending_jobs(m)
    if pend:
        print(f"  PENDING: {len(pend)} job(s) not finished/downloaded")
        sys.exit(1)
    print("  nothing pending")


def cmd_review(a):
    batch = Path(a.batch)
    m = load(batch)
    job_by_id(m, a.job_id)   # must exist
    m["review"]["slots"][str(a.slot)] = {
        "verdict": a.verdict,
        "reason": a.reason,
        "job_id": a.job_id,
        "ts": now(),
    }
    save(batch, m)
    print(f"slot {a.slot}: {a.verdict} ({a.reason})")


def cmd_set_validation(a):
    batch = Path(a.batch)
    m = load(batch)
    m["validation"] = {"pass": a.passed, "report": a.report, "ts": now()}
    save(batch, m)
    print(f"validation: {'PASS' if a.passed else 'FAIL'}")


def _archive_manifest(batch: Path, m: dict):
    artgen = find_artgen(batch)
    if artgen is None:
        die("promoted files copied, but no artgen/ root found to archive the manifest")
    archive = artgen / "batches" / f"{m['batch']}.manifest.json"
    save(batch, m)
    shutil.copy2(batch / MANIFEST, archive)
    print(f"  manifest archived -> {archive}")


def _promote_units(a, batch: Path, m: dict):
    """Copy each unit's post/ tree onto assets/sprites/<UnitName>/, archiving
    every file that would be overwritten into the batch's backup_originals/.
    The refusal gates have already run."""
    names = [a.unit] if a.unit else sorted(m.get("units", {}))
    if a.unit:
        _unit_entry(m, a.unit)
    if not names:
        die("no units in manifest")
    dest_root = Path(a.to) if a.to else UNIT_PROMOTE_ROOT
    backup_root = batch / "backup_originals"
    total = archived = 0
    for name in names:
        post = batch / name / "post"
        files = sorted(p for p in post.rglob("*") if p.is_file())
        if not files:
            die(f"nothing to promote in {post}")
        dest_unit = dest_root / name
        for f in files:
            rel = f.relative_to(post)
            dest = dest_unit / rel
            if dest.exists():
                bak = backup_root / name / rel
                bak.parent.mkdir(parents=True, exist_ok=True)
                if not bak.exists():   # first promotion wins: keep the ORIGINAL
                    shutil.copy2(dest, bak)
                    archived += 1
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, dest)
            total += 1
        print(f"  {name}: {len(files)} file(s) -> {dest_unit}")
    print(f"  {total} file(s) promoted, {archived} original(s) archived -> {backup_root}")
    m["promoted"] = {"to": str(dest_root), "units": names, "ts": now()}
    _archive_manifest(batch, m)


def cmd_promote(a):
    batch = Path(a.batch)
    m = load(batch)
    # the two refusals are the whole point of this command
    if m["validation"]["pass"] is not True:
        die("refusing to promote: validation.pass is not true "
            "(run the kind's validator, then set-validation)")
    slots = m["review"]["slots"]
    if not slots:
        die("refusing to promote: no per-slot review verdicts recorded")
    bad = [s for s, v in slots.items() if v["verdict"] != "accept"]
    if bad:
        die(f"refusing to promote: slot(s) {', '.join(sorted(bad))} not accepted")

    if m["kind"] == "unit":
        _promote_units(a, batch, m)
        return

    if not a.to:
        die("--to is required for tile kinds")
    post = batch / "post"
    files = sorted(list(post.glob("*.png")) + list(post.glob("*.tiles.json")))
    if not files:
        die(f"nothing to promote in {post}")
    to = Path(a.to)
    to.mkdir(parents=True, exist_ok=True)
    for f in files:
        shutil.copy2(f, to / f.name)
        print(f"  {f.name} -> {to}")
    if a.as_reference:
        ref = Path(a.as_reference)
        ref.mkdir(parents=True, exist_ok=True)
        raws = sorted((batch / "raw").glob("*.png"))
        for f in raws:
            shutil.copy2(f, ref / f.name)
        print(f"  {len(raws)} raw tile(s) -> {ref} (golden references)")

    artgen = find_artgen(batch)
    if artgen is None:
        die("promoted files copied, but no artgen/ root found to archive the manifest")
    archive = artgen / "batches" / f"{m['batch']}.manifest.json"
    m["promoted"] = {"to": str(to), "ts": now()}
    save(batch, m)
    shutil.copy2(batch / MANIFEST, archive)
    print(f"  manifest archived -> {archive}")


def cmd_close(a):
    batch = Path(a.batch)
    m = load(batch)
    m["balance_end"] = a.balance
    save(batch, m)
    spent = (m["balance_start"] - a.balance) if m["balance_start"] is not None else None
    print(f"closed {m['batch']}: balance {m['balance_start']} -> {a.balance}"
          + (f" ({spent} generations spent)" if spent is not None else ""))
    # keep the archive current if this batch was already promoted
    artgen = find_artgen(batch)
    if artgen and m.get("promoted"):
        shutil.copy2(batch / MANIFEST, artgen / "batches" / f"{m['batch']}.manifest.json")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    def base(p):
        p.add_argument("--batch", required=True, help="batch directory (artgen/staging/<name>)")
        return p

    p = base(sub.add_parser("init", help="create batch skeleton + manifest"))
    p.add_argument("--kind", required=True, choices=KINDS)
    p.add_argument("--biome", default=None,
                   help="required for tile kinds; unit batches default to '-'")
    p.add_argument("--units", default=None,
                   help="comma-separated unit names (--kind unit): creates "
                        "<batch>/<Unit>/raw|post|preview per unit")
    p.add_argument("--balance", type=int, default=None, help="get_balance before spending")
    p.set_defaults(fn=cmd_init)

    p = base(sub.add_parser("add-unit", help="add a unit subtree to a --kind unit batch"))
    p.add_argument("--unit", required=True)
    p.set_defaults(fn=cmd_add_unit)

    p = base(sub.add_parser("set-unit", help="record a unit's PixelLab ids as they become known"))
    p.add_argument("--unit", required=True)
    p.add_argument("--group-id", default=None)
    p.add_argument("--character", action="append", metavar="STATE=CHAR_ID")
    p.add_argument("--anim-group", action="append", metavar="NAME=GROUP_ID")
    p.set_defaults(fn=cmd_set_unit)

    p = base(sub.add_parser("add-job", help="record a submitted job (run the moment an ID exists)"))
    p.add_argument("--job-id", required=True)
    p.add_argument("--tool", required=True)
    p.add_argument("--targets", required=True, help='what it generates, e.g. "slots 0-9"')
    p.add_argument("--params", required=True, help="file holding the exact request params")
    p.add_argument("--cost", type=int, default=None)
    p.add_argument("--regen-of", default=None)
    p.add_argument("--unit", default=None, help="unit this job belongs to (--kind unit)")
    p.add_argument("--state", default=None, help="which state the job generates (with --unit)")
    p.set_defaults(fn=cmd_add_job)

    p = base(sub.add_parser("set-status", help="update a job; --url name=https://... repeatable"))
    p.add_argument("--job-id", required=True)
    p.add_argument("--status", required=True, choices=STATUSES)
    p.add_argument("--url", action="append")
    p.set_defaults(fn=cmd_set_status)

    p = base(sub.add_parser("download", help="fetch every completed job's URLs into raw/"))
    p.set_defaults(fn=cmd_download)

    p = base(sub.add_parser("status", help="job table; exit 0 only when nothing pending"))
    p.set_defaults(fn=cmd_status)

    p = base(sub.add_parser("review", help="record a per-slot verdict"))
    p.add_argument("--job-id", required=True)
    p.add_argument("--slot", required=True,
                   help="tile slot number, or a unit's '<Unit>/<state>' for unit batches")
    p.add_argument("--verdict", required=True, choices=VERDICTS)
    p.add_argument("--reason", required=True)
    p.set_defaults(fn=cmd_review)

    p = base(sub.add_parser("set-validation", help="record the validator gate result"))
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--pass", dest="passed", action="store_true")
    g.add_argument("--fail", dest="passed", action="store_false")
    p.add_argument("--report", default="")
    p.set_defaults(fn=cmd_set_validation)

    p = base(sub.add_parser("promote", help="copy post/ output to assets; refuses without PASS + accepts"))
    p.add_argument("--to", default=None,
                   help="destination root; required for tile kinds, defaults "
                        f"to {UNIT_PROMOTE_ROOT} for unit batches")
    p.add_argument("--unit", default=None,
                   help="promote only this unit (--kind unit; default: all)")
    p.add_argument("--as-reference", default=None,
                   help="also copy accepted raw tiles into this reference dir")
    p.set_defaults(fn=cmd_promote)

    p = base(sub.add_parser("close", help="record the post-batch balance"))
    p.add_argument("--balance", type=int, required=True)
    p.set_defaults(fn=cmd_close)

    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
