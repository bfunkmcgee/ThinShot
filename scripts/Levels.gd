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
## to wiping out the Thirst, which is what the first one does. Objectives are
## completed in order, and the level is won when the last one is:
##   {"kind": "eliminate"}                       - kill every goblin
##   {"kind": "destroy", "cells": [...]}         - demolish every cache
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
##   't' a Thirst claim marker - tally board, staked claim, well marker. Pure
##       decoration and walkable, exactly like 'p'; what it is for is that the
##       Charter the whole campaign is about has to be visible on the ground
##       somewhere, and this is where it is written down.
##
##   Half cover - unwalkable, shots pass at half damage. Three glyphs that
##   behave identically and say different things about who was here:
##   'j' rusted junk (nobody put it there)
##   's' sandbags (somebody dug in here)
##   'c' the Thirst's stacked ordnance (their ground, not yours). Keep these off
##       any map with a 'destroy' objective - crates you must burn and crates
##       you merely hide behind must not share a board.
##   'd' fuel drum (half cover too, but detonates when caught in a blast)
##
##   '=' barbed wire: stops movement and NOTHING else. Shots and sight cross it
##       freely and it gives cover to nobody. It is the only thing on the board
##       that divides ground without also dividing fire, which is what makes a
##       gate in it worth fighting over.
## Structure footprints overlay their cells as full blockers.
##
## A level may also paint an optional "roads" overlay: rows the same shape as
## the map, 'r' for a road cell, '.' for not. Purely cosmetic - the floor art
## under an 'r' becomes the connectable road tile matching its road
## neighbours, and movement, cover and LOS never notice. The level's floor
## needs an entry in Board.ROAD_SHEETS (only desert has one so far).

const LEVELS: Array[Dictionary] = [
	{
		# Four rock outcrops pinch the field into three lanes, and a junk
		# island splits the middle one so it cannot be walked straight down.
		# Every lane has a piece of cover to bound between, and each cover
		# piece has open ground on both sides so it can be flanked around.
		# Goblins hold in pairs, one per lane, which is what gives the
		# gunner's suppression something worth pinning.
		"name": "DRY WASH",
		"fiction": "A dead watercourse on the Confederacy's eastern line. There has been no water in it for two hundred years, and men are dying over it this morning.",
		"briefing": "The Thirst has never crossed the wash before. This morning they did - in daylight, in numbers, and they did not stop at the pumping station they passed on the way.\n\nEleven days ago an Accord survey capped four marginal wells north of here. The Assembly filed an objection. The Thirst filed this.\n\nRangers are stretched east and the Accord wants the crossing clear. That is the whole order, and it is yours because you are what is available.",
		"orders": "CLEAR THE WASH",
		"debrief": "They were not raiding.\n\nEvery fighter on the wash carried the same load: crates, sorted and tallied, roped for a long carry. Nobody hauls a tally into a raid.\n\nThey were moving it somewhere, and they were late. Follow the route back.",
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
		# The transport parked on the west edge (see "structures" below) sat
		# under and on top of the old start line, so the formation moved one
		# lane east to clear its footprint - same spread, same start line.
		"scout_spawns": [Vector2i(3, 4), Vector2i(5, 7), Vector2i(3, 8)],
		"lead_spawns": [Vector2i(4, 6)],
		"gunner_spawns": [Vector2i(4, 5)],
		"goblin_spawns": [
			Vector2i(13, 1), Vector2i(14, 4), Vector2i(14, 8),
		],
		# Raiders start a lane ahead of the riflemen and come straight on.
		# One per lane, and the southern one is the scrawny variant - open
		# ground is where his extra tile of movement reads clearest.
		"smg_spawns": [Vector2i(12, 3)],
		"smg_alt_spawns": [Vector2i(12, 6)],
		# Conscripts are pushed out in front of everyone as a screen.
		"novice_spawns": [Vector2i(15, 2), Vector2i(15, 5), Vector2i(15, 7)],
		# The marksman sits at the back of the middle lane behind the junk
		# island, so he only starts mattering once the squad is most of the
		# way across - the backstop rather than the opening problem.
		"bolt_spawns": [Vector2i(15, 4)],
		"structures": [
			# A troop transport idles on the west edge, first mission of the
			# campaign: the squad walks its ramp before the turn begins rather
			# than starting already deployed (Battle._run_disembark).
			{"kind": "troop_transport", "anchor": Vector2i(1, 6), "size": Vector2i(2, 2)},
		],
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
		"fiction": "A wire-and-scrap yard on the old freight line, where the Thirst stacks what it moves.",
		"briefing": "The route ends in a yard the locals call the Scrapline: rows of crates stacked and roped, waiting on a truck that has not come.\n\nKilling carriers changes nothing. There are always more carriers - the Charter left four settlements without water and every one of them has sons. The load is what matters.\n\nThere is a mast over the yard as well. It is not theirs, and while it stands, everyone within forty miles knows you are here.",
		"orders": "BURN THE CACHES, DROP THE RELAY",
		"debrief": "The crates were not scrap.\n\nPrimers, casings, barrel stock - machined, not scavenged. And the rifles: Tarkesh Foundry Mattocks, factory-new, no wear on the rails, no dust in the actions. Bhorra proof marks.\n\nThe Foundry was unwritten in eighty-three. There has not been a new Mattock in the world for three hundred and forty years, and there are eleven of them in this yard.\n\nEvery crate is struck with a Crown depot mark. One of ours, taken off the maps eleven years ago.\n\nSomebody is shipping guns that do not exist through a depot that does not either.",
		"size": Vector2i(16, 10),
		# Scrap thins out toward the west rather than stopping dead at the
		# outer barricade: the squad deploys onto ground it can bound through
		# instead of a bare apron, and the board stops reading as a packed
		# right half beside an empty left one.
		# The 't' at (4,6) and (5,7) are Assembly tally-boards: the Thirst counts
		# what it moves through here, in the open, on ground it says is theirs.
		# They are the first thing on any map that states the Charter grievance
		# the campaign turns on, and they cost the player nothing - walkable,
		# no cover, no LOS.
		"map": [
			".p..j.j..p.j....",
			"..j...j.........",
			"...j..j....j....",
			".j.......d.j....",
			"...j..j..d.j....",
			"....j.j.........",
			".j..t.j....j....",
			"...j.t.....j....",
			"..j...j....j....",
			"..p.j.j..p.j....",
		],
		# The track the load leaves on: a vehicle lane in from the west,
		# through the outer gate at y=3, jogging down the corridor and out the
		# inner gate lane at y=5 to the east edge. The relay mast at (10,4)
		# stands on its own short spur off the corridor - the yard wired its
		# aerials up beside the road that feeds it. Every road cell is open
		# ground; the goblins simply hold the gates the road runs through.
		"roads": [
			"................",
			"................",
			"rrr.............",
			"..rrrrrrr.......",
			"........r.r.....",
			"........rrrrrrrr",
			"................",
			"................",
			"................",
			"................",
		],
		# The line the level is named for cannot end at the map edge: a
		# barricade that stops where the camera does reads as one anybody
		# could stroll around, and the whole level is that they can't. Both
		# lines march on across the apron until the fade takes them - purely
		# scenery out there, but the gates stay the only way through that the
		# GROUND admits to. Columns match the map's own: outer x=6, inner
		# x=11, both ends of each.
		"apron_props": [
			{"kind": "junk", "from": Vector2i(6, -9), "to": Vector2i(6, -1)},
			{"kind": "junk", "from": Vector2i(6, 10), "to": Vector2i(6, 18)},
			{"kind": "junk", "from": Vector2i(11, -9), "to": Vector2i(11, -1)},
			{"kind": "junk", "from": Vector2i(11, 10), "to": Vector2i(11, 18)},
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
		# No vehicle wreck here, though this is the best fiction in the campaign
		# for one - a yard on the old freight line, waiting on a truck that has
		# not come, with the road overlay already painting the lane it would
		# have driven in on. Density was never the objection: the wreck costs
		# this board 0.645 -> 0.65 against a 0.66 gate. It is that the campaign
		# gets exactly two dead vehicles, and both are worth more elsewhere -
		# the hauler on THE HOLDING PENS, where it is the only hard cover on
		# the walk out, and the tanker on THE CISTERN, where it opens a second
		# lane. Three would make wrecks a motif; two keeps them a detail.
		"structures": [
			{"kind": "hut_1", "anchor": Vector2i(13, 2), "size": Vector2i(2, 2)},
			{"kind": "tent", "anchor": Vector2i(13, 6), "size": Vector2i(2, 2)},
		],
		# The load itself. Three caches spread corner to corner behind the
		# barricades, so clearing the yard is the only way to reach them all -
		# and a body count no longer ends the level. All three sit clear of the
		# hut and tent sprites, which are tall enough to paint over a cell
		# several rows in front of their own footprint.
		"objectives": [
			{
				"kind": "destroy",
				"label": "BURN THE CACHES",
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
		# What the mast is FOR. While it stands, the yard's call is out, and
		# every few turns somebody answers it off the freight line on the east
		# rim - so a body count can never finish this map, and the relay stops
		# being a side errand the moment the second patrol walks on. Light
		# arrivals only: the yard is calling neighbours, not a garrison.
		"pressure": {
			"while_objective": 1,
			"first_turn": 3,
			"every": 3,
			"edge": "east",
			"units": [[5], [6, 6], [4]],
			"banner": "THE MAST IS STILL CALLING",
		},
		"zone_seed": 21,
		"shade_seed": 34,
		# Was [-0.5, -0.2], which handed zone 2 nearly the whole yard and made
		# the cache rows stand on one unbroken slab of heavy hardpan.
		"zone_thresholds": [-0.35, 0.0],
	},
	{
		# A properly sealed compound this time. The fortress is flush to the
		# east edge so there is no walking around the back: the only ways in
		# are the west gate (8,4) and the two south gates (11,7) and (14,7).
		# Three ways in, all covered, and the garrison holds each in pairs.
		# The hamlet and rocks outside give the squad staging cover to set
		# the gun up before anyone steps into a gateway.
		"name": "OUTPOST 7",
		"fiction": "A Crown forward depot, struck off the maps eleven years ago. The Thirst lives in it now, and the squad goes in at dawn.",
		"briefing": "Outpost 7 was ours. It is not on any inventory the Accord will admit to holding, and the Thirst has been eating out of it for a decade.\n\nTwo ammunition stores are still standing in there. They are the reason a water dispute has rifles in it.\n\nYou cannot hold the place. There are not enough of you and there never were. Blow the stores and walk the squad back out.",
		"orders": "BLOW THE AMMO STORES, THEN EXTRACT",
		# The depot pays: Crown stores, swept or not, still hold saleable stock.
		"reward": {"scrip": 20},
		"debrief": "The stores are gone. What was in them was not.\n\nBoth were light - a third full, at most, and swept clean rather than looted. Somebody drew that stock down deliberately and moved it out ahead of you.\n\nRanger liaison has filed the Foundry marks upward and been told the query is above the Accord. Note that and keep it out of the log.\n\nTake the squad home. This is not finished, and the Assembly of Wells has called a strike in three districts over the capping. Whatever comes next is going to happen in front of people.",
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
		# in - close behind the west-gate defenders and the marksman, which makes
		# it something to fight toward rather than something to hunt for.
		"objectives": [
			{
				"kind": "destroy",
				"label": "BLOW THE AMMO STORES",
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
		# The withdrawal is chased. Two blasts big enough to open the west
		# zone are big enough to be heard by every patrol the garrison has
		# out, and they come home through the desert on the east rim - so the
		# walk back out is fought against arrivals, not just survivors. The
		# clock starts when the second store goes, which is the moment the
		# squad chose to be loud.
		"pressure": {
			"after_objective": 0,
			"first_turn": 2,
			"every": 2,
			"edge": "east",
			"units": [[4, 6], [6]],
			"banner": "PATROLS COMING HOME - KEEP MOVING",
		},
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
		"fiction": "Open ground west of the wash, where a Thirst column was still walking two days after the depot burned.",
		"briefing": "You were told the Thirst was finished east of the line. Here they are in daylight, walking a load west with no cover for a mile in any direction.\n\nThe stores at Outpost 7 were light when you blew them. This is where the rest went, and it is still going.\n\nBurn the load.\n\nRanger liaison has asked, on the record, that the squad account for what is in it before firing. That request is noted, and the order stands.",
		"orders": "BURN THE COLUMN'S LOAD",
		"debrief": "Water.\n\nNot ordnance. Drums of water, tallied and roped and hand-hauled across forty miles of nothing, and the squad put a match to all of it in a country that has been arguing about wells for three centuries.\n\nThe Rangers have gone quiet. Not hostile. Quiet, which is worse, and Liaison has stopped forwarding district intelligence pending a conversation nobody has scheduled.\n\nNote also: the Thirst is not arming a war any more. It is supplying something. And whatever it is sits far enough out that a drink is worth a column.",
		"size": Vector2i(16, 10),
		"map": [
			"..p......j......",
			".....j..........",
			"...........j....",
			"..j.............",
			"......dd........",
			# Was a lone rock; it sat in the transport's new footprint and a
			# single outcrop was never the point on a map about bare ground, so
			# it gave way rather than the transport shifting off the west edge.
			"............j...",
			".........dd.....",
			"....j...........",
			"..........j.....",
			"...p.......j....",
		],
		# The transport parked on the west edge (see "structures" below) sat
		# under and on top of the old start line, so the formation moved one
		# lane east to clear its footprint - same spread, same start line.
		# Both trailing scouts differ from their DRY WASH twins: (4,7) is
		# junk on this map, and row 3 is one long bare lane clear to the
		# east edge - (3,2) keeps the same shape without opening a 13-tile
		# firing lane through the start line.
		"scout_spawns": [Vector2i(3, 4), Vector2i(5, 7), Vector2i(3, 8)],
		"lead_spawns": [Vector2i(4, 6)],
		"gunner_spawns": [Vector2i(4, 5)],
		# The column is strung out rather than dug in - they were walking, not
		# waiting - so they arrive at the fight in ones and twos.
		"goblin_spawns": [
			Vector2i(12, 1), Vector2i(13, 4), Vector2i(12, 7), Vector2i(14, 2),
		],
		"smg_spawns": [Vector2i(11, 5)],
		"smg_alt_spawns": [Vector2i(11, 3), Vector2i(13, 6)],
		"novice_spawns": [Vector2i(15, 1), Vector2i(15, 5), Vector2i(15, 8)],
		"bolt_spawns": [Vector2i(14, 7)],
		# The second operation is where the Thirst starts bringing crew
		# weapons: a belt-fed gun walking escort in the middle of the column.
		"heavy_spawns": [Vector2i(13, 3)],
		# And a hired gun the column's water is paying for - the first hint
		# of what the debrief will say out loud: they are supplying something.
		"partisan_spawns": [Vector2i(15, 6)],
		"structures": [
			# A troop transport idles on the west edge, first mission of the
			# operation: the squad walks its ramp before the turn begins
			# rather than starting already deployed (Battle._run_disembark).
			{"kind": "troop_transport", "anchor": Vector2i(1, 6), "size": Vector2i(2, 2)},
		],
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
		# The convoy fiction begs for a "roads" overlay, but the column walks
		# the pan and only a desert road set exists: painting warm hardpan
		# track across pale salt would split the palette. Wire one in when a
		# salt road sheet ships.
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
		"fiction": "A walled water point on the old survey line. The only water east for a day in either direction, and the Charter says it belongs to a family that has not drawn from it in ninety years.",
		"briefing": "Every tally in the column names the same place: a cistern on the survey line, walled and held.\n\nIt is the only water east of here, which is why they hold it and why you cannot go around it.\n\nGet the squad through and out the far side. Do not stop to take it - you could not hold it, and the Assembly would hear that the Crown seized a well before the sun went down.",
		"orders": "BREAK THROUGH TO THE EAST",
		# A survey-line water point keeps survey-line instruments.
		"reward": {"item": "glass_sight"},
		"debrief": "Past the cistern the tracks stop scattering.\n\nEvery path east of the water runs together into one, beaten flat and wide by more feet than the Thirst has ever put in one place - and it does not follow the road. It follows the old riverbed, which has been dry since before the Charter was written.\n\nSomebody is walking them along a watercourse that has no water in it.",
		"size": Vector2i(16, 10),
		# Claim markers on the western approach, outside the wall: this is the
		# water the Charter awards to a family that has not drawn from it in
		# ninety years, and the 't' cells are where somebody has gone on saying
		# otherwise - a well marker and staked claims on the ground the squad
		# crosses to get at it. Decoration; the fight is unchanged.
		"map": [
			"..p...WWW.......",
			"...t..W...j.....",
			"...j..W..c......",
			".....sW....j....",
			"....t.....dd....",
			".....sW.........",
			"..tj..W....j....",
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
		# The gun sits a step behind the gate holder, firing down the middle
		# gap's lane - the breakthrough now has a reason to try the south.
		"heavy_spawns": [Vector2i(9, 4)],
		# The family the Charter says this water belongs to. No objective points
		# at them, nothing in the game arranges for them to survive, and the
		# squad's orders are to pass through rather than stop. They are placed
		# where the fighting is - one beside the gate defender at (7,3), one in
		# the southern approach - so that a frag thrown at a real target is a
		# decision rather than a formality. THE ROLL is the only thing that
		# will mention them afterwards.
		"bystander_spawns": [Vector2i(7, 2), Vector2i(8, 7)],
		"structures": [
			{"kind": "hut_1", "anchor": Vector2i(13, 0), "size": Vector2i(2, 2)},
			# A dead water tanker on the southern approach. The campaign's
			# whole argument is about hauling water, and this is the first
			# thing on any board that says people were doing it here long
			# before this squad arrived. It is also the reason the southern
			# gap is now worth trying: the breakthrough had one covered lane
			# and the other was bare, so there was no choice to make.
			{"kind": "tanker_wreck", "anchor": Vector2i(3, 8), "size": Vector2i(2, 2)},
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
		"fiction": "A wire pen behind the Thirst's line, and the reason they have been hauling water across forty miles of nothing.",
		"briefing": "The water was not for them.\n\nBehind the line there is a pen, and in it are the people they have been keeping alive - Confederacy survey staff, by the tallies. Civilians. Taken, fed, and kept.\n\nThat is what the column was for. Go and get them.\n\nThe pen is wire. You will see them long before you reach them, and so will everyone else - wire stops a boot and nothing else. There is one gate, and they have dug in behind it.\n\nA freed prisoner has no weapon and cannot be shot at, but they walk at their own pace and they walk the whole way back out through that same gate. Reaching them is the easy half.",
		"orders": "REACH THE PRISONERS, THEN WALK THEM OUT",
		"debrief": "Surveyors. Taken off the line eleven years ago, the same season Outpost 7 came off the maps, and kept alive ever since because somebody wanted the maps in their heads.\n\nThey knew every well, dump, and cistern on the survey line. That is how the Thirst found them all.\n\nThey will not say his name. They say he asked about water that is not there - where it used to run, how deep, how fast, which way it turned. Eleven years of questions about dry rivers.\n\nOne of them asked us, twice, what day it was, and then said she already knew.\n\nHe is still out there, at the end of the tracks.",
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
		# Dug in directly behind the one hole in the wire. The walk back out
		# with unarmed prisoners is the mission, and he is why.
		"heavy_spawns": [Vector2i(11, 4)],
		"structures": [
			{"kind": "tent", "anchor": Vector2i(6, 1), "size": Vector2i(2, 2)},
			# The hauler the water never rode on. Its being dead here is the
			# answer to the question the last two missions asked - why a column
			# was carrying drums forty miles by hand - and it is the only hard
			# cover on the way back out. That is deliberate: the briefing says
			# reaching the prisoners is the easy half, and until now the walk
			# home across open sand with unarmed people at move 4 had nothing
			# to bound between at all.
			{"kind": "hauler_wreck", "anchor": Vector2i(4, 6), "size": Vector2i(2, 2)},
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
		# Thirst standing in it. Back to elimination, which is the point: the
		# first operation taught that killing them changed nothing, and this is
		# the one time it does.
		"name": "THE SURVEY CAMP",
		"fiction": "Where every track east of the cistern ends: a camp laid out along a riverbed that has been dry for two hundred years, pitched as though the water were still running.",
		"briefing": "The tracks end in a bowl in the rock, and the Thirst is in it - all of it, and more than you have seen in one place.\n\nThey did not gather themselves. Somebody down there has been keeping them, and while he keeps them there will always be another column.\n\nFighters in that bowl will not break. Liaison has been clear on this and so has the interrogation of the pen guards: they are not staying because they are brave. They are staying because they have been told how this ends and they believe it.\n\nNo caches this time. No withdrawal.",
		"orders": "END THE READING",
		# The keeper's camp strongbox, taken whole.
		"reward": {"scrip": 30},
		# The briefing above is not colour: it says these fighters will not
		# break, and Rules.breaks_to_* honours it. Without this the starting
		# morale table would have three of the thirteen defenders of the
		# campaign's climactic mission running on the first round, on the one
		# map whose whole premise is an enemy that does not withdraw.
		"fighters_hold": true,
		"debrief": "It is over, and it is quiet.\n\nThe camp was not a camp. It was laid out along the bed in stages - markers at the bends, stakes at the depth changes, the whole dry course measured out and pegged as though somebody intended to fill it.\n\nThe old man's papers are forty years of Confederacy survey work, annotated in a hand that gets steadier the further out it goes. The last forty pages are not survey. They are a schedule.\n\nHe was not with the bodies. Nobody saw him leave.\n\nBring the squad home. The Rangers are burying their own dead separately from ours, and did not ask whether we minded.",
		"size": Vector2i(16, 10),
		# The 't' cells are the survey stakes, and they are the one piece of
		# scenery in the campaign that the debrief writes down afterwards:
		# "markers at the bends, stakes at the depth changes, the whole dry
		# course measured out and pegged as though somebody intended to fill
		# it." They run WNW to ESE across the bowl, following the riverbed
		# rather than the cover, so the thing the player has been walking past
		# all mission turns out to have been the answer.
		"map": [
			"....##......##..",
			"...#....j....#..",
			"..t....j........",
			"..j.t.c...j.....",
			".....dd.....j...",
			"........j..t....",
			"...jt......dd...",
			"......j..c......",
			"...#....j...t#..",
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
		# The camp's standing gun, at the rear of the bowl where the largest
		# force in the campaign keeps its base of fire.
		"heavy_spawns": [Vector2i(13, 2)],
		# The brute stands mid-bowl in front of the base of fire: the one
		# defender who walks TOWARD the squad while everyone else holds.
		"brute_spawns": [Vector2i(10, 4)],
		# The keeper's hired gun works the southern rocks. fighters_hold
		# covers him too - here even a contractor stays bought.
		"partisan_spawns": [Vector2i(12, 7)],
		"structures": [
			{"kind": "tent", "anchor": Vector2i(10, 8), "size": Vector2i(2, 2)},
		],
		"objectives": [
			{"kind": "eliminate", "label": "END THE READING"},
		],
		# The end of every track, and the one map that is not desert or pan:
		# burnt ground, because the Thirst has been gathering and burning here
		# long enough to leave the bowl black.
		"floor": "ash",
		"zone_seed": 77,
		"shade_seed": 34,
		"zone_thresholds": [-0.05, 0.30],
	},
	{
		# The epilogue road. Burnt country in depth - wall stubs where the
		# hamlet stood, drums the fire never found - with his three supply
		# drops strung along the road line, corner to corner, so no one
		# position covers two of them. The rearguard holds the middle ground
		# and keeps being fed from the east while the drops stand: the
		# pressure table is the mission's argument, and burning the supply is
		# what shuts it off.
		"name": "THE CINDER ROAD",
		"fiction": "The country west of the survey camp, burned by the Thirst as it broke up. The road through it is the only thing the fire could not take.",
		"briefing": "The bowl is cleared and the reading is ended, and the man who kept them together is not among the bodies.\n\nHe went west on the old survey road, with a rearguard and more supply than a running man needs. The country he is crossing is the country the Thirst burned behind itself, so there is nothing out there to live on but what he carries.\n\nBurn what he dropped along the cinder road, and he arrives at the end of it with nothing.",
		"orders": "BURN HIS SUPPLY DROPS",
		"debrief": "Three drops, burned where the fire line stalled.\n\nWhat was in them was not food. Map cases, instrument crates, a folio of well surveys under Crown stamps - he is not running from the campaign, he is carrying the reading out of it.\n\nAnd the rearguard fought for the crates, not for the road. He has one man left worth guarding and one place left to read. The cold well, at the end of the survey. Go and get the last surveyor back.",
		"size": Vector2i(16, 10),
		"map": [
			"..p....#.....j..",
			".....j....W...s.",
			"..j...W...W..j..",
			".p...jW....d....",
			".......s..W....j",
			"...j...W......d.",
			"......jW...W....",
			".......W..sW.j..",
			"....j...W....j..",
			".p....#.....j...",
		],
		# The transport parked on the west edge (see "structures" below) sat
		# under and on top of the old start line, so the formation moved one
		# lane east to clear its footprint - same spread, same start line.
		"scout_spawns": [Vector2i(3, 4), Vector2i(5, 8), Vector2i(3, 8)],
		"lead_spawns": [Vector2i(4, 6)],
		"gunner_spawns": [Vector2i(4, 5)],
		"goblin_spawns": [Vector2i(10, 3), Vector2i(9, 6), Vector2i(12, 7)],
		"smg_spawns": [Vector2i(13, 4), Vector2i(12, 5)],
		"novice_spawns": [Vector2i(14, 2), Vector2i(12, 2), Vector2i(12, 8)],
		"bolt_spawns": [Vector2i(15, 5)],
		# The rearguard's gun holds the middle ground between the drops - the
		# reason the road cannot just be walked.
		"heavy_spawns": [Vector2i(11, 5)],
		"structures": [
			# A troop transport idles on the west edge, first mission of the
			# operation: the squad walks its ramp before the turn begins
			# rather than starting already deployed (Battle._run_disembark).
			{"kind": "troop_transport", "anchor": Vector2i(1, 6), "size": Vector2i(2, 2)},
		],
		"objectives": [
			{
				"kind": "destroy",
				"label": "BURN THE SUPPLY DROPS",
				"prop": "crates",
				"cells": [Vector2i(12, 3), Vector2i(13, 6), Vector2i(11, 8)],
			},
		],
		# While his supply stands, the rearguard keeps being fed off the road
		# east - the drops are what they are here to hold, so burning the
		# drops is what ends the feeding. Conscripts and a runner: he is
		# spending what he has least need of to keep what he cannot replace.
		"pressure": {
			"while_objective": 0,
			"first_turn": 3,
			"every": 3,
			"edge": "east",
			"units": [[6], [4], [6, 6]],
			"banner": "HIS REARGUARD KEEPS COMING",
		},
		"floor": "ash",
		"zone_seed": 41,
		"shade_seed": 12,
		"zone_thresholds": [-0.05, 0.30],
	},
	{
		# The end of the survey. A full wire fence north to south with one
		# gate, his marksman rooted on the gate lane behind the one wall that
		# breaks it, and the capped well in the rock on the far side with the
		# last surveyor beside it. Reaching him is the rescue; the walk home
		# is the mission - the extraction zone is the west edge the squad
		# started from, and it does not open until the surveyor is aboard.
		"name": "THE COLD WELL",
		"fiction": "The last well on the survey, capped eleven years ago. The one man who can still read the district's water is being made to read it here.",
		"briefing": "The well was capped in the first survey, and it was capped because it was worth capping: the aquifer under it feeds every line on the maps the Assembly lost.\n\nHe has the last surveyor at the wellhead, and wire around both. When the reading is done he will not need the man any more, and nothing in his file says he keeps what he does not need.\n\nOne gate in the wire. His marksman is on it. Go through, reach the surveyor, and walk him home.",
		"orders": "REACH THE SURVEYOR, THEN WALK HIM OUT",
		# The wellhead works: the cap plate alone is worth the carry.
		"reward": {"scrip": 25, "item": "boiler_plate"},
		"debrief": "The surveyor is out, and the maps in his head are out with him.\n\nThe man who held him is not among the bodies. He was not among them at the survey camp either, and the file the campaign keeps on him reads like the files it keeps on the ones who will not die: seen twice, settled never.\n\nThe district has its water on paper again. The Accord has its questions. The squad goes home by the burnt road, and whatever walks out of the ash behind it is somebody else's war.\n\nThe notebook keeps the rest.",
		"size": Vector2i(16, 10),
		"map": [
			"..p....#=...j...",
			".....j..=.W..s..",
			"..j.....=..#....",
			".p..j...=..##...",
			"..j..W..=...#...",
			"...W.........#.s",
			"......jW=..s....",
			".j......=W...j..",
			"....j...=..W.j..",
			".p...#..=....j..",
		],
		"scout_spawns": [Vector2i(1, 2), Vector2i(2, 7), Vector2i(1, 8)],
		"lead_spawns": [Vector2i(0, 4)],
		"gunner_spawns": [Vector2i(0, 5)],
		"goblin_spawns": [Vector2i(10, 2), Vector2i(13, 6), Vector2i(10, 8)],
		"smg_spawns": [Vector2i(13, 2), Vector2i(12, 7)],
		"novice_spawns": [Vector2i(9, 5), Vector2i(10, 4), Vector2i(12, 8)],
		"bolt_spawns": [Vector2i(12, 5)],
		# The last gun he has, on the gate lane beside the marksman. Two
		# weapons on one lane is the argument for not walking through it.
		"heavy_spawns": [Vector2i(11, 5)],
		# And the brute just inside the wire, south of the gate: the man he
		# keeps closest at the end, guarding the one way in on foot.
		"brute_spawns": [Vector2i(9, 6)],
		# The last contractor still being paid, on the high north corner
		# behind the wire where a long rifle covers the whole approach.
		"partisan_spawns": [Vector2i(14, 0)],
		"prisoner_spawns": [Vector2i(13, 4)],
		"structures": [],
		"objectives": [
			{"kind": "rescue", "label": "REACH THE SURVEYOR"},
			{
				"kind": "extract",
				"label": "WALK HIM OUT",
				# Six cells: five Kestrels and the man they came for.
				"cells": [
					Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4),
					Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7),
				],
			},
		],
		"floor": "ash",
		"zone_seed": 58,
		"shade_seed": 21,
		"zone_thresholds": [0.0, 0.32],
	},
]

## The operations the campaign is made of. `missions` are indices into LEVELS,
## so mission data stays exactly where it was. `biome` is what the field camp
## between those missions dresses itself as, and each one now names its own
## floor tilesheet in BIOMES.
const OPERATIONS: Array[Dictionary] = [
	{
		"name": "OPERATION DRY WELL",
		"biome": "desert",
		"summary": "Push the Thirst back off the eastern wells, and find out what they are carrying.",
		"missions": [0, 1, 2],
	},
	{
		"name": "OPERATION LONG SURVEY",
		# The operation is fought out on the pan - the column, the cistern and
		# the pens are all salt missions, and the field camp between them
		# should stand on the same ground.
		"biome": "salt",
		"summary": "The stores were drawn down before you got there. Find out who took the rest, and where it went.",
		# Four rather than three: the rescue sits between the cistern and the
		# gathering, because the water the column was hauling only makes sense
		# once you find who it was being hauled to.
		"missions": [3, 4, 5, 6],
	},
	{
		"name": "OPERATION BURNT SURVEY",
		# The epilogue is fought out on the ash, which finally gives the third
		# tilesheet an operation of its own - the field camp between the two
		# missions stands on burnt ground.
		"biome": "ash",
		"summary": "The reading is ended and the man who kept it is not among the bodies. Follow him out through the country the Thirst burned behind itself.",
		"missions": [7, 8],
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

const LEGAL_CHARS := ".#Wjpdsc=t"


## Validates every level. push_error-based so it also reports in release
## builds (asserts are stripped there); debug builds additionally hard-stop.
## The clock a mission can put on the squad. A level's optional "pressure"
## table schedules Thirst arrivals off the turn counter, gated on the state
## of the objectives - so the thing calling for help is also the tap that
## shuts the arrivals off, and the player closes it by doing the mission.
##
##   "pressure": {
##       "while_objective": 1,     # waves only while objectives[1] is NOT done
##       "after_objective": 0,     # or: only once objectives[0] IS done
##       "first_turn": 3,          # turns before the first wave (from the gate
##                                 # opening, for after-gated pressure)
##       "every": 3,               # cadence after that
##       "edge": "east",           # the rim they walk on from
##       "units": [[5], [6, 6]],   # Kind ordinals - one list per wave, and the
##                                 # list of lists IS the cap
##       "banner": "...",          # what the arrival says on screen
##   }
##
## Pure arithmetic over the level dict, so tools/test_pressure.gd can pin the
## cadence and both gates without standing up a scene: Battle hands in the
## turn, which objectives are done, and (for after-gated pressure) the turn
## the gate opened, and gets back the wave due this turn or {}.
static func pressure_wave(level: Dictionary, turn: int, objectives_done: Array,
		gate_open_turn := -1) -> Dictionary:
	var pressure: Dictionary = level.get("pressure", {})
	if pressure.is_empty():
		return {}
	var gate_while := int(pressure.get("while_objective", -1))
	if gate_while >= 0 and gate_while < objectives_done.size() \
			and bool(objectives_done[gate_while]):
		return {}  # the thing calling for help is down
	var base := 0
	if pressure.has("after_objective"):
		if gate_open_turn < 0:
			return {}  # nothing to chase yet
		base = gate_open_turn
	var first := int(pressure.get("first_turn", 2))
	var every := maxi(int(pressure.get("every", 3)), 1)
	if turn < base + first or (turn - base - first) % every != 0:
		return {}
	var waves: Array = pressure.get("units", [])
	var index := (turn - base - first) / every
	if index >= waves.size():
		return {}  # the tap has run dry on its own
	return {
		"units": waves[index],
		"edge": str(pressure.get("edge", "east")),
		"banner": str(pressure.get("banner", "")),
	}


## The pressure table is data, so a typo in it is a shipped bug like any other
## map defect - checked with the same _check the rest of the schema uses.
static func _validate_pressure(data: Dictionary, label: String) -> bool:
	if not data.has("pressure"):
		return true
	var ok := true
	var p: Dictionary = data.pressure
	var objectives: Array = data.get("objectives", [])
	for key in ["while_objective", "after_objective"]:
		if p.has(key):
			var idx := int(p[key])
			ok = _check(idx >= 0 and idx < objectives.size(),
					"%s: pressure %s out of range" % [label, key]) and ok
	ok = _check(not (p.has("while_objective") and p.has("after_objective")),
			"%s: pressure cannot be both while- and after-gated" % label) and ok
	ok = _check(int(p.get("first_turn", 2)) >= 1,
			"%s: pressure first_turn must be >= 1" % label) and ok
	ok = _check(int(p.get("every", 3)) >= 1,
			"%s: pressure every must be >= 1" % label) and ok
	ok = _check(["north", "south", "east", "west"].has(str(p.get("edge", "east"))),
			"%s: pressure edge '%s' unknown" % [label, str(p.get("edge", ""))]) and ok
	var waves: Array = p.get("units", [])
	ok = _check(not waves.is_empty(), "%s: pressure has no waves" % label) and ok
	for wave in waves:
		ok = _check(wave is Array and not (wave as Array).is_empty(),
				"%s: each pressure wave is a non-empty kind list" % label) and ok
		if wave is Array:
			for kind in wave:
				# 3..7 are the Thirst's fighting kinds; 8 is the CIVILIAN and
				# pressure must never conscript bystanders.
				ok = _check(int(kind) >= 3 and int(kind) <= 7,
						"%s: pressure kind %s is not a Thirst fighter"
						% [label, str(kind)]) and ok
	return ok


static func validate_all() -> void:
	var ok := true
	for i in LEVELS.size():
		ok = _validate(i) and ok
	# An operation's biome names the ground its field camp stands on; a typo
	# would silently dress the camp as desert.
	for op: Dictionary in OPERATIONS:
		ok = _check(BIOMES.has(str(op.get("biome", ""))),
				"Operation '%s': unknown biome '%s'" % [
						op.get("name", "?"), op.get("biome", "")]) and ok
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
	# Walkable = the decoration-only chars, outside every footprint. Board says
	# the same thing by falling through to CellKind.OPEN; keep the two in step.
	var walkable := func(cell: Vector2i) -> bool:
		if cell.x < 0 or cell.x >= grid.x or cell.y < 0 or cell.y >= grid.y:
			return false
		if footprints.has(cell):
			return false
		var ch: String = data.map[cell.y][cell.x]
		return ch == "." or ch == "p" or ch == "t"
	var spawns: Array = data.scout_spawns + data.get("lead_spawns", []) \
			+ data.get("gunner_spawns", []) + data.goblin_spawns \
			+ data.get("smg_spawns", []) + data.get("smg_alt_spawns", []) \
			+ data.get("novice_spawns", []) + data.get("bolt_spawns", []) \
			+ data.get("heavy_spawns", []) + data.get("brute_spawns", []) \
			+ data.get("partisan_spawns", []) \
			+ data.get("prisoner_spawns", []) + data.get("bystander_spawns", [])
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
	ok = _validate_pressure(data, label) and ok
	ok = _validate_floor(data, label, grid) and ok
	ok = _validate_zones(data, label) and ok
	ok = _validate_roads(data, label, grid) and ok
	ok = _validate_reward(data, label) and ok
	return ok


## The optional authored "reward" - what a story win pays on top of the flat
## rate. Keys are exactly {scrip, item}: scrip a non-negative int, item a key
## the Gear catalog knows. Anything else is an authoring typo that would
## otherwise silently pay nothing.
static func _validate_reward(data: Dictionary, label: String) -> bool:
	if not data.has("reward"):
		return true
	var ok := _check(typeof(data.reward) == TYPE_DICTIONARY,
			"%s: reward must be a Dictionary" % label)
	if not ok:
		return false
	var reward: Dictionary = data.reward
	for key: String in reward:
		ok = _check(key == "scrip" or key == "item",
				"%s: unknown reward key '%s'" % [label, key]) and ok
	if reward.has("scrip"):
		ok = _check(typeof(reward.scrip) == TYPE_INT and int(reward.scrip) >= 0,
				"%s: reward scrip must be a non-negative int" % label) and ok
	if reward.has("item"):
		ok = _check(Gear.ITEMS.has(str(reward.get("item", ""))),
				"%s: reward item '%s' is not in the catalog"
				% [label, reward.get("item", "")]) and ok
	return ok


## The optional "roads" overlay is cosmetic, but it is still authored: rows
## must match the map, chars are 'r' (road) or '.' (not), and the level's
## floor has to have a road sheet at all or the key would silently paint
## nothing. A road cell under a rock, wall or structure footprint only warns -
## the art would be hidden, which is almost always a typo, but a track
## disappearing under a boulder that fell across it is a legitimate look.
static func _validate_roads(data: Dictionary, label: String, grid: Vector2i) -> bool:
	var roads: Array = data.get("roads", [])
	if roads.is_empty():
		return true
	var ok := _check(Board.ROAD_SHEETS.has(str(data.get("floor", Board.DEFAULT_FLOOR))),
			"%s: paints roads but floor '%s' has no road sheet"
			% [label, data.get("floor", Board.DEFAULT_FLOOR)])
	if not _check(roads.size() == grid.y,
			"%s: roads must have %d rows" % [label, grid.y]):
		return false
	var footprints := _footprint_cells(data)
	for y in grid.y:
		var srow := str(roads[y])
		if not _check(srow.length() == grid.x,
				"%s: roads row '%s' wrong length" % [label, srow]):
			ok = false
			continue
		for x in grid.x:
			var ch := srow[x]
			ok = _check(ch == "r" or ch == ".",
					"%s: roads char '%s' not in 'r.'" % [label, ch]) and ok
			if ch != "r":
				continue
			var map_ch: String = data.map[y][x]
			if map_ch == "#" or map_ch == "W" or footprints.has(Vector2i(x, y)):
				push_warning("[Levels] %s: road cell (%d, %d) hidden under blocker '%s'"
						% [label, x, y, map_ch])
	return ok


## The cosmetic layer gets checked too: thresholds must be two ascending
## values, the optional zone_map / prop_seed / lint keys must be shaped right,
## and the split the noise actually produces gets a sanity pass - a zone under
## 5% of the board reads as stray speckles, one over 90% means the thresholds
## are doing nothing. Lopsided splits only warn: a near-uniform pan is a valid
## look, but it should be a chosen one.
static func _validate_zones(data: Dictionary, label: String) -> bool:
	var ok := true
	var grid: Vector2i = data.size
	var thresholds: Array = data.get("zone_thresholds", [-0.12, 0.22])
	ok = _check(thresholds.size() == 2,
			"%s: zone_thresholds needs exactly 2 values" % label) and ok
	if thresholds.size() == 2:
		ok = _check(float(thresholds[0]) < float(thresholds[1]),
				"%s: zone_thresholds %s not ascending" % [label, thresholds]) and ok
	var zone_map: Array = data.get("zone_map", [])
	if not zone_map.is_empty():
		ok = _check(zone_map.size() == grid.y,
				"%s: zone_map must have %d rows" % [label, grid.y]) and ok
		for row in zone_map:
			var srow := str(row)
			ok = _check(srow.length() == grid.x,
					"%s: zone_map row '%s' wrong length" % [label, srow]) and ok
			for ch in srow:
				ok = _check("012.".contains(ch),
						"%s: zone_map char '%s' not in '012.'" % [label, ch]) and ok
	if data.has("prop_seed"):
		ok = _check(typeof(data.prop_seed) == TYPE_INT,
				"%s: prop_seed must be an int" % label) and ok
	# "lint" is per-level tooling overrides (check_level.gd reads it); the game
	# only requires that it is a dictionary and otherwise leaves it alone.
	if data.has("lint"):
		ok = _check(typeof(data.lint) == TYPE_DICTIONARY,
				"%s: lint must be a dictionary" % label) and ok
	if not ok:
		return false
	# Rebuild the classification Board will run - same noise, same seed, same
	# thresholds, same zone_map overrides - and measure the split.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = int(data.get("zone_seed", 7))
	noise.frequency = Board.ZONE_NOISE_FREQ
	var counts := [0, 0, 0]
	for y in grid.y:
		for x in grid.x:
			var zone := -1
			if y < zone_map.size():
				var srow := str(zone_map[y])
				if x < srow.length() and srow[x] != ".":
					zone = clampi(int(srow[x]), 0, 2)
			if zone < 0:
				var n := noise.get_noise_2d(x, y)
				zone = 0 if n < float(thresholds[0]) \
						else (1 if n < float(thresholds[1]) else 2)
			counts[zone] += 1
	var total := grid.x * grid.y
	for zone in 3:
		var share := float(counts[zone]) / float(total)
		if share < 0.05 or share > 0.90:
			push_warning("[Levels] %s: zone %d covers %d%% of the board %s" % [
					label, zone, roundi(share * 100.0), thresholds])
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
	# Scenery must never impersonate an objective. The Thirst's crate stacks
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
			# any prisoner walking out with them. Bystanders are deliberately
			# NOT counted: they live here and the squad is the one leaving, so
			# the extract objective steps over them (see Battle).
			var needed: int = squad_size(data) \
					+ int(data.get("prisoner_spawns", []).size())
			ok = _check(cells.size() >= needed,
					"%s: extraction zone holds %d, needs %d" % [
							label, cells.size(), needed]) and ok
	return ok
