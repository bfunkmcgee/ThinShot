# SANDLINE — canon bindings

What this repo owes the Veil Codex, distilled so a session needs no network.

**Source of truth:** https://github.com/bfunkmcgee/Veil_lore ("the Codex").
**Written against:** Canon CR3 · build CR2.1 · narrative NF2 · engineering RM5 ·
59 rulings (2026-08-25). If the Codex has moved past that line, re-verify
anything load-bearing before relying on this file.

The governing rule (RM1/RM6): **fiction conforms to the Codex; mechanics
conform to the build.** The shipped Godot build outranks the Codex's own legacy
design document (Book VIII.2, the "Sand & Sorcery" spec — its Vector Atlas
visuals section included); the Codex outranks everything this repo says about
the world.

## The rulings that bind this repo

| Ruling | One line |
|---|---|
| **RM1** | ThinShot adopted as the SANDLINE implementation; mechanics follow the build, fiction follows the Codex |
| **RM4** | The surveyor-collector "at the end of the tracks" *is* the Cartographer — the Confederacy's former survey-master |
| **RM5** | `Rules.gd` is the canonical home of combat arithmetic, with assertions in `tools/test_rules.gd` |
| **RM6** | The canon integration plan (`Veil_lore/docs/SANDLINE_Canon_Integration_Plan.md`) is itself a ruling |
| **RM7** | The Appendix A mission rewrites (missions 1–7) are authored canon, adopted here verbatim |
| **GS1** | SANDLINE systems specification + campaign mission manifest (world bible VIII.2.5–VIII.2.6) |
| **GS2** | No pacifist optimum: killing an armed, fighting combatant costs nothing — no Standing, no Strain, no rating. Conduct is what costs |
| **KC1** | Rodar Akai, Kestrel Squad, the Accord Ranger Program, the Grounded Doctrine, the Felia crossover |
| **KC2** | The insurgency's two wings, the Countrymen, the Cupbearers, the Riverspoken; "SANDLINE" as the name |
| **KC3** | OLD PROMISE — the Act V horror climax |
| **KC4** | Rodar's origin: Dray Cross freight yards, conscript, temperament |
| **KC5** | Inspector Emrys Ashcombe — the human-intelligence layer |
| **TR2** | Goblins are a species, not a threatform; the insurgency is political |
| **CR1** | House style: archival lyricism — see Tone, below |

## Names

| Thing | Canon |
|---|---|
| The player's side | **Kestrel Squad**, Third Expeditionary Ranger Company — Crown conscripts seconded to the Confederacy under the **Sandline Accord** (the Accord Ranger Program) |
| The enemy | **The Thirst** — the radical wing of the goblin insurgency; dispossessed duneworks labour, dispossessed by the **Charter of Wells** |
| The political wing | **The Assembly of Wells**, led by Matriarch Ottla Brimm — never a target |
| The Thirst's warleader | **Vrikka Half-Well**, Ottla's former protégée |
| Elven militants beside the Thirst | **The Cupbearers** — the old well-oath's name, taken by the crossed-over (shipped here as `Kind.ELF_PARTISAN`) |
| Elven elders who share water against the Charter | **The Old Wells Society** |
| The cult inside the Thirst | **The Riverspoken** (patron: Sael-Vel); field prophets are **Linewalkers**; conducted fighters are **the Spoken-For** |
| The man at the end of the tracks | **The Cartographer** — an elderly desert elf, the Confederacy's former survey-master (RM4). Never captured, never killed on screen: "seen twice, settled never" |
| The ghost guns | **Tarkesh Foundry Wound-steel Mattocks** — factory-new rifles from a foundry unwritten in A.V. 1983, moving through a Crown depot eleven years off the maps |
| The eight Kestrels | Rodar Akai (lead) · Josen Marr · Essa Vane · Sillae Vekh · Halvik Dunn · Brukk Meshan · Dava Ren · Fen Ost |
| Unit labels | The single source is `Unit.kind_role_name()` — Thirst Well-hand / Runner / Light Runner / Marksman / Gunner / Breaker, Pressed Conscript, Cupbearer, Settlement Elder / Stallkeeper / Water-carrier, Kestrel ⟨role⟩, "Rodar Akai, Kestrel Squad" |

## Tone

The three Appendix A rules, held by every briefing and debrief in the game:

1. **No briefing implies the killing was avoidable.**
2. **No debrief grades the player.**
3. **The enemy has a reason, and it is a good one** — motive replaces menace;
   the Charter of Wells is the reason for everything.

The GS2 two-panel rule: **THE OPERATION is graded, THE ROLL is reported, and
they are never summed.** The moment a name costs a point, the player optimises
against grief and stops reading the names.

House style (CR1): archival lyricism — austere institutional language pierced
occasionally by the strange, the funny, or the painfully human. *Occasionally*
is load-bearing: a quarter to a third of all prose should be plainly ordinary,
so that when a sentence lands like scripture, it still can.

Vocabulary watchpoints: victory banners never read as scorelines (`CONTACT
RESOLVED`, not WIN); once a name is known the interface never again says
hostiles; "goblin" is a species, spoken plainly, never a slur or a rabble
framing; the word *Choir* is dead canon (pre-conversion enemy name) and must
not reappear in anything player-visible or in live authoring docs.

## Visual canon

- **Chunky 2× pixel art is ratified** (RM1; ruling EN2 embedded the in-game
  Rodar sprite in the world bible). The Codex's legacy "Vector Atlas" visuals
  spec is superseded by the build. The hi-res v2 unit program is suspended by
  user verdict — do not re-propose.
- Executing authority for *how* art is made: `UNIT_ASSET_SPEC.md` (units) and
  `artgen/STYLE.md` (ground). Kestrels are tan/brown desert military; the
  Thirst are green-skinned goblins **in worn work clothes** — dispossessed
  duneworks labour, per KC2.
- **New generation prompts must frame the Thirst that way** — labourers off a
  capped well, worn kit, scrap only where scrap is the story. Never
  street-gang framing (hoodies, sneakers, "gangster"); a few older sprite
  prompts read that way and are kept only as history.
- `assets/sprites/*/metadata.json` files are **pipeline records, not
  fiction** — they log what was once sent to PixelLab and are not retconned
  (one exception made: the Elf_Partisan name field, which flatly contradicted
  the shipped fiction).

## Repo-invented fiction awaiting upstream rulings

This repo extends the world beyond what the Codex has ruled on. None of it
*contradicts* canon; per the process in CLAUDE.md it should be filed in
Veil_lore as integration rulings (the RM4 pattern: adopt the repo's invention
rather than overwrite it). The list, in rough order of weight:

1. **OPERATION BURNT SURVEY** (missions 8–9: THE CINDER ROAD, THE COLD WELL) —
   the Cartographer flees west through country the Thirst burned, drops his
   supply, and is denied the last surveyor at the last well. Extends the
   Act III→IV bridge; keeps him unresolved, consistent with VIII.3.9.
2. **The Cupbearer as a fielded unit** — `Kind.ELF_PARTISAN`: long rifle,
   mobile, *can* break (he has a side of the wire to go back to). Adopts the
   KC2 faction as a battlefield presence. Open sub-item: `Roll.gd` draws his
   named-dead identity from the goblin name register and the four goblin
   settlements — an elf falling on the roll currently gets a goblin name and a
   capped-well grievance. Needs either an elven register upstream or a ruling
   that the roll records where he fought from, not where he was born.
3. **The goblin civilian kinds** — Settlement Elder, Stallkeeper,
   Water-carrier ("so a settlement stops being drawn out of the rifle rack").
4. **The named-dead register** (`Roll.gd`) — settlements Ashet Draw, Bhorra
   Low, Kessit, Vennet Rill, each with a Charter grievance line; the given and
   family name pools.
5. **The bounty and ratline place-names** — THE SUMP, KHERRA WELL, THE
   TAILINGS, SALT REACH, THE LOW CROSSING, OSSA FLATS; the Dry Ford, the Salt
   Gap, Broke-Tooth Pass, the Old Survey Track, Threadneedle Wash, the Night
   Steps.
6. **The garrison** as the campaign's home base (GARRISON.md, INTERIORS.md) —
   layout doctrine, the lockup, the wet canteen, the surgeon's tent.
7. **The Holding Pens briefing extension** — two paragraphs beyond Appendix A
   teaching the rescue mechanics (wire, the gate, the freed prisoner's pace).
   A mechanical-clarity addition, not a fiction change.
8. **Minor texture** — the Gear item names (`ACCORD CUIRASS` and kin), the
   Sillae district readings in `Camp.gd`, parley lines, the tagline on the
   main menu.
9. **THE RANGE** (real-time live-fire drill, `scenes/Arena.tscn`) — a
   Grounded Doctrine qualification course run at the garrison range: goblin
   silhouettes stood up in waves for Rodar to work through alone, off the
   books and off the mission clock. Self-contained; touches no campaign save,
   fields no civilians, names no dead (its fighters are targets, not people
   on THE ROLL). Its banners hold the scoreline rule: `LINE HELD`, never a
   count; `THE LINE BROKE`, never a grade.
