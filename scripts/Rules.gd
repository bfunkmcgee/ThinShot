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
static func effective_cover(board: Board, attacker: Unit, target: Unit) -> Board.CoverLevel:
	if is_flanking(attacker, target):
		return Board.CoverLevel.NONE
	return board.cover_between(attacker.cell, target.cell)


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
