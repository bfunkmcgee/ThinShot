#!/usr/bin/env python3
"""Verify every res:// asset path in the scripts matches the disk's own casing.

    python tools/check_res_case.py

This exists because a mis-cased path is invisible on the machine the game is
developed on and fatal in the build that ships. Windows resolves
`Dead_Stance/rotations/east.png` to `Dead_stance/rotations/east.png` at the OS
level, so the editor loads it, the harnesses load it, and every check passes.
Inside an exported PCK the path is a case-sensitive key, and the texture is
simply not there.

Nothing else can catch it. tools/check_unit_art.gd asserts that every kind's
frames actually loaded, and on Windows they DO load through the wrong casing -
it caught the machinegunner's `Standing_ReadyToFire_idle` (a genuinely
different name) and could not have caught its `Dead_Stance` (the same name in
different case). Only a string-versus-directory-listing comparison sees that
one, which is what this does.

It resolves the constants too, so `MG_BASE + "/animations/standing_idle"` is
checked as the full path a player's machine will ask for. The repo has real
mixed-case folders on purpose - `Standing_Ready_to_fire_stance`,
`Solider_aims_his_rif`, `Dead_Stance` - so this cannot be fixed by lowercasing
everything; the names have to be quoted exactly as generated.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"

# Paths the loaders point at deliberately even though nothing is there.
# UNIT_ASSET_SPEC.md §3 makes standing_idle_alt optional, and Unit.gd asks for
# it regardless: _load_dir_frames returns eight empty per-direction arrays for
# an absent set, which is the shape the field must have. Loading nothing is the
# point - the alternative, leaving the field at [], is an out-of-bounds crash
# the first time that unit idles, because the field is indexed by direction.
MISSING_IS_FINE = ("/animations/standing_idle_alt",)

CONST_LITERAL = re.compile(r'^const\s+(\w+)\s*:=\s*"(res://[^"]+)"', re.M)
CONST_JOINED = re.compile(r'^const\s+(\w+)\s*:=\s*(\w+)\s*\+\s*"([^"]+)"', re.M)
# NAME + "/some/path" anywhere, and bare "res://..." literals.
JOINED_USE = re.compile(r'\b(\w+)\s*\+\s*"(/[^"]*)"')
BARE_USE = re.compile(r'"(res://assets/[^"]+)"')


def resolve_consts(text: str) -> dict:
    consts = {n: v for n, v in CONST_LITERAL.findall(text)}
    # A joined const may name another joined const, so iterate to a fixed point.
    for _ in range(8):
        grew = False
        for name, base, tail in CONST_JOINED.findall(text):
            if name in consts or base not in consts:
                continue
            consts[name] = consts[base] + tail
            grew = True
        if not grew:
            break
    return consts


def check_path(res_path: str) -> tuple:
    """(verdict, detail). Compares component by component against the real
    directory listing, so it works on a case-insensitive filesystem.

    "miscased" is the bug this tool is for: the entry is there under a
    different case, so it loads here and vanishes in an export.
    "absent" is a different thing entirely and is NOT a failure by itself -
    the loaders are deliberately pointed at optional sets that do not exist
    (see MISSING_IS_FINE), because asking for an absent path is how a field
    gets the right empty shape.
    """
    rel = res_path[len("res://"):]
    here = ROOT
    for part in rel.split("/"):
        if not part:
            continue
        names = {p.name for p in here.iterdir()} if here.is_dir() else set()
        if part not in names:
            near = [n for n in names if n.lower() == part.lower()]
            where = str(here.relative_to(ROOT)).replace("\\", "/") + "/" + part
            if near:
                return "miscased", "%s -> on disk it is '%s'" % (where, near[0])
            return "absent", where
        here = here / part
    return "ok", None


def main() -> None:
    miscased, absent, checked = [], [], 0
    scripts = sorted(SCRIPTS.rglob("*.gd"))
    for gd in scripts:
        text = gd.read_text(encoding="utf-8", errors="replace")
        consts = resolve_consts(text)
        wanted = set()
        for base, tail in JOINED_USE.findall(text):
            if base in consts:
                wanted.add(consts[base] + tail)
        for lit in BARE_USE.findall(text):
            wanted.add(lit)
        for path in sorted(wanted):
            # Only assets; res://scripts and res://scenes are Godot's own.
            if not path.startswith("res://assets/"):
                continue
            checked += 1
            verdict, where = check_path(path)
            if verdict == "miscased":
                miscased.append("%s\n      %s\n      %s"
                                % (gd.relative_to(ROOT), path, where))
            elif verdict == "absent":
                absent.append((path, any(path.endswith(s) for s in MISSING_IS_FINE)))

    print("checked %d res:// asset path(s) across %d script(s)"
          % (checked, len(scripts)))

    expected = [p for p, ok in absent if ok]
    unexpected = [p for p, ok in absent if not ok]
    if expected:
        print("\n%d path(s) absent on purpose (an optional set: asking for it is"
              " how the field gets the right empty shape):" % len(expected))
        for p in expected:
            print("  %s" % p)
    if unexpected:
        print("\n%d path(s) that do not exist and are not an optional set:"
              % len(unexpected))
        for p in unexpected:
            print("  %s" % p)

    if not miscased and not unexpected:
        print("\nRESULT: PASS (every path matches the disk's own casing)")
        return
    if miscased:
        print("\n%d path(s) that only resolve on a case-insensitive filesystem"
              " - these WILL break in an export:" % len(miscased))
        for p in miscased:
            print("  %s" % p)
    print("\nRESULT: FAIL")
    sys.exit(1)


if __name__ == "__main__":
    main()
