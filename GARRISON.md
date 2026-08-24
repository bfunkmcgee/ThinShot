# The garrison, built out

The zoning pass (ASSETS.md, Tier 6) gave the yard quarters; this is the
construction pass that gives the quarters walls. It is a design, not a map
edit: most of what it places does not have art yet, and nothing here should
land in `CampData.gd` until its building does. The layout below is validated
mechanically — every fixture on a named cell, every station spot on open
ground, the wall ring closed, the pen actually enclosed — so when the art
arrives the edit is transcription rather than design.

## Why it is laid out the way it is

A garrison is an argument about what you expect to happen to it, and this one
expects what the campaign says: raids on the water, a gate that must be
watched, replacements greener than the people they replace, and prisoners
worth more alive. Each principle below is one a real desert post uses, and
each is doing work a rule in this game already does.

- **One gate, overwatched.** Everything enters and leaves under the tower.
  The wall has exactly one gap, south, and the watchtower stands inside it.
- **Command deepest from the gate.** The HQ backs onto the north wall, the
  whole yard between it and the breach anybody would have to make.
- **The armory in the middle, under command's eye.** Weapons and ammunition
  sit where the HQ can see them, a stand-off from the wall (nothing lobbed
  over lands on the magazine) and from the billets (nobody sleeps against
  the one building that can go up).
- **The range fires outward.** Firing line inside, berm against the north
  wall, rounds that miss leave over empty desert. The ammunition point is
  behind the firing line, which is where a real range wants it — and where
  the armory already is.
- **Detention beside the gate.** A man the Accord is collecting leaves
  without being walked through the middle of the camp.
- **Sleep in the west, work in the east.** Billets, washing, the stove and
  the canteen on one side; armory, range, motor pool and the pen on the
  other. Off duty has a side of the yard.
- **Water where it is used.** The bowser by the billets and canteen, the
  tank over the motor pool where the trucks fill. In a war about water the
  garrison's own supply should be conspicuous, and it is.

## The map

22×12, against today's 16×12. `G` marks the gate gap — it ships as `.`
(Board has no gate char; the gate art, ASSETS.md #2, hangs on the flanking
wall cells when it lands).

```
WWWWWWWWWWWWWWWWWWWWWW
W.....j.....jjjjjjjj.W    flag(6,1) | HQ(8,1) | signals(12,1) berm(13..19,1)
W..j..........j.j.j..W    washing(3,2) | targets(14,16,18 ,2)
W....................W    HQ porch: dressing(8,3)(10,3) briefing(9,3)
W....................W
W......j.j..j.j.j.j..W    duty board(7,5) bounty board(9,5) | range flag(12,5) mats(14,16,18 ,5)
W...j..........jj....W    kit frame(4,6) | ammo(15,6) cleaning(16,6)
W......j...........j.W    bowser(7,7) | water tank(19,7)
W...........j..=.....W    awning(12,8) | pen wire(15,8), pen gate(16,8)
W.....j......j=......W    stove(6,9) | jerry cans(13,9) wire(14,9) pen(15..16,9)
W.pjp.......j.=......W    memorial(3,10) | tower(12,10) wire(14,10) pen(15..16,10)
WWWWWWWWWGGWWWWWWWWWWW    gate(9..10,11)
```

Structures (2×2 anchors): billets `hut_1`(1,1), `hut_2`(1,4), `field_tent`
(1,7) — all shipped art; **HQ**(8,1), **surgeon's tent**(4,3) (#27),
**canteen**(4,8), **armory**(13,6), **lockup**(17,9) — all new.

Stations and spots: player wakes mid-parade (9,6); briefing on the HQ porch
(9,3) with the map crates flanking; stores at the armory's south door (14,8);
the QM issue counter at its west window (12,7); paymaster beside the HQ's
east gable (11,2); the duty and bounty boards on the parade's north edge
facing the HQ, with the levy post working the same row (8,5); the ledger
stays at the memorial (3,9) — the money can move to the paymaster when #25
lands, the CAREERS page stays at the cross if that pairing was the point.
Squad idle: two by the canteen and billets, one on the parade, one at the
firing line (17,5), one by the motor pool, one loose.

## The buildings

**HQ** — a command post, not a fortress: the garrison is eight people. Mud
brick the Confederacy raised, a steel door and an antenna stub the Crown
added, which is the whole art direction for every building here — local
shells, Crown fittings. The briefing happens standing up on its porch,
because the map is pinned to the porch wall; deployment has always been an
outdoor decision and stays one. The signals mast (#24, the ratline's
mission-giver) plants at its east gable so the two mission sources — the
briefing table and the border net — are ten steps apart. Do NOT reuse the
Outpost 7 fortress art: the sign on it names a place this garrison is not,
and a wrong sign on the ground is a lie the fiction would notice.

**The wet canteen** — the recreation building, and the Crown word for a bar
on post. End of the billet row, stove at its door, as far from the HQ as the
yard allows, which is where every army in history has put it. This is where
the squad idles and where Sillae reads the theater back — she does it over
a drink now instead of over a grave's shoulder. Scrip spends here in the
fiction; no mechanic rides that yet.

**The armory** — windowless, buttressed, stencilled, the only building in
the yard with nothing to sit on. The quartermaster issues from its west
window (#26), the stores split happens at its south door, ammunition boxes
and the cleaning bench stand at its east wall where the range's firing line
starts. One building answers three functions that today stand in three
corners of the yard.

**The lockup** — a low blockhouse and a wired pen, beside the gate, under
the tower. The campaign already pays more for a live man and already lets a
bounty end with "he walked in ahead of the party" — this is where he walks
IN TO, and where the Accord collects from. The echo is deliberate and the
game should own it: THE HOLDING PENS is a mission about people kept in a
pen, and the squad keeps one too. Wire is the battle `=` char — real rules,
stops movement, no cover — which Camp does not yet draw (see below).

**The range** — three lanes against the north wall: firing-point mats,
silhouette targets, an earth berm as the backstop, a red flag flying at the
entry because the range is live whenever the yard is. The levy post stands
a row south: the recruits it signs are level-1 green, the conscripts across
the wire shoot at 48%, and the range is where the difference between those
two numbers is manufactured. Pure scenery at first; if it ever earns a
mechanic, it is the natural home for a resting soldier's line.

**Gate, motor pool, memorial** — the tower moves from the back wall to the
gate it exists to watch. The awning, jerry cans and water tank make the
motor pool inside the gate where trucks fill and park. The memorial keeps
what the zoning pass gave it — alone, in a planted row — but holds the
south-west corner now, beside the way out.

## The asset bill

Ships today: both huts, the field tent, wire, tower, flag, water tank,
bowser, awning, stove, washing line, kit frame, ammo box, cleaning bench,
notice board, memorial, jerry cans; `Signal_banner` serves as the range
flag; sandbags stand in for the berm until it has its own art.

| Piece | Canvas | Notes |
|---|---|---|
| ~~HQ command post~~ — **shipped** | 2×2 (168) | `garrison_buildings/Hq_post`, offset −36 |
| ~~Wet canteen~~ — **shipped** | 2×2 (168) | `garrison_buildings/Wet_canteen`, offset −37 |
| ~~Armory magazine~~ — **shipped** | 2×2 (168) | `garrison_buildings/Armory_magazine`, offset −35 |
| ~~Lockup blockhouse~~ — **shipped** | 2×2 (168) | `garrison_buildings/Lockup`, offset −34 |
| ~~Surgeon's tent~~ — **shipped** | 2×2 (168) | `garrison_buildings/Surgeon_tent`, offset −26 — closes #27's art half |
| Earth berm | 48×48 ×2–3 | replaces the sandbag stand-in; reads as pushed dirt |
| Range target | 48×48 ×2 | steel silhouette on a timber frame, patched holes |
| Firing point | 48×48 | mat, sand sock, brass on the ground |
| Gate | 68×68 wall-format | already specced as #2; camp wants the OPEN state |
| ~~Water truck~~ — **shipped** | 2×2 (168) | `garrison_buildings/Water_truck`, offset −29 |

Generation notes are Tier 6's, unchanged: name the modern material in every
prompt, no sand disc, 48px batches anchored on shipped props.

All six buildings generated 2026-08-24 (two 168px batches, 50 generations,
one round, no rejects) and registered as Camp structure kinds `hq`,
`canteen`, `armory`, `lockup`, `surgeon_tent`, `water_truck` — unplaced
until the map lands. Two alternate takes (an HQ with its own lattice mast,
a canteen with a painted sign) stay in the PixelLab library unused: the
mast would double #24's, and the sign was louder than this game's voice.

## Implementation notes, for whoever builds it

- Camp's prop spawner has no `=` branch: copy Battle's wire-kind selection
  and textures across (Board already parses `=` as WIRE, so movement is
  right the moment the map lands; only the drawing is missing).
- New structure kinds are one line each in `Camp.STRUCTURE_DIRS` and
  `STRUCTURE_OFFSETS`, measured off the art's opaque bounds as always.
- The gate ships as two open wall-row cells. Camp's bounds keep the player
  inside; the gateway is somewhere to stand, not somewhere to leave.
- The tower at (12,10) is a tall prop at the front of the yard: it will
  occlude a walking soldier two rows behind it. Battle solved this with the
  occlusion fade; port it to Camp if it bothers, and until then the motor
  pool keeps its ground clutter low.
- The awning keeps clear cells either side — its canopy is two tiles wide
  on a one-tile stand. (12,8) has both.
- Staged landing order, each step leaving the yard coherent: (1) map +
  wire + relocated fixtures with today's art, buildings absent; (2) each
  building as its art arrives, its stations moving in with it; (3) the
  range set; (4) the gate.
