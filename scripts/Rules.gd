class_name Rules

## The shooting rules, lifted out of the controller so they can be checked.
##
## The game asks these questions twice. Once while the player is still hovering
## a target and the panel has to promise what the shot would do, and once a
## moment later when the trigger is pulled and the roll has to deliver it.
## Those two answers came from the same function already, but only because
## nobody had yet had a reason to write a second one - and a tactics game where
## the percentage on screen and the percentage rolled can drift apart is a
## tactics game the player stops trusting. Keeping the arithmetic in a file of
## its own, with the numbers it reads, makes that a structural fact rather than
## a habit.
##
## Everything here is static and takes the Board it needs as an argument rather
## than reaching for one. That is not ceremony. Board's spatial predicates -
## line of sight, cover by sector, the lean around a corner - already run on a
## bare `Board.new()` with no scene tree under it, which is how
## tools/check_cover_rules.gd sweeps all seven shipped maps. Passing the handle
## in is the whole cost of extending that reach to the shooting rules, so they
## can be tested against geometry built for the purpose instead of whatever a
## shipped level happens to contain.
##
## What is deliberately absent: Inspiration's aura. Finding it means walking
## the living units looking for a hero, which is the controller's job and not a
## rule. Battle totals it and hands the finished number in.

# --- The to-hit numbers -------------------------------------------------------

const FLANK_ACCURACY := 10    # bonus to hit from outside the target's arc
const FLANKER_ACCURACY := 10  # the Flanker perk's extra, on top of the flank bonus
const LONG_SHOT_PENALTY := 5  # per tile past half the shooter's range
const SUPPRESSION_ACCURACY := 25  # % of the positional chance the pin takes
const FULL_COVER_ACCURACY := 25   # to-hit penalty against a target behind a wall
const PEEK_ACCURACY := 10         # to-hit penalty for leaning around your own cover

## Inspiration's aura: this much to hit while a living allied hero carrying the
## perk stands within this many tiles of the SHOOTER. The rule lives here with
## the rest of the balance; the search for the hero does not (see the header).
const INSPIRATION_RANGE := 4  # manhattan tiles around the perked hero
const INSPIRATION_ACCURACY := 5

## Executioner: a flanking round lands this much harder. Named rather than
## written as a bare 1 in the damage code, so the perk can be found by reading
## the rules instead of by grepping for an increment.
const EXECUTIONER_BONUS := 1

## Every shot is worth taking and no shot is a certainty. The floor keeps a
## pinned soldier at long range from being told his rifle is decorative; the
## ceiling is one short of 100 so that the dice always have something to say,
## which is also why a test can never assume a quoted shot will land.
const MIN_HIT_CHANCE := 20
const MAX_HIT_CHANCE := 99


# --- Facing, cover, and the lean ---------------------------------------------

## True if the shot comes from outside the target's front arc, in which case
## cover does not protect it. Derived from cells, never live positions, so
## the hover preview and the resolved shot always agree.
static func is_flanking(attacker: Unit, target: Unit) -> bool:
	return not target.covers_sector(Board.sector_from_to(target.cell, attacker.cell))


## The cover that actually applies to this shot. A unit only benefits from
## what it is facing into - shot from outside its front arc, it is caught with
## its back to the wall rather than behind it, and the cover does nothing.
##
## Which makes flanking and cover mutually exclusive by construction: a flanked
## target has NONE, whatever it is standing beside. Both the hit roll and the
## damage rule lean on that, and it is why they can test the two conditions in
## either order and still agree.
##
## Both of those are properties of the target and where the shot comes from,
## not of the Unit object, so the rule is written one level down in `cover_at`
## and this is the call that reads a live target's numbers off it.
static func effective_cover(board: Board, attacker: Unit, target: Unit) -> Board.CoverLevel:
	return cover_at(board, target.cell, target.facing_sector, target.arc_half,
			attacker.cell)


## The same question with the units taken out of it: a unit standing at `cell`,
## facing `facing_sector` with a front arc `arc_half` sectors wide either side,
## shot at from `from_cell` - what cover applies?
##
## This exists because the AI has to ask it about a cell nothing is standing on
## yet, with a facing nothing is holding yet, and `effective_cover` can only be
## asked about a Unit that is already there. Battle's `_best_ai_dest` works out
## an `end_sector` for each candidate cell for exactly that reason. Before this,
## the AI gave up and scored `board.cover_between` instead - facing-blind, a
## model the resolver does not use - so goblins took cover that would not be
## there when the shot came.
##
## `effective_cover` is now one call to this, so there is a single
## implementation of the COVER rule and no way for the AI's model and the
## resolver's to drift apart again.
##
## The arc line is Unit.covers_sector's test written out rather than called.
## That is not an oversight and not a second rule: the whole value of this
## function is that it needs no Unit - it takes four numbers and a bare Board,
## so a sweep with nothing in the scene tree can ask it (which is how
## tools/measure_phantom_cover.gd measures the shipped maps, and it runs before
## the autoloads exist, where naming Unit fails outright). Unit.gd is
## deliberately independent of Board and cannot host the test either. If the arc
## rule ever changes, it changes in both places - and tools/test_rules.gd sweeps
## every cell, facing and arc width against a third, independent spelling of it,
## so a one-sided edit is caught rather than shipped.
static func cover_at(board: Board, cell: Vector2i, facing_sector: int,
		arc_half: int, from_cell: Vector2i) -> Board.CoverLevel:
	# Sector pointing from the target toward the shot - the direction the target
	# would have to be facing to be behind its cover rather than against it.
	# -1 is the same cell, which counts as inside the arc; cover_between returns
	# NONE for that pair anyway.
	var sector := Board.sector_from_to(cell, from_cell)
	if sector >= 0 and absi(wrapi(sector - facing_sector + 4, 0, 8) - 4) > arc_half:
		return Board.CoverLevel.NONE
	return board.cover_between(from_cell, cell)


## True when the shooter has to lean around its own full cover to take this
## shot: the direct line is blocked, but an adjacent cell can see the target.
static func is_peeking(board: Board, attacker: Unit, target: Unit) -> bool:
	return board.can_peek(attacker.cell, target.cell)


# --- The roll ----------------------------------------------------------------

## Percent chance this shot connects. Cover is deliberately NOT an accuracy
## modifier - it already halves damage, and keeping the two rules separate
## keeps both readable. Flanking helps; so does not taking a long shot.
##
## `inspiration` arrives already totalled because this runs on every mouse
## motion that moves the panel, and a hero-shaped search of the entity list per
## hover is a cost the rules should not be quietly imposing on the controller.
static func hit_chance(board: Board, attacker: Unit, target: Unit,
		accuracy_mod := 0, inspiration := 0) -> int:
	var chance := attacker.accuracy + accuracy_mod
	# The hero's steadying hands: Rally's transient bonus on the soldier, and
	# Inspiration's aura for standing near a living hero who carries it.
	chance += attacker.rally_bonus
	chance += inspiration
	if is_flanking(attacker, target):
		chance += FLANK_ACCURACY
		if attacker.has_perk("flanker"):
			chance += FLANKER_ACCURACY
	# Half cover only costs damage, keeping the old rule intact. Full cover is
	# what a soldier is genuinely hard to hit behind, so it costs accuracy too -
	# that difference is the whole reason to prefer a wall to a scrap pile.
	elif effective_cover(board, attacker, target) == Board.CoverLevel.FULL:
		chance -= FULL_COVER_ACCURACY
	# Leaning out around your own cover is an awkward way to shoot.
	if is_peeking(board, attacker, target):
		chance -= PEEK_ACCURACY
	var dist := Board.manhattan(attacker.cell, target.cell)
	# Integer division on purpose: a 5-tile weapon is comfortable to 2, the same
	# as a 4-tile one. Half a tile of comfort is not a thing the grid can express.
	var comfortable: int = attacker.attack_range / 2
	# A Marksman has shot at that range enough times for it to stop mattering.
	if dist > comfortable and not attacker.has_perk("marksman"):
		chance -= (dist - comfortable) * LONG_SHOT_PENALTY
	chance = clampi(chance, MIN_HIT_CHANCE, MAX_HIT_CHANCE)
	# Being pinned takes its quarter of whatever the position left - AFTER the
	# clamp, multiplicatively, so suppression is worth the same fraction
	# against a dug-in target as against one in the open. The old additive
	# -25 vanished under the floor exactly where the player was playing well:
	# a Conscript shooting into full cover lost nothing at all to the pin.
	# This is also the one number allowed below MIN_HIT_CHANCE, which is a
	# clamp on the POSITION; the pin is not a position, it is a machinegun.
	if attacker.is_suppressed():
		chance = chance * (100 - SUPPRESSION_ACCURACY) / 100
	return chance


## The roll. Every shot in the game comes through this one line, and that is the
## whole point of it having a name: the single stochastic step in a game of
## otherwise exact arithmetic should be findable by reading rather than by
## grepping for `randi` and hoping the list is short.
##
## The generator is passed in for the same reason the board is - Battle keeps
## two streams and only one of them is allowed to decide anything (see its
## _rules_rng comment), and a rule that reached for a global would quietly draw
## from whichever one was handy.
##
## `randi_range(1, 100) <= chance` is the shape, exactly. It is a percentage
## against a uniform d100: at chance 20 twenty of the hundred outcomes land, at
## 99 all but one does. Any other spelling - randf(), 0..99, `<` - shifts the
## distribution by a point somewhere, and hit_chance's clamp is calibrated
## against this one.
static func roll_hits(rng: RandomNumberGenerator, chance: int) -> bool:
	return rng.randi_range(1, 100) <= chance


# --- The round ---------------------------------------------------------------

## The cover this shot has to get through. `effective_cover` already answers
## what the target's facing leaves it; this adds the one shot that goes where
## the cover is not. Both reductions mean the same thing by the same word -
## cover that APPLIES, not cover that exists - so a called shot at a soldier
## hugging a wall reports NONE for the same reason a flanked one does.
static func _applied_cover(board: Board, attacker: Unit, target: Unit,
		ignore_cover: bool) -> Board.CoverLevel:
	if ignore_cover:
		return Board.CoverLevel.NONE
	return effective_cover(board, attacker, target)


## What one round takes off, before the target's own arithmetic.
##
## PER ROUND. A burst fires this several times; how many, and how to say so on
## the panel, is the controller's business and not a rule.
##
## The branch order is cover first, flank second. That is not a coin toss: it
## is the order the resolver has always used, and the resolver is the one that
## pays out - if a preview and a round ever came apart, the number on screen
## would be the wrong one by definition, so the screen should be quoting the
## resolver's shape. The other order was equally correct, and that was the
## problem: two spellings of one rule, agreeing only because `effective_cover`
## returns NONE on a flank (see above) and so a flanked target can never reach
## the halving arm. That invariant is pinned by tools/test_rules.gd, but it now
## has nothing to hold together here - there is one spelling left.
##
## `ignore_cover` is the called shot's whole trick: the roll stays a normal
## one, the damage is simply never halved. `bonus_damage` carries One Shot's
## extra, and lands BEFORE the halving, so a bonus fired into cover is halved
## along with the rest of the round.
static func damage_for(board: Board, attacker: Unit, target: Unit,
		bonus_damage := 0, ignore_cover := false) -> int:
	var dmg: int = attacker.damage + bonus_damage
	if _applied_cover(board, attacker, target, ignore_cover) != Board.CoverLevel.NONE:
		return dmg >> 1
	if is_flanking(attacker, target) and attacker.has_perk("executioner"):
		dmg += EXECUTIONER_BONUS
	return dmg


## Everything a shot that has not been fired yet can be asked, answered once.
##
## This exists because the answer used to be assembled four times over: the
## resolver, the panel's damage line, the panel's called-shot line, and the
## colour of the aim line all re-derived flank and cover for themselves. They
## agreed, but by coincidence renewed at every edit rather than by construction.
## A tactics game where the promise and the round can drift apart is one the
## player stops trusting, and the cheapest way to make drift impossible is to
## leave only one place capable of answering.
##
## `chance` is the roll to beat, `dmg` is PER ROUND (see damage_for), `cover`
## is the cover that APPLIES to this shot - NONE on a flank, and NONE when
## `ignore_cover` says the round goes around it - and `flanking` / `peeking`
## are the two facts the panel and the aim line label themselves with.
static func shot_preview(board: Board, attacker: Unit, target: Unit,
		accuracy_mod := 0, inspiration := 0,
		bonus_damage := 0, ignore_cover := false) -> Dictionary:
	return {
		"chance": hit_chance(board, attacker, target, accuracy_mod, inspiration),
		"dmg": damage_for(board, attacker, target, bonus_damage, ignore_cover),
		"cover": _applied_cover(board, attacker, target, ignore_cover),
		"flanking": is_flanking(attacker, target),
		"peeking": is_peeking(board, attacker, target),
	}


# --- Reactions ---------------------------------------------------------------

## Does a reaction shot that CONNECTS stop the unit it hit?
##
## Yes. The advance ends on the cell the round found, and the activation ends
## with it: no walking the rest of the path, and no shot at the end of it. A
## soldier who has just been hit is not finishing the thought he was having.
##
## A MISS does nothing, and that asymmetry is the whole texture of the rule.
## Overwatch is not a wall, it is a bet: the watcher spends a turn to buy a
## chance, and the dice decide whether the advance dies on the wire or walks
## through it. Making a miss interrupt would turn a covered lane into a hard
## barrier and end the game's only real reason to accept a risky crossing.
##
## Symmetrical by construction, because it is asked about a hit rather than
## about a team. A goblin caught crossing a scout's lane stops where a scout
## caught crossing a goblin's does.
##
## This lives here as a rule rather than as an `if hit` inside the movement
## loop for the reason everything else in this file does: it is a rule, it
## decides what a turn is worth, and somebody tuning the game should find it by
## reading rather than by grepping the controller for `overwatch`.
static func reaction_interrupts(hit: bool) -> bool:
	return hit


## Every cell a unit on overwatch covers from `sector`: inside its reaction
## reach, inside the watched arc, walkable, and in line of sight. One rule,
## three askers - the overlay paints exactly this, the AI routes against
## exactly this, and the cells a step actually triggers on are these - so the
## cone the player reads and the cone the Thirst avoids can never drift apart.
static func overwatch_cells(board: Board, unit: Unit, sector: int) -> Dictionary:
	var cells := {}
	var r := unit.overwatch_range()  # the gunner watches further than he shoots
	for dy in range(-r, r + 1):
		var w := r - absi(dy)
		for dx in range(-w, w + 1):
			var cell: Vector2i = unit.cell + Vector2i(dx, dy)
			if cell == unit.cell or not board.in_bounds(cell) or not board.is_walkable(cell):
				continue
			var to_cell := Board.sector_from_to(unit.cell, cell)
			if absi(wrapi(to_cell - sector + 4, 0, 8) - 4) > unit.arc_half:
				continue
			if board.has_line_of_sight(unit.cell, cell):
				cells[cell] = true
	return cells


# --- Thrown ordnance ----------------------------------------------------------

## How far a soldier can put a grenade, in tiles, before line of sight is
## consulted.
##
## Everyone throws it by arm. Essa Vane does not: her rifle carries a launcher
## under the barrel, which is drawn on every one of her eight facings, and a
## launched round goes a tile further than a thrown one. That is the whole
## rule, and it covers smoke as well as frag - it is one launcher, and screening
## a crossing from further back is as much of her job as breaking up a cluster.
##
## FIVE, and the tile it sits on is the Thirst's longest reach rather than the
## squad's. That distinction is the whole of the balance and it is easy to get
## backwards: comparing the launcher to Rodar's six-tile battle rifle looks like
## parity and is not, because his six rolls to hit and is halved by cover while
## a frag does neither. The number that decides whether a grenade is FREE is how
## far the enemy can answer, and the longest weapon the Thirst owns is the
## Marksman's bolt rifle at five.
##
## So five is the last tile from which she still has to stand on his line. Six
## would have been the first from which she never does - and against everything
## else on the board those two tiles are worth nothing, because every mobile
## goblin threatens seven or eight (move plus weapon) and both numbers sit well
## inside that. The Marksman is the exception only because reloading costs his
## move and his magazine holds one, so once he starts firing he is rooted at
## exactly five.
##
## Measured before it was chosen: at six, every one of the seven shipped maps
## offers cells with line of sight to the Marksman's post at range six and
## outside his own five - between three and ten of them per map. At five there
## are none, on any map, by construction. Six does not make her better at
## grenades; it makes her immune to the one enemy the campaign builds toward,
## whom README answers with smoke and broken line of sight.
##
## What keeps the rest honest is not the tile count anyway. Frags carry no hit
## roll and ignore cover, so the real levers are the pool - TWO for an entire
## battle, three with her perk, shared by the whole squad - and the line of
## sight every throw still needs.
##
## Takes the raw Kind ordinal for the same two reasons never_breaks() does: it
## keeps Unit out of this file's signatures, and saves speak in ordinals anyway.
const THROW_RANGE := 4
const LAUNCHER_RANGE := 5
const KIND_GRENADIER := 10

static func throw_range(kind: int) -> int:
	return LAUNCHER_RANGE if kind == KIND_GRENADIER else THROW_RANGE


## True where a kind puts ordnance further than an arm can throw it, for the
## places that want to say so rather than compare two numbers.
static func has_launcher(kind: int) -> bool:
	return throw_range(kind) > THROW_RANGE


# --- Morale ------------------------------------------------------------------
#
# There was no morale in this game. Suppression is a pin, not a fear: it costs
# accuracy and movement and expires on a counter, and a suppressed goblin has
# never once considered leaving. Everything below is new, and it is written the
# way the shooting rules are - as arithmetic over plain numbers, with no Unit
# in any signature - so tools/test_rules.gd can pin it without a scene.
#
# Morale is the enemy's only. The squad is five volunteers and a conscript with
# a campaign behind them; the Thirst is a levy fighting forty miles from a well
# that stopped being theirs eleven days ago. Giving both sides the same meter
# would say they are the same kind of formation, and they are not.

const MORALE_MAX := 100
## At or below this a unit breaks. Which of the two ways it breaks is
## `breaks_to_surrender` below, and that is decided by the squad, not the unit.
const MORALE_BREAK := 30

## Taking a round. Flat, because a graze that misses the bone still arrives at
## the same speed as one that does not.
const MORALE_HIT := 15
## Additionally, once the round leaves the unit on half its HP or less. This is
## the wound rather than the noise, and it is deliberately the largest single
## term: a hurt soldier a long way from home is the case morale exists for.
const MORALE_WOUNDED := 25
## Watching somebody die within this many tiles.
const MORALE_ALLY_DOWN := 12
const MORALE_WITNESS := 4
## Being under a beaten zone, charged once per turn it is still pinned.
const MORALE_SUPPRESSED := 20
## Given back at the top of the unit's turn when nothing happened to it. Small
## on purpose: it lets a lull un-break a unit that was never really committed,
## and never outruns a squad that keeps up the pressure.
const MORALE_RECOVER := 5

## How many of your soldiers must have a shot on a broken unit before it has
## somebody to surrender TO. Below this it runs instead, because a man alone in
## the open with nobody covering him has no way to give up safely and every
## reason to think the offer will not be heard.
const MORALE_SURRENDER_GUNS := 2


## What a fighter starts a battle holding, by Kind.
##
## Everyone used to start at MORALE_MAX, and the arithmetic made that a rule
## that only the healthy could ever break. Losing 70 takes a wounding round
## (40) plus most of a squad going down beside you - and the two classes least
## able to stand a fight are the two least able to reach it. A conscript has 2
## HP: the only round he survives is one already halved by cover, and that one
## round is the entire 40 he will ever be charged, because the next kills him.
## A light runner at 3 HP is barely better. The men the fiction describes as
## least willing to be there were the men who could not break.
##
## So they do not all arrive at 100. This is the supply reading the README
## already gives, made mechanical: a well-hand is fighting where he used to draw
## water and stands at full; a runner is lighter in every sense; and a pressed
## conscript, handed a worn-out sidearm last week with no training to speak of,
## starts most of the way to running and breaks the first time he is really hurt.
## The Marksman's number is irrelevant - never_breaks() answers before this does
## - but it is written at full because he was trained rather than pressed.
const MORALE_WELL_HAND := 100
const MORALE_RUNNER := 85
const MORALE_LIGHT_RUNNER := 75
const MORALE_CONSCRIPT := 60

const KIND_GOBLIN := 3
const KIND_GOBLIN_SMG := 4
const KIND_GOBLIN_SMG_ALT := 5
const KIND_GOBLIN_REVOLVER := 6

## Unit.gd spells these per kind in its own stat blocks - it cannot name this
## file - so tools/test_rules.gd asserts the two agree for every Kind. Anything
## not listed starts at MORALE_MAX, which is every soldier in the squad, whose
## morale is never asked about at all.
static func starting_morale(kind: int) -> int:
	match kind:
		KIND_GOBLIN:
			return MORALE_WELL_HAND
		KIND_GOBLIN_SMG:
			return MORALE_RUNNER
		KIND_GOBLIN_SMG_ALT:
			return MORALE_LIGHT_RUNNER
		KIND_GOBLIN_REVOLVER:
			return MORALE_CONSCRIPT
	return MORALE_MAX


## A fighter who ran, and came back anyway.
##
## He is steadier than he was, and the reasoning is not sentiment: he is not a
## levy who was marched here, he is a man who walked back to a fight he had
## already left. So he starts at full whatever he started at last time, and he
## carries the same resistance the Marksman does to the small stuff - watching
## somebody die near him no longer moves him.
##
## What this buys the game is a price on mercy. Shooting a routing man costs
## Standing (see Conduct below), so letting him go is the decent choice and was
## also the free one. Now it is decent and expensive, which is the shape a
## dilemma has. It never forces the player's hand - Standing and Strain still
## push the other way - it just stops the answer being obvious.
const RETURNER_MORALE := MORALE_MAX

static func returner_morale(_kind: int) -> int:
	return RETURNER_MORALE


# --- Left for dead ------------------------------------------------------------
#
# Most of the people the squad shoots down are dead. Some of them are not, and
# which is which is the difference between a war with a cast and a war with a
# body count. A fighter who gets up again keeps his name, and the next time the
# squad meets him they meet somebody who has met them.

## How likely a defeated fighter is to be found breathing, given how many times
## he has already walked away from this squad.
##
## The first time, one in six. After that it climbs, because the ones who keep
## surviving are not a random sample - they are the ones who know how this goes,
## and they get better at it. The cap is what stops a nemesis becoming a joke:
## past SURVIVE_CAP he is hard to finish, never impossible.
const SURVIVE_BASE := 18
const SURVIVE_STEP := 12
const SURVIVE_CAP := 60

static func survive_chance(survivals: int) -> int:
	return mini(SURVIVE_BASE + SURVIVE_STEP * maxi(survivals, 0), SURVIVE_CAP)


## Was that blow decisive enough that there is no question?
##
## A hit that would have killed him from FULL health leaves nobody to find. This
## is the player's lever, and it is why the rule reads on max_hp rather than on
## overkill: almost every weapon in the game does exactly 2, and enemy HP runs
## 2-4, so overkill past what was left is nearly always zero and a rule built on
## it would never fire. Read this way it says something the player can act on -
## Rodar's battle rifle and Sillae's scope (4) settle anything, a frag (3)
## settles a runner or a conscript, and a carbine finishing a wounded man is
## exactly the case where somebody crawls off. Cover halves damage, so a shot
## through a wall stops being decisive, which is correct: it was a worse shot.
static func decisive_blow(amount: int, max_hp: int) -> bool:
	return amount >= max_hp


## What a fighter who was left for dead brings back, having been patched up in a
## settlement with no doctor and every reason to send him out again.
##
## Down a point of health per wound and a long way down on nerve - the opposite
## of the man who merely ran, who comes back whole and steadier. That contrast
## is the whole read: one of them chose to return and one of them was sent, and
## the player can tell which at a glance from the health bar.
##
## It also self-limits. Survival makes him harder to put down for good and
## weaker every time he does it, so a four-time veteran is a wretch who will not
## die rather than a boss who cannot be hurt. The floor is 1: there is always a
## body to shoot.
const INJURY_HP_COST := 1
const INJURY_MORALE_COST := 20

static func injured_hp(max_hp: int, injuries: int) -> int:
	return maxi(max_hp - INJURY_HP_COST * maxi(injuries, 0), 1)


## Never starts below breaking - a fighter who arrives already broken would rout
## on his first activation, which is not a comeback, it is a cutscene.
static func injured_morale(kind: int, injuries: int) -> int:
	var start := starting_morale(kind) - INJURY_MORALE_COST * maxi(injuries, 0)
	return maxi(start, MORALE_BREAK + 1)


## Does watching an ally fall still move this fighter? Not if he has already
## walked away from one fight and chosen to come back to another.
static func shaken_by_the_fallen(returned: bool) -> bool:
	return not returned


## What a round does to the morale of the soldier who took it. `hp_left` is
## after the damage, so a round that kills is never asked about.
static func morale_after_round(morale: int, hp_left: int, max_hp: int) -> int:
	var out := morale - MORALE_HIT
	# Integer halving, matching the cover rule's `>>` - "half or less" is one
	# comparison in a game where every max_hp is small and mostly even.
	if hp_left <= max_hp >> 1:
		out -= MORALE_WOUNDED
	return maxi(out, 0)


## Watching an ally go down `dist` tiles away. Outside MORALE_WITNESS the unit
## did not see it happen and pays nothing.
static func morale_after_ally_down(morale: int, dist: int) -> int:
	if dist > MORALE_WITNESS:
		return morale
	return maxi(morale - MORALE_ALLY_DOWN, 0)


## Charged once per turn the unit begins still pinned.
static func morale_after_suppression(morale: int) -> int:
	return maxi(morale - MORALE_SUPPRESSED, 0)


## A quiet turn.
##
## `ceiling` is the unit's OWN starting morale, not MORALE_MAX, and that
## distinction is the whole of whether starting_morale() means anything. Capped
## at 100 instead, a conscript who starts at 60 is at 65 before his first
## decision point and back at 100 by the eighth quiet turn - so the class trait
## decays into the old flat rule and the two kinds this exists for stop being
## breakable again. A man does not get braver than he arrived; he gets his
## breath back.
static func morale_recovered(morale: int, ceiling := MORALE_MAX) -> int:
	return mini(morale + MORALE_RECOVER, mini(ceiling, MORALE_MAX))


## Has this unit stopped fighting? Says nothing about which way - see below.
static func is_broken(morale: int) -> bool:
	return morale <= MORALE_BREAK


## Some of them do not break, and the game needs that to be true of at least one
## class on every map that asks the squad to clear it. Otherwise a player who
## plays well enough could finish a combat mission having killed nobody, and the
## game would be telling him restraint is always available - which is the exact
## lie the Codex's counterweight mission exists to prevent. (The Codex is the
## Veil canon repo this game's fiction answers to - see docs/CANON.md.)
##
## It is the Marksman, and the reason is already in his stat line rather than
## bolted onto it. He is the only one of them who was trained rather than
## pressed, and the bolt roots him: he reloads after every round, reloading
## costs the move, so he has never been able to leave a firefight he is winning.
## "He does not run" is a description of a unit that already cannot.
##
## Takes the raw Kind ordinal rather than a Unit, both to keep this file's
## no-Unit-in-signatures habit and because saves speak in ordinals anyway.
const KIND_GOBLIN_BOLT := 7

static func never_breaks(kind: int) -> bool:
	return kind == KIND_GOBLIN_BOLT


## A broken unit surrenders when somebody is there to take it and runs when
## nobody is. `guns` is how many living soldiers currently have a shot on it.
##
## The two are exhaustive and mutually exclusive over a broken unit, which is
## what lets the controller ask one question and get an action rather than
## asking two and reconciling them.
## `holds` is the ground rather than the man: some maps are defended by people
## who have been told how it ends and believe it, and on those nobody breaks
## whatever his morale says. THE SURVEY CAMP's briefing states this outright -
## "Fighters in that bowl will not break... they are not staying because they
## are brave" - and it was prose with nothing behind it until starting_morale()
## made three of its thirteen defenders breakable on the first round. A shipped
## claim about how the world works is a rule; this is where it lives.
## What the district's opinion of the squad is worth at the exact moment a
## man's nerve fails. Standing never touches morale itself - a fighter's
## nerve is his own - it decides what breaking MEANS. Where the squad is
## known to take prisoners and let runners run, surrender is survivable and
## one gun on him is enough to raise his hands to. Where it is known for
## shooting the running and finishing the wounded, no sane man stops moving:
## he breaks to the rim instead, whatever is pointed at him.
##
## Expressed as a shift on the guns a surrender needs rather than as a morale
## term, so the two break outcomes stay exhaustive and mutually exclusive by
## construction at every standing. The thresholds are deliberately wide of
## STANDING_START: a fresh campaign sits in the middle band and the rule is
## invisible until the player has actually built a reputation either way.
const STANDING_TRUSTED := 70
const STANDING_FEARED := 30

static func surrender_guns_needed(standing: int) -> int:
	if standing <= STANDING_FEARED:
		return 99  # nobody puts his hands up to a squad that shoots them
	if standing >= STANDING_TRUSTED:
		return maxi(MORALE_SURRENDER_GUNS - 1, 1)
	return MORALE_SURRENDER_GUNS


static func breaks_to_surrender(kind: int, morale: int, guns: int,
		holds := false, standing := STANDING_START) -> bool:
	if holds or never_breaks(kind) or not is_broken(morale):
		return false
	return guns >= surrender_guns_needed(standing)


static func breaks_to_rout(kind: int, morale: int, guns: int,
		holds := false, standing := STANDING_START) -> bool:
	if holds or never_breaks(kind) or not is_broken(morale):
		return false
	return guns < surrender_guns_needed(standing)


# --- Breaking as a formation --------------------------------------------------
#
# Everything above is a private meter: a fighter is worn down by what happens to
# HIM and to whoever is close enough for him to watch it. That is a man losing
# his nerve, and it is only half of why levies leave. The other half is the unit
# losing its cohesion, and a body of men knows two things about itself that no
# individual term can express - how fast it is dying, and how badly it is
# outnumbered.
#
# So both terms below are charged to EVERY surviving fighter regardless of where
# he is standing. That is the point rather than a simplification: four men going
# down in one exchange is known to the whole formation, and a fighter counting
# two of his own against six rifles does not need line of sight to do it.
#
# Both are charged at most once per fighter per turn, in _resolve_morale, and
# both stack with the private meter rather than replacing it.

## How long a death still counts as "just now", in player turns. Two, so that a
## turn the squad spends reloading does not wipe the memory of the turn before.
const SHOCK_WINDOW := 2
## How many have to go down inside that window before it reads as a collapse
## rather than a firefight. Below this the per-death ally term already covers
## it, and this has to stay silent or a good opening volley would rout the map.
const SHOCK_DEATHS := 3
## Charged per death at or past that floor. Three dead is 16, four is 32, five
## is 48 - which is most of a well-hand's meter and all of a conscript's, and
## that ordering is deliberate: the men least willing to be there leave first.
const MORALE_SHOCK := 16


## The morale cost of the formation's recent losses. Zero until the floor.
static func shock_cost(deaths_in_window: int) -> int:
	if deaths_in_window < SHOCK_DEATHS:
		return 0
	return MORALE_SHOCK * (deaths_in_window - SHOCK_DEATHS + 1)


static func morale_after_shock(morale: int, deaths_in_window: int) -> int:
	return maxi(morale - shock_cost(deaths_in_window), 0)


## "There are three of us left and six of them."
##
## Two conditions, not one, and the pair is what keeps this from firing on the
## opening turn of a map the Thirst outnumbers. A force can be outnumbered two
## to one and still be eleven strong, which is a fight; the same ratio with
## three men left is the end of one.
const OUTNUMBERED_FEW := 3
## Soldiers per surviving fighter before it counts.
const OUTNUMBERED_BY := 2
## Charged every turn the situation holds, so it compounds if they stay.
const MORALE_OUTNUMBERED := 18


static func is_outnumbered(fighters: int, soldiers: int) -> bool:
	if fighters <= 0 or fighters > OUTNUMBERED_FEW:
		return false
	return soldiers >= fighters * OUTNUMBERED_BY


static func morale_after_outnumbered(morale: int, fighters: int,
		soldiers: int) -> int:
	if not is_outnumbered(fighters, soldiers):
		return morale
	return maxi(morale - MORALE_OUTNUMBERED, 0)


# --- Raiders and warbands -----------------------------------------------------
#
# A returning fighter used to come back and fight the mission out like a levy
# who had been standing there all along, which wasted the one thing that makes
# him interesting: he chose to be here. These two shapes give that choice a
# form on the board.

## How often somebody walking back onto a mission has come to raid rather than
## to hold ground - hit the squad once and break contact on his own terms.
const RAID_CHANCE := 40
## How many shots he came to take before leaving.
const RAID_SHOTS := 1

## What a man has to have walked away from before he can gather others: twice.
## Once is luck, and the campaign is full of people who managed it.
const WARBAND_LEADER_SURVIVALS := 2
## And what the people he gathers need. Once - they are followers, not peers.
const WARBAND_MEMBER_SURVIVALS := 1
## Leader plus three. Four is a fireteam and reads as one on the board; three
## reads as stragglers and five swamps a sixteen-by-ten map.
const WARBAND_SIZE := 4

## A warband holds together while the man who gathered it is alive. This is the
## extra his people recover at the top of their turn, on top of MORALE_RECOVER.
const MORALE_WARBAND_STEADY := 7
## And what it costs them, all at once, when he goes down. Deliberately larger
## than a wound: the reason they are on this map is that HE came back, and the
## rest of them have no such argument with this squad.
const MORALE_LEADER_DOWN := 30


static func morale_after_leader_down(morale: int) -> int:
	return maxi(morale - MORALE_LEADER_DOWN, 0)


## Recovery for a fighter whose warband leader is still standing.
static func morale_recovered_led(morale: int, ceiling := MORALE_MAX) -> int:
	return mini(morale + MORALE_RECOVER + MORALE_WARBAND_STEADY,
			mini(ceiling, MORALE_MAX))


## Whether a record has walked away from enough missions to gather a warband.
## Takes the plain count rather than a record so the harness can pin it.
static func can_lead_warband(survivals: int) -> bool:
	return survivals >= WARBAND_LEADER_SURVIVALS


static func can_join_warband(survivals: int) -> bool:
	return survivals >= WARBAND_MEMBER_SURVIVALS


# --- Conduct, Standing, and Strain -------------------------------------------
#
# The after-action has two panels that are never summed. THE OPERATION is
# graded and killing armed men is how it is earned; THE ROLL is reported and
# never ranked. These are the numbers behind the second panel, and the first
# rule of them is the one that is easiest to get wrong:
#
#   Killing an armed, fighting combatant costs NOTHING. Not Standing, not
#   Strain, not the rating. A hard-fought firefight can be a perfect operation.
#
# Everything that does cost is a CHOSEN act - something the player did that he
# had the option not to do, with a soldier who was no longer fighting or was
# never fighting at all. That distinction is the whole design, so it is spelled
# as data below rather than as branches somewhere in the controller.

enum Conduct {
	## The baseline, and the one that is free. Named rather than left implicit
	## so the zero is visible in the table instead of being an absence.
	COMBATANT_KILLED,
	## Firing on a unit that had already stopped: running, hands up, or down.
	ROUTING_FIRED_ON,
	SURRENDERED_FIRED_ON,
	WOUNDED_FIRED_ON,
	## A civilian killed by anyone on the squad's side, by round or by blast.
	CIVILIAN_KILLED,
	## Water, homes, and aid. Destroying a well is the one act in the game that
	## does what the Charter dispute is about.
	WELL_DESTROYED,
	HOME_DESTROYED,
	AID_DESTROYED,
	## Leaving their dead where they fell when the squad could have allowed
	## them to be collected.
	DEAD_LEFT,
}

## Standing is per settlement and Strain is theater-wide, so an act can cost
## one, both, or - for a clean kill - neither. Read as {Conduct: [standing, strain]}.
##
## Reconciling two lines of the plan that pull against each other: Strain is
## described as driven "only by Crown-attributed goblin deaths", and separately
## a clean combat kill is required to cost zero. Both hold at once only if the
## deaths that drive Strain are the ones the district counts as something other
## than a battle - the routing, the surrendered, the wounded, the bystanders.
## That is what this table says, and it is why COMBATANT_KILLED is 0/0.
const CONDUCT_COST := {
	Conduct.COMBATANT_KILLED: [0, 0],
	Conduct.ROUTING_FIRED_ON: [8, 5],
	Conduct.SURRENDERED_FIRED_ON: [15, 10],
	Conduct.WOUNDED_FIRED_ON: [6, 4],
	Conduct.CIVILIAN_KILLED: [20, 12],
	Conduct.WELL_DESTROYED: [25, 15],
	Conduct.HOME_DESTROYED: [12, 8],
	Conduct.AID_DESTROYED: [12, 8],
	Conduct.DEAD_LEFT: [5, 3],
}

## Standing runs 0..100 per settlement and starts here: they have met the Crown
## before and it went the way it went.
const STANDING_START := 50
const STANDING_MAX := 100

## Strain runs 0..100 theater-wide, and never reaches 0.
const STRAIN_MAX := 100
## The floor, and the most important number in this section. Strain cannot be
## cleared by conduct, ever, because none of it is about conduct: an Accord
## counterinsurgency is standing on ground whose Assembly filed an objection,
## and the best-behaved squad in the theater does not make that untrue. A player
## who reaches zero has found a bug in the theme, which is why the clamp is a
## rule with an assertion rather than a `maxi` somewhere in Game.gd.
const STRAIN_FLOOR := 1
## Where a campaign opens - above the floor, so good conduct has somewhere to go.
const STRAIN_START := 12

## Given back per mission completed without a conduct entry against it. Strain
## decays toward the floor and never through it.
const STRAIN_DECAY := 3


static func standing_cost(conduct: Conduct) -> int:
	return int(CONDUCT_COST[conduct][0])


static func strain_cost(conduct: Conduct) -> int:
	return int(CONDUCT_COST[conduct][1])


## Standing after an act. Clamped both ends; a settlement's opinion is bounded.
static func standing_after(standing: int, conduct: Conduct) -> int:
	return clampi(standing - standing_cost(conduct), 0, STANDING_MAX)


## Strain after an act. The floor is applied here and nowhere else, so there is
## one place capable of getting it wrong.
static func strain_after(strain: int, conduct: Conduct) -> int:
	return clampi(strain + strain_cost(conduct), STRAIN_FLOOR, STRAIN_MAX)


## A clean mission, which walks Strain back down toward - never through - the
## floor.
static func strain_decayed(strain: int) -> int:
	return clampi(strain - STRAIN_DECAY, STRAIN_FLOOR, STRAIN_MAX)
