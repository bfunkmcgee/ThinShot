# SANDLINE — guide for Codex sessions

Godot 4 turn-based tactics. The project is **SANDLINE**; the repo folder still
says ThinShot for historical reasons, and so do a handful of internal names.
Neither is worth churning — see the identifier rule below.

## The Codex — where the fiction comes from

**The lore source of truth is the Veil canon repository:
https://github.com/bfunkmcgee/Veil_lore** — referred to throughout this repo
and its history as "the Codex".

The governing rule, verbatim from its integration plan (rulings RM1/RM6):

> **Fiction conforms to the Codex. Mechanics conform to the build.**

Nothing canonical may change a rule, a stat, a spawn, or a tuning value; and no
player-visible text may contradict the Codex. If a fiction commit moves a test,
the commit is wrong.

- **Day to day**: [docs/CANON.md](docs/CANON.md) distills every binding this
  repo needs — rulings, names, tone rules, visual canon — with the canon
  version it was written against. Start there; most sessions never need more.
- **Deep questions**: clone Veil_lore and read
  `codex/Veil_Unified_World_Bible.md` Book VIII (VIII.2.5 systems spec,
  VIII.2.6 mission manifest, VIII.3 the Kestrel Campaign) and
  `docs/SANDLINE_Canon_Integration_Plan.md` (Appendix A holds the authored
  mission text for missions 1–7, adopted here verbatim).
- **New canon**: fiction invented in this repo that extends the world — a new
  named place, character, faction detail, or operation — should be proposed
  upstream as a Veil_lore ruling (its `add_ruling.py` flow), never silently
  diverged. docs/CANON.md keeps the list of what is awaiting a ruling.

## Hard constraints

- **Never reorder or insert into `Kind` or the `TEAM_*` constants.** Saves
  persist raw ordinals; append only, and climb `SAVE_VERSION`.
- **The `goblin` identifiers stay.** `Kind.GOBLIN_*`, `TEAM_GOBLIN`,
  `goblin_spawns`, `assets/sprites/Goblin_*/` — enum members, data keys, and
  thousands of asset paths. Canon governs what the player is told, not what
  the developer types; the Thirst *are* goblins (the species was never the
  problem, the rabble framing was). The only player-facing faction vocabulary
  is `Unit.kind_role_name()`.
- **Chunky 2× pixel art is the ratified style** (Codex rulings RM1/EN2 — the
  in-game Rodar sprite is embedded in the world bible itself). Never propose
  HD regeneration; the hi-res v2 program is suspended by user verdict.
- `Rules.gd` is the canonical home of combat arithmetic (RM5): any mechanic
  expressible as a number lands there with an assertion in
  `tools/test_rules.gd`.

## Where the fiction lives

| Surface | File |
|---|---|
| Faction/role labels (all of them) | `scripts/Unit.gd` `kind_role_name()` |
| Missions: fiction/briefing/orders/debrief | `scripts/Levels.gd` |
| Named dead: names, settlements, grievances | `scripts/Roll.gd` |
| Procedural missions: bounties, ratline | `scripts/Bounty.gd`, `scripts/Ratline.gd` |
| Banners, the roll, parley lines | `scripts/Battle.gd` |
| Camp prompts, Sillae's district readings | `scripts/Camp.gd` |
| The story bible in prose | `README.md` |
| Art style contracts | `UNIT_ASSET_SPEC.md`, `artgen/STYLE.md` |
