class_name Levels

## Static campaign data.
##
## The campaign is a list of OPERATIONS, each a run of missions the squad flies
## out for and stays out on. Between missions inside an operation they camp in
## the field; between operations they come back to the garrison, where the
## dead are finally replaced. An operation names the biome it takes place in,
## which is what the field camp dresses itself from.
##
## LEVELS below is the flat list of every mission in campaign order, which is
## what a mission actually is; OPERATIONS indexes into it. Keeping the two
## separate means the mission data never had to move.
##
## Each level carries an ordered "objectives" list; a level with none defaults
## to wiping out the Choir, which is what the first one does. Objectives are
## completed in order, and the level is won when the last one is:
##   {"kind": "eliminate"}                       - kill every goblin
##   {"kind": "destroy", "cells": [...]}         - demolish every tithe cache
##   {"kind": "rescue"}                          - reach every prisoner
##   {"kind": "extract", "cells": [...]}         - every surviving scout to the
##                                                 zone, and only once every
##                                                 earlier objective is done
## Losing is unchanged and unconditional: the squad dies, you lose.
##
## Each level also carries the campaign's narrative beats:
##   "briefing" - the situation, shown before the first turn
##   "orders"   - the one-line task, shown under the briefing
##   "debrief"  - the payoff, shown on a win; it is what sets up the next
##                mission, so the three read as one story rather than three
##                skirmishes. The arc is deliberately carried by the objective
##                kinds themselves: eliminate (nothing else to be done yet),
##                destroy (the cargo turns out to matter more than the
##                carriers), destroy-then-extract (deny it and withdraw,
##                because the place cannot be held).
##
## Map legend:
##   '.' open sand          '#' rock (blocks move + LOS)
##   'W' mud-brick wall (blocks move + LOS)
##   'p' plant (pure decoration, walkable)
##
##   Half cover - unwalkable, shots pass at half damage. Three glyphs that
##   behave identically and say different things about who was here:
##   'j' rusted junk (nobody put it there)
##   's' sandbags (somebody dug in here)
##   'c' the Choir's stacked ordnance (their ground, not yours). Keep these off
##       any map with a 'destroy' objective - crates you must burn and crates
##       you merely hide behind must not share a board.
##   'd' fuel drum (half cover too, but detonates when caught in a blast)
##
##   '=' barbed wire: stops movement and NOTHING else. Shots and sight cross it
##       freely and it gives cover to nobody. It is the only thing on the board
##       that divides ground without also dividing fire, which is what makes a
##       gate in it worth fighting over.
## Structure footprints overlay their cells as full blockers.

const LEVELS: Array[Dictionary] = [
	{
		# Four rock outcrops pinch the field into three lanes, and a junk
		# island splits the middle one so it cannot be walked straight down.
		# Every lane has a piece of cover to bound between, and each cover
		# piece has open ground on both sides so it can be flanked around.
		# Goblins hold in pairs, one per lane, which is what gives the
		# gunner's suppression something worth pinning.
		"name": "DRY WASH",
		"fiction": "The dry riverbed where the Rust Choir first crossed into scout territory.",
		"briefing": "The Choir has never crossed the wash before. This morning they did - in daylight, in numbers, and they did not stop to loot the crossing.\n\nCommand wants them off scout ground. That is the whole order.",
		"orders": "CLEAR THE WASH",
		"debrief": "They were not raiding.\n\nEvery body on the wash was carrying the same load: scrap, sorted and tallied, bundled for transport. Nobody carries a tally into a raid.\n\nThey were hauling it somewhere, and they were late. Follow the route back.",
		"size": Vector2i(16, 10),
		"map": [
			"..p.##.....##...",
			"....##...p.##...",
			"......j..dd.....",
			"..........j.....",
			".......jj....j..",
			".......jj....j..",
			"...p......j.....",
			"......j.......p.",
			"....##.....##...",
			"....##..p..##...",
		],
		"scout_spawns": [Vector2i(1, 2), Vector2i(1, 7), Vector2i(2, 4)],
		"lead_spawns": [Vector2i(0, 5)],
		"gunner_spawns": [Vector2i(2, 5)],
		"goblin_spawns": [
			Vector2i(13, 1), Vector2i(14, 4), Vector2i(14, 8),
		],
		# Raiders start a lane ahead of the riflemen and come straight on.
		# One per lane, and the southern one is the scrawny variant - open
		# ground is where his extra tile of movement reads clearest.
		"smg_spawns": [Vector2i(12, 3)],
		"smg_alt_spawns": [Vector2i(12, 6)],
		# Novices are pushed out in front of everyone as a screen.
		"novice_spawns": [Vector2i(15, 2), Vector2i(15, 5), Vector2i(15, 7)],
		# The Cantor sits at the back of the middle lane behind the junk
		# island, so he only starts mattering once the squad is most of the
		# way across - the backstop rather than the opening problem.
		"bolt_spawns": [Vector2i(15, 4)],
		"structures": [],
		# Stated rather than left to default, so the banner on screen reads the
		# same words as the orders in the briefing.
		"objectives": [
			{"kind": "eliminate", "label": "CLEAR THE WASH"},
		],
		"zone_seed": 7,
		"shade_seed": 13,
		"zone_thresholds": [-0.12, 0.22],
	},
	{
		# Two scrap barricades in depth. The outer line (x=6) has gates at
		# y=3 and y=7; the inner line (x=11) has gates at y=1 and y=5 -
		# deliberately offset, so breaching the first one leaves you crossing
		# the yard sideways under fire to reach the second. Gate defenders
		# stand in pairs, and the corridor between the lines is the killing
		# ground the machinegunner exists for.
		"name": "THE SCRAPLINE",
		"fiction": "The Choir's scrap-tithe yard - tribute junk sung into rows.",
		"briefing": "The route ends in a yard the Choir calls the Scrapline: rows of tribute stacked and sung over, waiting to move on.\n\nKilling collectors changes nothing. There are always more collectors. The tithe is what matters.\n\nThere is a mast over the yard as well - scrap aerials wired up a pole - and it is how the Scrapline calls the rest of the Choir down on anyone who walks in. Put it down too.",
		"orders": "BURN THE CACHES, DROP THE RELAY",
		"debrief": "The caches were not scrap.\n\nPrimers. Casings. Barrel stock. Machined, not scavenged - and every crate struck with the same depot mark. One of ours, taken off the maps eleven years ago.\n\nThe mast carried it too, stamped into the base plate. They no more built that than they milled the casings.\n\nThe Choir is not scavenging the desert. It is stripping Outpost 7, and arming itself with what we left behind.",
		"size": Vector2i(16, 10),
		# Scrap thins out toward the west rather than stopping dead at the
		# outer barricade: the squad deploys onto ground it can bound through
		# instead of a bare apron, and the board stops reading as a packed
		# right half beside an empty left one.
		"map": [
			".p..j.j..p.j....",
			"..j...j.........",
			"...j..j....j....",
			".j.......d.j....",
			"...j..j..d.j....",
			"....j.j.........",
			".j....j....j....",
			"...j.......j....",
			"..j...j....j....",
			"..p.j.j..p.j....",
		],
		"scout_spawns": [Vector2i(1, 1), Vector2i(1, 8), Vector2i(2, 5)],
		"lead_spawns": [Vector2i(0, 4)],
		"gunner_spawns": [Vector2i(2, 4)],
		"goblin_spawns": [
			Vector2i(7, 3), Vector2i(8, 3),    # north gate
			Vector2i(7, 7), Vector2i(8, 7),    # south gate
		],
		# Raiders wait in the corridor between the barricades, ready to
		# rush whichever gate the scouts commit to. The skirmishers are the
		# ones who can cross it in a single turn, so a second waits deep.
		"smg_spawns": [Vector2i(9, 1)],
		"smg_alt_spawns": [Vector2i(9, 8), Vector2i(12, 2)],
		"novice_spawns": [Vector2i(12, 5), Vector2i(15, 2), Vector2i(15, 7)],
		# Behind the inner barricade with junk at (11,4) to hide behind, five
		# tiles of reach covering the corridor lengthwise. Crossing between
		# the lines now costs something even when the gates are clear.
		"bolt_spawns": [Vector2i(12, 4)],
		"structures": [
			{"kind": "hut_1", "anchor": Vector2i(13, 2), "size": Vector2i(2, 2)},
			{"kind": "tent", "anchor": Vector2i(13, 6), "size": Vector2i(2, 2)},
		],
		# The tithe itself. Three caches spread corner to corner behind the
		# barricades, so clearing the yard is the only way to reach them all -
		# and a body count no longer ends the level. All three sit clear of the
		# hut and tent sprites, which are tall enough to paint over a cell
		# several rows in front of their own footprint.
		"objectives": [
			{
				"kind": "destroy",
				"label": "BURN THE TITHE CACHES",
				"prop": "crates",
				"cells": [Vector2i(15, 1), Vector2i(14, 4), Vector2i(12, 8)],
			},
			# How the yard calls for help. Two charges to put down, and it
			# stands in the open corridor between the barricades, so silencing
			# it means crossing the ground the machinegunner exists to cover.
			{
				"kind": "destroy",
				"label": "SILENCE THE RELAY",
				"prop": "mast",
				"cells": [Vector2i(10, 4)],
			},
		],
		"zone_seed": 21,
		"shade_seed": 34,
		"zone_thresholds": [-0.5, -0.2],
	},
	{
		# A properly sealed compound this time. The fortress is flush to the
		# east edge so there is no walking around the back: the only ways in
		# are the west gate (8,4) and the two south gates (11,7) and (14,7).
		# Three ways in, all covered, and the garrison holds each in pairs.
		# The hamlet and rocks outside give the squad staging cover to set
		# the gun up before anyone steps into a gateway.
		"name": "OUTPOST 7",
		"fiction": "The old desert command, now the Choir's hive. The scouts go in at dawn.",
		"briefing": "Outpost 7 was ours. The Choir lives in it now, and every round it has fired at you came out of our own stores.\n\nTwo ammunition dumps are still standing in there, and they are the reason the Choir is worth anything at all.\n\nYou cannot hold the place. There are not enough of you, and there never were. So you will not try. Go in at dawn, and come back out.",
		"orders": "BLOW THE AMMO DUMPS, THEN EXTRACT",
		"debrief": "The dumps are gone, and with them the only thing that ever made the Choir more than a rabble with knives.\n\nThey will be out there tomorrow. They will still outnumber you. But they will be singing over scrap again - the way they were, before somebody left them a war to find.\n\nTake the squad home.",
		"size": Vector2i(16, 10),
		# Scrap in the staging ground west of the compound, so the squad has
		# something to bound between on the approach instead of crossing bare
		# sand - and so the western half is not visually empty beside a
		# fortress wall.
		"map": [
			".p...j..WWWWWWWW",
			"....j.p.W.......",
			".....#..W.......",
			"...j.#.sW.......",
			"....j...........",
			"......jsW.......",
			"........W...dd..",
			".........WW.WW.W",
			"..j.p.j.........",
			"....j..p........",
		],
		"scout_spawns": [Vector2i(0, 2), Vector2i(1, 8), Vector2i(0, 6)],
		"lead_spawns": [Vector2i(0, 4)],
		"gunner_spawns": [Vector2i(1, 5)],
		"goblin_spawns": [
			Vector2i(9, 3), Vector2i(9, 4),    # west gate
			Vector2i(10, 1),                   # courtyard
			Vector2i(14, 5),                   # fortress door
		],
		# Raiders hold the south gates and counter-attack through them; a
		# skirmisher in the courtyard reaches whichever gateway breaks first.
		"smg_spawns": [Vector2i(10, 6)],
		"smg_alt_spawns": [Vector2i(11, 6), Vector2i(11, 2)],
		"novice_spawns": [Vector2i(10, 2), Vector2i(13, 5), Vector2i(15, 6)],
		# Laid in on the west gate at (8,4) from five tiles back, straight
		# down the entry lane. The gateway is the obvious way in, and this is
		# what makes walking through it the wrong idea.
		"bolt_spawns": [Vector2i(11, 4)],
		"structures": [
			{"kind": "fortress", "anchor": Vector2i(12, 1), "size": Vector2i(4, 4)},
			{"kind": "hut_1", "anchor": Vector2i(2, 1), "size": Vector2i(2, 2)},
			{"kind": "hut_2", "anchor": Vector2i(2, 6), "size": Vector2i(2, 2)},
		],
		# A raid, not a massacre: blow the ammo dumps, then walk everyone back
		# out the way they came in. The extraction zone is the ground the squad
		# started on, so the level ends where it began and the last stretch is
		# a fighting withdrawal.
		# The fortress sprite is 512px square and swallows most of the northern
		# compound, so the western dump sits at (10,4) rather than deeper
		# in - close behind the west-gate defenders and the Cantor, which makes
		# it something to fight toward rather than something to hunt for.
		"objectives": [
			{
				"kind": "destroy",
				"label": "BLOW THE AMMO DUMPS",
				"prop": "crates",
				"cells": [Vector2i(10, 4), Vector2i(14, 6)],
			},
			{
				"kind": "extract",
				"label": "EXTRACT THE SQUAD",
				"cells": [
					Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4),
					Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7),
				],
			},
		],
		# Desert outside the wall, concrete inside it. The inset is the
		# courtyard east of the west wall and north of the south wall, so the
		# staging ground the squad crosses is still open sand and the fortress
		# finally reads as something that was built rather than camped in.
		"floor": "desert",
		# Down to and including the south wall line, so the two south gateways
		# at (11,7) and (14,7) are already concrete underfoot - breaching one
		# puts you on the compound floor rather than on sand inside a wall.
		"floor_inset": {"floor": "compound", "rect": Rect2i(9, 0, 7, 8)},
		"zone_seed": 42,
		"shade_seed": 55,
		"zone_thresholds": [-0.12, 0.22],
	},
	# --- OPERATION SECOND VERSE -------------------------------------------
	{
		# Caught in the open, and that is the whole map: almost no cover, three
		# loads strung out east, and a long walk to reach any of them. The
		# first mission where the cover rules bite by their absence - there is
		# very little to hug and the ground between is bare.
		"name": "THE LONG HAUL",
		"fiction": "Open ground west of the wash, where a Choir column was still walking two days after the outpost burned.",
		"briefing": "You were told the Choir was finished. Here they are in daylight, walking a load west.\n\nThe ammo dumps at Outpost 7 were light when you blew them. This is why. Something went out ahead of the raid, and it is still going.",
		"orders": "BURN THE COLUMN'S LOAD",
		"debrief": "Water.\n\nNot ordnance - drums of water, tallied and roped and hauled by hand across forty miles of nothing.\n\nThe Choir is not arming a war any more. It is supplying something. And whatever it is sits far enough out that a drink is worth a column.",
		"size": Vector2i(16, 10),
		"map": [
			"..p......j......",
			".....j..........",
			"...........j....",
			"..j.............",
			"......dd........",
			".#..........j...",
			".........dd.....",
			"....j...........",
			"..........j.....",
			"...p.......j....",
		],
		"scout_spawns": [Vector2i(1, 2), Vector2i(1, 7), Vector2i(2, 4)],
		"lead_spawns": [Vector2i(0, 5)],
		"gunner_spawns": [Vector2i(2, 5)],
		# The column is strung out rather than dug in - they were walking, not
		# waiting - so they arrive at the fight in ones and twos.
		"goblin_spawns": [
			Vector2i(12, 1), Vector2i(13, 4), Vector2i(12, 7), Vector2i(14, 2),
		],
		"smg_spawns": [Vector2i(11, 5)],
		"smg_alt_spawns": [Vector2i(11, 3), Vector2i(13, 6)],
		"novice_spawns": [Vector2i(15, 1), Vector2i(15, 5), Vector2i(15, 8)],
		"bolt_spawns": [Vector2i(14, 7)],
		"structures": [],
		"objectives": [
			{
				"kind": "destroy",
				"label": "BURN THE COLUMN'S LOAD",
				"prop": "crates",
				"cells": [Vector2i(13, 2), Vector2i(12, 4), Vector2i(13, 8)],
			},
		],
		# The mission whose point is bare ground with nothing to hug, walked
		# across forty miles of nothing - so it is fought on the salt pan.
		"floor": "salt",
		"zone_seed": 5,
		"shade_seed": 61,
		"zone_thresholds": [-0.20, 0.18],
	},
	{
		# A breakthrough, which no mission has asked for yet. The cistern wall
		# runs the height of the map with two gaps, the extraction zone is the
		# far edge, and there is nothing to destroy - the only way to finish is
		# to get the whole squad through and out the other side.
		"name": "THE CISTERN",
		"fiction": "A walled water point on the old survey line, and the only way east for a day in either direction.",
		"briefing": "The column's tallies all name the same place: a cistern on the survey line, walled and held.\n\nIt is the only water east of here, which is why they hold it and why you cannot go around it.\n\nGet the squad through. Do not stop to take it - you could not hold it either.",
		"orders": "BREAK THROUGH TO THE EAST",
		"debrief": "Past the cistern the tracks stop scattering.\n\nEvery path east of the water runs together into one, beaten flat and wide by more feet than the Choir has ever put in one place.\n\nSomething is gathering them. Follow it in.",
		"size": Vector2i(16, 10),
		"map": [
			"..p...WWW.......",
			"......W...j.....",
			"...j..W..c......",
			".....sW....j....",
			"..........dd....",
			".....sW.........",
			"...j..W....j....",
			"......W.........",
			"..p...WWW..j....",
			"...........p....",
		],
		"scout_spawns": [Vector2i(1, 2), Vector2i(1, 7), Vector2i(2, 4)],
		"lead_spawns": [Vector2i(0, 5)],
		"gunner_spawns": [Vector2i(2, 5)],
		# Held at the two gaps in the wall - y4 through the middle, y9 around
		# the southern end - with the rest waiting in the ground beyond.
		"goblin_spawns": [
			Vector2i(7, 3), Vector2i(7, 5), Vector2i(9, 1), Vector2i(9, 8),
			Vector2i(12, 1),
		],
		"smg_spawns": [Vector2i(8, 4)],
		"smg_alt_spawns": [Vector2i(10, 2), Vector2i(10, 6)],
		"novice_spawns": [Vector2i(13, 3), Vector2i(13, 6), Vector2i(12, 9)],
		"bolt_spawns": [Vector2i(14, 4)],
		"structures": [
			{"kind": "hut_1", "anchor": Vector2i(13, 0), "size": Vector2i(2, 2)},
		],
		# No caches, no killing quota: the whole objective is the far edge, so
		# the squad has to be pushed through rather than fought to a standstill.
		"objectives": [
			{
				"kind": "extract",
				"label": "GET THE SQUAD THROUGH",
				"cells": [
					Vector2i(15, 2), Vector2i(15, 3), Vector2i(15, 4),
					Vector2i(15, 5), Vector2i(15, 6), Vector2i(15, 7),
				],
			},
		],
		# Still on the salt, one day further east: the cistern is the only
		# water on the survey line, and a dried pan is why that is true.
		"floor": "salt",
		"zone_seed": 28,
		"shade_seed": 12,
		"zone_thresholds": [-0.40, 0.05],
	},
	{
		# The rescue. Two objectives that pull in opposite directions: the
		# prisoners are held deep east, the way out is the west edge you came
		# in by, and a freed prisoner walks at move 4 with no weapon. So the
		# mission is a long reach followed by a longer walk back, with the
		# squad's own guns as the only thing making that walk survivable.
		"name": "THE HOLDING PENS",
		"fiction": "A wire pen behind the Choir's line, and the reason they have been hauling water across forty miles of nothing.",
		"briefing": "The water was not for them.\n\nBehind the Choir's line there is a pen, and in it are the people they have been keeping alive - surveyors off the old line, by the look of the tallies.\n\nThat is what the column was for. Go and get them.\n\nThe pen is wire. You will see them long before you reach them and every gun in there will see you coming - wire stops a boot and nothing else. There is one gate, and they have dug in behind it.\n\nA freed prisoner has no weapon and cannot be shot at, but they walk at their own pace and they walk the whole way back out through that same gate. Reaching them is the easy half.",
		"orders": "REACH THE PRISONERS, THEN WALK THEM OUT",
		"debrief": "Surveyors. Taken off the line eleven years ago, when Outpost 7 came off the maps, and kept alive ever since because somebody down there wanted the maps in their heads.\n\nThey knew where every dump and cistern on the survey line was. That is how the Choir found them all.\n\nAnd they say the one who asked the questions is still out there, at the end of the tracks.",
		"size": Vector2i(16, 10),
		# The pen is wire, not wall, and that is the whole map. You can see
		# the prisoners from the start line and shoot the guards through the
		# fence without setting foot inside - but the only way through is the
		# gate at (10,4), and it is dug in behind sandbags. Prep by fire,
		# breach, then come back out the same hole carrying people.
		"map": [
			"..p.......======",
			".....j....=.....",
			"...j......=..c..",
			".......js.=.....",
			"....dd..........",
			"...j....s.=.....",
			".........j=...c.",
			"......j...=.....",
			"...p......======",
			".....j..........",
		],
		"scout_spawns": [Vector2i(1, 2), Vector2i(1, 7), Vector2i(2, 4)],
		"lead_spawns": [Vector2i(0, 5)],
		"gunner_spawns": [Vector2i(2, 5)],
		# The pen is behind a wire line with one way through, at (10,4).
		"prisoner_spawns": [Vector2i(13, 3), Vector2i(13, 6)],
		"goblin_spawns": [
			Vector2i(9, 2), Vector2i(9, 5), Vector2i(11, 1), Vector2i(11, 7),
		],
		# The one way through the wire is (10,4), and it is held.
		"smg_spawns": [Vector2i(10, 4)],
		"smg_alt_spawns": [Vector2i(8, 4), Vector2i(12, 5)],
		"novice_spawns": [Vector2i(15, 1), Vector2i(15, 7), Vector2i(14, 4)],
		"bolt_spawns": [Vector2i(12, 2)],
		"structures": [
			{"kind": "tent", "anchor": Vector2i(6, 1), "size": Vector2i(2, 2)},
		],
		"objectives": [
			{"kind": "rescue", "label": "REACH THE PRISONERS"},
			{
				"kind": "extract",
				"label": "WALK THEM OUT",
				"cells": [
					Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4),
					Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7),
					Vector2i(1, 4), Vector2i(1, 5),
				],
			},
		],
		"zone_seed": 66,
		"shade_seed": 40,
		"zone_thresholds": [-0.25, 0.14],
	},
	{
		# A bowl in the rock with cover through the middle of it, and the whole
		# Choir standing in it. Back to elimination, which is the point: the
		# first operation taught that killing them changed nothing, and this is
		# the one time it does.
		"name": "THE CHOIRMASTER",
		"fiction": "Where every track east of the cistern ends, and the singing is loudest.",
		"briefing": "The tracks end in a bowl in the rock, and the Choir is in it. All of it, and more of it than you have seen in one place.\n\nThey did not gather themselves. Somebody down there is keeping them, and while they are kept there will always be another column.\n\nNo caches this time. No withdrawal. Finish it.",
		"orders": "LEAVE NOBODY SINGING",
		"debrief": "It is over, and it is quiet, and there is nothing left down there to sing.\n\nWhoever held them together held them here, and held them to the last one. The Choir will be scavengers again by the next dry season - scattered, starving, and nobody's army.\n\nBring the squad home.",
		"size": Vector2i(16, 10),
		"map": [
			"....##......##..",
			"...#....j....#..",
			".......j........",
			"..j...c...j.....",
			".....dd.....j...",
			"........j.......",
			"...j.......dd...",
			"......j..c......",
			"...#....j....#..",
			"....##......##..",
		],
		"scout_spawns": [Vector2i(1, 2), Vector2i(1, 7), Vector2i(2, 4)],
		"lead_spawns": [Vector2i(0, 5)],
		"gunner_spawns": [Vector2i(2, 5)],
		# The largest force in the campaign, and the only one that does not
		# have somewhere else to be.
		"goblin_spawns": [
			Vector2i(11, 1), Vector2i(12, 3), Vector2i(11, 7), Vector2i(12, 5),
			Vector2i(10, 2),
		],
		"smg_spawns": [Vector2i(9, 4), Vector2i(9, 6)],
		"smg_alt_spawns": [Vector2i(10, 5), Vector2i(13, 4)],
		"novice_spawns": [Vector2i(14, 2), Vector2i(14, 6), Vector2i(15, 4)],
		"bolt_spawns": [Vector2i(14, 8)],
		"structures": [
			{"kind": "tent", "anchor": Vector2i(10, 8), "size": Vector2i(2, 2)},
		],
		"objectives": [
			{"kind": "eliminate", "label": "LEAVE NOBODY SINGING"},
		],
		# The end of every track, and the one map that is not desert or pan:
		# burnt ground, because the Choir has been gathering and burning here
		# long enough to leave the bowl black.
		"floor": "ash",
		"zone_seed": 77,
		"shade_seed": 34,
		"zone_thresholds": [-0.05, 0.30],
	},
]

## The operations the campaign is made of. `missions` are indices into LEVELS,
## so mission data stays exactly where it was. `biome` is what the field camp
## between those missions dresses itself as, and each one now names its own
## floor tilesheet in BIOMES.
const OPERATIONS: Array[Dictionary] = [
	{
		"name": "OPERATION DRY CHOIR",
		"biome": "desert",
		"summary": "Push the Rust Choir back off scout ground, and find out what they are carrying.",
		"missions": [0, 1, 2],
	},
	{
		"name": "OPERATION SECOND VERSE",
		"biome": "desert",
		"summary": "The ammo dumps at Outpost 7 were already light. Find out who took the rest.",
		# Four rather than three: the rescue sits between the cistern and the
		# gathering, because the water the column was hauling only makes sense
		# once you find who it was being hauled to.
		"missions": [3, 4, 5, 6],
	},
]

## Biome dressing for the field camp. One entry per biome an operation can
## name; `floor` is the tilesheet in Board.FLOOR_SHEETS the camp stands on.
const BIOMES := {
	"desert": {
		"label": "DESERT",
		"floor": "desert",
		"floor_seed": 91,
		"shade_seed": 17,
		"thresholds": [-0.30, 0.10],
	},
	"salt": {
		"label": "SALT FLAT",
		"floor": "salt",
		"floor_seed": 44,
		"shade_seed": 8,
		"thresholds": [-0.55, -0.15],
	},
	"ash": {
		"label": "ASH",
		"floor": "ash",
		"floor_seed": 63,
		"shade_seed": 29,
		"thresholds": [0.05, 0.35],
	},
}

const LEGAL_CHARS := ".#Wjpdsc="


## Validates every level. push_error-based so it also reports in release
## builds (asserts are stripped there); debug builds additionally hard-stop.
static func validate_all() -> void:
	var ok := true
	for i in LEVELS.size():
		ok = _validate(i) and ok
	assert(ok, "Level data invalid - see errors above")


static func _check(cond: bool, msg: String) -> bool:
	if not cond:
		push_error("[Levels] " + msg)
	return cond


static func _footprint_cells(data: Dictionary) -> Dictionary:
	var cells := {}
	for s: Dictionary in data.structures:
		var anchor: Vector2i = s.anchor
		var size: Vector2i = s.size
		for dy in size.y:
			for dx in size.x:
				cells[anchor + Vector2i(dx, dy)] = true
	return cells


static func _validate(index: int) -> bool:
	var data: Dictionary = LEVELS[index]
	var label: String = "Level %d '%s'" % [index + 1, data.name]
	var grid: Vector2i = data.size
	var ok := _check(data.map.size() == grid.y, "%s: map must have %d rows" % [label, grid.y])
	if not ok:
		return false  # row checks below would misindex
	for row: String in data.map:
		ok = _check(row.length() == grid.x, "%s: row '%s' wrong length" % [label, row]) and ok
		for ch in row:
			ok = _check(LEGAL_CHARS.contains(ch), "%s: illegal char '%s'" % [label, ch]) and ok
	if not ok:
		return false
	var footprints := _footprint_cells(data)
	var seen_footprint := {}
	for s: Dictionary in data.structures:
		var anchor: Vector2i = s.anchor
		var struct_size: Vector2i = s.size
		for dy in struct_size.y:
			for dx in struct_size.x:
				var cell: Vector2i = anchor + Vector2i(dx, dy)
				ok = _check(cell.x >= 0 and cell.x < grid.x and cell.y >= 0 and cell.y < grid.y,
						"%s: structure %s out of bounds at %s" % [label, s.kind, cell]) and ok
				ok = _check(not seen_footprint.has(cell),
						"%s: overlapping structures at %s" % [label, cell]) and ok
				seen_footprint[cell] = true
	# Walkable = '.' or 'p', outside every footprint.
	var walkable := func(cell: Vector2i) -> bool:
		if cell.x < 0 or cell.x >= grid.x or cell.y < 0 or cell.y >= grid.y:
			return false
		if footprints.has(cell):
			return false
		var ch: String = data.map[cell.y][cell.x]
		return ch == "." or ch == "p"
	var spawns: Array = data.scout_spawns + data.get("lead_spawns", []) \
			+ data.get("gunner_spawns", []) + data.goblin_spawns \
			+ data.get("smg_spawns", []) + data.get("smg_alt_spawns", []) \
			+ data.get("novice_spawns", []) + data.get("bolt_spawns", []) \
			+ data.get("prisoner_spawns", [])
	var seen_spawn := {}
	for spawn: Vector2i in spawns:
		ok = _check(walkable.call(spawn), "%s: spawn %s not walkable" % [label, spawn]) and ok
		ok = _check(not seen_spawn.has(spawn), "%s: duplicate spawn %s" % [label, spawn]) and ok
		seen_spawn[spawn] = true
	# Reachability: every spawn connected to the first scout spawn.
	var start: Vector2i = data.scout_spawns[0]
	var visited := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + dir
			if visited.has(nxt) or not walkable.call(nxt):
				continue
			visited[nxt] = true
			frontier.push_back(nxt)
	for spawn: Vector2i in spawns:
		ok = _check(visited.has(spawn),
				"%s: spawn %s unreachable from %s" % [label, spawn, start]) and ok
	ok = _validate_objectives(data, label, walkable, visited, seen_spawn) and ok
	ok = _validate_floor(data, label, grid) and ok
	return ok


## A level may name the ground it is fought on, and optionally a second sheet
## for an inset of the board. A typo would silently fall back to desert at
## load, so it is caught here instead.
static func _validate_floor(data: Dictionary, label: String, grid: Vector2i) -> bool:
	var ok := true
	var floor_name: String = data.get("floor", Board.DEFAULT_FLOOR)
	ok = _check(Board.FLOOR_SHEETS.has(floor_name),
			"%s: unknown floor '%s'" % [label, floor_name]) and ok
	var inset: Dictionary = data.get("floor_inset", {})
	if inset.is_empty():
		return ok
	var inset_name: String = inset.get("floor", Board.DEFAULT_FLOOR)
	ok = _check(Board.FLOOR_SHEETS.has(inset_name),
			"%s: unknown floor_inset floor '%s'" % [label, inset_name]) and ok
	var rect: Rect2i = inset.get("rect", Rect2i())
	ok = _check(rect.size.x > 0 and rect.size.y > 0,
			"%s: floor_inset rect is empty" % label) and ok
	ok = _check(Rect2i(Vector2i.ZERO, grid).encloses(rect),
			"%s: floor_inset rect %s outside the board" % [label, rect]) and ok
	return ok


## The squad size an extraction zone has to be able to hold. Every scout still
## alive has to fit inside it at once, so a zone smaller than the whole squad
## would make the level unwinnable on a no-casualty run.
static func squad_size(data: Dictionary) -> int:
	return data.scout_spawns.size() + data.get("lead_spawns", []).size() \
			+ data.get("gunner_spawns", []).size()


static func _validate_objectives(data: Dictionary, label: String,
		walkable: Callable, visited: Dictionary, spawns: Dictionary) -> bool:
	var ok := true
	var objectives: Array = data.get("objectives", [])
	var seen_cell := {}
	# Scenery must never impersonate an objective. The Choir's crate stacks
	# ('c') and the demolition targets are both stacked ordnance, so a map that
	# asks you to burn crates cannot also be dressed with crates you can only
	# hide behind - you would be reading art to guess at the objective.
	var has_destroy := false
	for obj: Dictionary in objectives:
		if obj.get("kind", "") == "destroy":
			has_destroy = true
	if has_destroy:
		for row: String in data.map:
			ok = _check(not row.contains("c"),
					"%s: 'c' crate scenery on a map with a destroy objective"
					% label) and ok
			if not ok:
				break
	for obj: Dictionary in objectives:
		var kind: String = obj.get("kind", "")
		ok = _check(kind == "eliminate" or kind == "destroy" or kind == "extract"
				or kind == "rescue",
				"%s: unknown objective kind '%s'" % [label, kind]) and ok
		if kind == "rescue":
			# The prisoners are the objective, so the level has to hold some.
			ok = _check(not data.get("prisoner_spawns", []).is_empty(),
					"%s: rescue objective with no prisoner_spawns" % label) and ok
			continue
		if kind == "eliminate":
			continue
		var cells: Array = obj.get("cells", [])
		ok = _check(not cells.is_empty(),
				"%s: '%s' objective needs cells" % [label, kind]) and ok
		for cell: Vector2i in cells:
			ok = _check(walkable.call(cell),
					"%s: objective cell %s not walkable" % [label, cell]) and ok
			ok = _check(visited.has(cell),
					"%s: objective cell %s unreachable" % [label, cell]) and ok
			ok = _check(not seen_cell.has(cell),
					"%s: objective cell %s used twice" % [label, cell]) and ok
			seen_cell[cell] = true
			# A cache sitting under a starting unit reads as a bug even
			# though nothing about it actually breaks.
			if kind == "destroy":
				ok = _check(not spawns.has(cell),
						"%s: cache %s sits on a spawn" % [label, cell]) and ok
		if kind == "extract":
			# Everyone who has to be standing in it at once - the squad, plus
			# any prisoner walking out with them.
			var needed: int = squad_size(data) \
					+ int(data.get("prisoner_spawns", []).size())
			ok = _check(cells.size() >= needed,
					"%s: extraction zone holds %d, needs %d" % [
							label, cells.size(), needed]) and ok
	return ok
