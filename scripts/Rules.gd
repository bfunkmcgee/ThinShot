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
const SUPPRESSION_ACCURACY := 25  # to-hit penalty while pinned down
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
	if attacker.is_suppressed():
		chance -= SUPPRESSION_ACCURACY
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
	return clampi(chance, MIN_HIT_CHANCE, MAX_HIT_CHANCE)


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


## A quiet turn. Never past MORALE_MAX, so a unit cannot bank calm.
static func morale_recovered(morale: int) -> int:
	return mini(morale + MORALE_RECOVER, MORALE_MAX)


## Has this unit stopped fighting? Says nothing about which way - see below.
static func is_broken(morale: int) -> bool:
	return morale <= MORALE_BREAK


## Some of them do not break, and the game needs that to be true of at least one
## class on every map that asks the squad to clear it. Otherwise a player who
## plays well enough could finish a combat mission having killed nobody, and the
## game would be telling him restraint is always available - which is the exact
## lie the Codex's counterweight mission exists to prevent.
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
static func breaks_to_surrender(kind: int, morale: int, guns: int) -> bool:
	if never_breaks(kind) or not is_broken(morale):
		return false
	return guns >= MORALE_SURRENDER_GUNS


static func breaks_to_rout(kind: int, morale: int, guns: int) -> bool:
	if never_breaks(kind) or not is_broken(morale):
		return false
	return guns < MORALE_SURRENDER_GUNS


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
