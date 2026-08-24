"""The garrison interiors, validated before a line of them reaches a doc.

Same discipline as garrison_design.py: every 'j' named, ring closed except
the door, every walkable cell reachable from the door, and any barred cell
('=' = jail bars, wire semantics: stops movement, sees through) sealed
except where a prisoner spawn stands inside it.
"""
from collections import deque

INTERIORS = {
 "hq": {
  "rows": ["WWWWWWWWWW",
           "W.j..j..jW",
           "W........W",
           "Wj..jj..jW",
           "W........W",
           "W........W",
           "WWWW..WWWW"],
  "props": {(2,1):"files_cabinet",(5,1):"radio_desk",(8,1):"map_board",
            (1,3):"command_desk",(4,3):"map_table",(5,3):"map_crates",(8,3):"strong_safe"},
  "door": [(4,6),(5,6)], "spawn": (4,5),
 },
 "canteen": {
  "rows": ["WWWWWWWWWW",
           "Wjjj..j.jW",
           "W........W",
           "W..j..j..W",
           "W........W",
           "W.j....j.W",
           "WWWW..WWWW"],
  "props": {(1,1):"bar_counter",(2,1):"bar_counter_1",(3,1):"bar_counter_end",
            (6,1):"bottle_shelf",(8,1):"field_stove",
            (3,3):"canteen_table",(6,3):"canteen_table",
            (2,5):"canteen_table",(7,5):"canteen_table"},
  "door": [(4,6),(5,6)], "spawn": (4,5),
 },
 "armory": {
  "rows": ["WWWWWWWWW",
           "Wjj.j.jjW",
           "W.......W",
           "Wj.....jW",
           "W.......W",
           "WWW..WWWW"],
  "props": {(1,1):"rifle_rack",(2,1):"rifle_rack",(4,1):"qm_shelving",
            (6,1):"ammo_box",(7,1):"ammo_box",
            (1,3):"qm_counter",(7,3):"cleaning_bench"},
  "door": [(3,5),(4,5)], "spawn": (3,4),
 },
 "lockup": {
  "rows": ["WWWWWWWWW",
           "Wj..W..jW",
           "W...W...W",
           "W===W===W",
           "W.......W",
           "Wj.....jW",
           "WWW..WWWW"],
  "props": {(1,1):"cell_cot",(7,1):"cell_cot",(1,5):"guard_stool",(7,5):"notice_board"},
  "door": [(3,6),(4,6)], "spawn": (3,5),
  "cells": [{"cells":[(1,1),(2,1),(3,1),(1,2),(2,2),(3,2)],"spawn":(2,2)},
            {"cells":[(5,1),(6,1),(7,1),(5,2),(6,2),(7,2)],"spawn":(6,2)}],
 },
 "surgeon": {
  "rows": ["WWWWWWWWW",
           "Wj.j.j.jW",
           "W.......W",
           "Wj.....jW",
           "W.......W",
           "WWW..WWWW"],
  "props": {(1,1):"cot",(3,1):"cot",(5,1):"cot",(7,1):"medical_chest",
            (1,3):"wash_stand",(7,3):"folding_screen"},
  "door": [(3,5),(4,5)], "spawn": (3,4),
 },
 "billet": {
  "rows": ["WWWWWWWWW",
           "Wj.j.j.jW",
           "W.......W",
           "Wjj....jW",
           "W.......W",
           "WWW..WWWW"],
  "props": {(1,1):"bunk",(3,1):"bunk",(5,1):"bunk",(7,1):"bunk",
            (1,3):"footlocker",(2,3):"footlocker",(7,3):"field_stove"},
  "door": [(3,5),(4,5)], "spawn": (3,4),
 },
}

errs=[]
for name, spec in INTERIORS.items():
    rows=spec["rows"]; W=len(rows[0]); H=len(rows)
    grid=[list(r) for r in rows]
    if any(len(r)!=W for r in rows): errs.append("%s: ragged rows"%name)
    door=set(spec["door"])
    for y in range(H):
        for x in range(W):
            ch=grid[y][x]
            border = x in (0,W-1) or y in (0,H-1)
            if border and ch!="W" and (x,y) not in door:
                errs.append("%s: ring open at %s"%(name,(x,y)))
            if ch=="j" and (x,y) not in spec["props"]:
                errs.append("%s: unnamed furniture at %s"%(name,(x,y)))
    for c,nm in spec["props"].items():
        if grid[c[1]][c[0]]!="j": errs.append("%s: prop %s at %s not on j"%(name,nm,c))
    cellsets=spec.get("cells",[])
    barred=set()
    for cs in cellsets: barred|=set(cs["cells"])
    def walk(c):
        x,y=c
        return 0<=x<W and 0<=y<H and grid[y][x]=="." and c not in barred
    start=spec["spawn"]
    if not walk(start): errs.append("%s: spawn %s not walkable"%(name,start))
    seen={start}; q=deque([start])
    while q:
        x,y=q.popleft()
        for n in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
            if n not in seen and walk(n): seen.add(n); q.append(n)
    for y in range(H):
        for x in range(W):
            if grid[y][x]=="." and (x,y) not in barred and (x,y) not in seen:
                errs.append("%s: cell %s unreachable from the door"%(name,(x,y)))
    # cells sealed and their spawn inside them
    for i,cs in enumerate(cellsets):
        inside=set(cs["cells"])
        if cs["spawn"] not in inside: errs.append("%s cell %d: spawn outside"%(name,i))
        for (x,y) in inside:
            for n in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
                if n in inside: continue
                ch=grid[n[1]][n[0]]
                if ch not in "W=": errs.append("%s cell %d leaks at %s"%(name,i,n))
print("ERRORS: %d"%len(errs))
for e in errs: print(" -",e)
print("\n%d interiors validated"%len(INTERIORS))
