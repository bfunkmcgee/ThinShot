class_name Board
extends Node2D

## Desert battle grid: isometric tile drawing, coordinate math, and BFS
## reachability. Cells are abstract Vector2i; only this script knows the
## 2:1 diamond projection. Highlight state is pushed in by Battle.gd.

const TILE_W := 128
const TILE_H := 60
## Texel-density doctrine: the camera never zooms past 1.0, where a floor
## texel is exactly one screen pixel and the 2x-class props and units land on
## exact 2x2 pixel blocks. Above 1.0 nearest-neighbour has to invent pixels
## and every sprite goes lumpy; below it the eighths snap keeps the grid
## stable. Battle and Camp both clamp to this, so the two scenes share one
## density and a soldier is the same size on screen at home as in the fight.
const MAX_ZOOM := 1.0

## What a cell means for movement and shooting.
##
## WIRE is the odd one out and the reason this is an enum rather than two
## booleans: it stops you walking but does nothing else. You can see across it,
## shoot across it, and it gives no cover to anyone standing beside it - a line
## on the map that only movement respects. Everything else that stops a boot
## also stops a bullet or slows one down.
enum CellKind {
	OPEN,   # walkable, no LOS effect ('.', 'p')
	BLOCK,  # impassable, blocks LOS ('#', 'W', structure footprints)
	COVER,  # impassable, LOS passes at half damage ('j', 's', 'c', 'd')
	WIRE,   # impassable, no LOS effect, no cover ('=')
}

## One sheet per kind of ground a level can be fought on. Every sheet is the
## same ten-tile grid in the same slot order, so a level picks its ground with
## a single name and nothing else about the board changes.
const FLOOR_SHEETS := {
	"desert": preload(
			"res://assets/Tiles/Environments/Desert/Cracked_Desert_floor.png"),
	"salt": preload(
			"res://assets/Tiles/Environments/Salt/Salt_flat_floor.png"),
	"ash": preload(
			"res://assets/Tiles/Environments/Ash/Ash_burnt_floor.png"),
	"compound": preload(
			"res://assets/Tiles/Environments/Compound/Compound_floor.png"),
}
const DEFAULT_FLOOR := "desert"

## Connectable road sheets, one per floor that has shipped one. The `.tiles.json`
## sidecar beside each is an edge-mode set (TileCatalog.load_road_for): sixteen
## 128x60 faces indexed by which of the cell's four grid edges the road
## continues across. A floor with no entry simply cannot paint roads yet.
const ROAD_SHEETS := {
	"desert": preload(
			"res://assets/Tiles/Environments/Desert/Desert_road.png"),
}

## How each ground reads, and what the air over it does to everything standing
## on it. Without this every board is lit like the desert one: the dust shader
## warm-shifts props toward sand and hazes them toward a tan horizon, which is
## right on cracked desert and actively wrong on burnt grey ash.
##
## Derived from each sheet's measured mean colour rather than picked by eye:
##   tint  - (channel / mean channel)^0.2, normalised to preserve luminance, so
##           props are nudged toward the ground's hue and no further. Reproduces
##           the hand-tuned desert value to two decimals, which is why the
##           recipe is trusted for the other three.
##   haze  - the ground desaturated 30% and lifted 25% toward white: the far
##           edge of the board sits back into its own atmosphere, not sand's.
##   shadow / shadow_gain - shadows are the ground darkened, and the gain keeps
##           them equally READABLE rather than equally dark. Ash is luminance
##           100 against desert's 147, so the same alpha would nearly vanish.
##   accent / spacing - the flatter a sheet's base tiles, the louder a rare
##           feature tile shouts. Ash's calm slots measure contrast 9 against
##           its accent's 44, so it scatters sparsest and desert densest.
##           The SPACING is the knob that actually bites at 16x10: with a
##           minimum of 2 cells between accents a board that size saturates at
##           4-8 of them and the rate never gets to bind at all. The rate is
##           kept per-sheet regardless, because it is what governs a bigger map.
## Distance haze, shared between the floor and everything standing on it. The
## board's depth is quantised into a few bands so the whole scene needs only a
## handful of prop materials, and the FloorLayer paints the ground with the
## same numbers - one atmosphere, not three separately graded populations.
## Battle and Camp read these rather than keeping their own copies.
const HAZE_BANDS := 5
const HAZE_MAX := 0.20

const FLOOR_MOODS := {
	"desert": {
		# Re-derived 2026-08 for the promoted 18-slot sheet. The muted palette
		# sits at the same luminance as the old art (lum 146 vs 146, so the
		# gain holds at 1.00) but carries far less orange: the warm push, the
		# sand haze and the shadow hue all relax with it. The old hand-tuned
		# values were (1.04, 0.99, 0.90) / (0.80, 0.71, 0.55) /
		# (0.16, 0.10, 0.06). tools/derive_floor_mood.gd reprints this block
		# for any sheet using the same math.
		"tint": Vector3(1.03, 1.00, 0.95),
		"haze": Vector3(0.72, 0.67, 0.61),
		"shadow": Color(0.13, 0.11, 0.09),
		"shadow_gain": 1.00,
		"accent": 0.06,
		"spacing": 2,
	},
	"salt": {
		# Re-derived 2026-08-14 for the promoted 18-slot sheet, taken as the
		# recipe printed it (like desert/compound; shipped salt already matched
		# the recipe exactly). The rebuilt pan sits at lum 152.9 vs ref 146.5,
		# so the gain holds at the recipe 0.96; tint/haze/shadow move a final
		# digit with the slightly warmer beige mean. Accents back way off: the
		# new zone0 powder pan is nearly featureless (base contrast 2.8, was
		# the old sheet's ~5; accent/base ratio 5.19, was 3.0), so the brine
		# pool and nodules read much louder and want ash-like sparseness. Old
		# values: (1.01, 1.00, 0.98) / (0.72, 0.70, 0.67) / (0.13, 0.12, 0.11)
		# / 0.96 / 0.06 / 2. tools/derive_floor_mood.gd reprints this block.
		"tint": Vector3(1.01, 1.00, 0.99),
		"haze": Vector3(0.71, 0.70, 0.68),
		"shadow": Color(0.12, 0.12, 0.11),
		"shadow_gain": 0.96,
		"accent": 0.04,
		"spacing": 4,
	},
	"ash": {
		# Re-derived 2026-08 for the promoted 18-slot sheet (lum 103, barely
		# moved from the old art, so the ground stays a dark bowl). Two
		# hand-tunings survive on purpose, keeping the cold-dead intent: tint
		# stays exactly neutral (the recipe printed 1.01 red - that is the new
		# warm grit bleeding into the mean; the grit may be warm, the AIR
		# stays cold) and haze keeps the deliberate ~10% burnt-bowl darkening
		# (recipe printed 0.56, 0.55, 0.55). shadow_gain keeps its in-engine
		# readability nudge (recipe 1.43; it was 1.44 before). Accent cadence
		# follows the new sheet: the rebuilt accents shout less over the drift
		# (ratio 3.15, was 4.6), so they can come slightly denser. Old values:
		# (1.00, 1.00, 1.00) / (0.50, 0.49, 0.49) / (0.08, 0.08, 0.08) /
		# 1.50 / 0.04 / 4. tools/derive_floor_mood.gd reprints the raw recipe.
		"tint": Vector3(1.00, 1.00, 1.00),
		"haze": Vector3(0.50, 0.50, 0.50),
		"shadow": Color(0.08, 0.08, 0.08),
		"shadow_gain": 1.50,
		"accent": 0.05,
		"spacing": 3,
	},
	"compound": {
		# Re-derived 2026-08 for the promoted 18-slot sheet, taken as the
		# recipe printed it (like desert). The rebuilt concrete sits a touch
		# brighter (lum 139.5 vs ref 146.5), so the gain relaxes to the recipe
		# 1.05 - the old 1.08 carried a hand-nudge tuned against the previous
		# art. Accents ease off: the new zone0 poured slabs are much flatter
		# (accent/base ratio 7.9, was 3.2), so accents read louder and want
		# more spacing. Old values: (1.01, 1.00, 0.97) / (0.68, 0.66, 0.62) /
		# (0.12, 0.11, 0.10) / 1.08 / 0.05 / 3.
		"tint": Vector3(1.01, 1.00, 0.98),
		"haze": Vector3(0.67, 0.66, 0.64),
		"shadow": Color(0.11, 0.11, 0.10),
		"shadow_gain": 1.05,
		"accent": 0.04,
		"spacing": 4,
	},
}

# Measured source regions in the floor sheet: 128x60 diamond faces on a
# 129px stride, rows at y 34/163/292. The plant tile (index 6) is 6px
# taller; its extra height hangs above the diamond when drawn.
const TILE_REGIONS: Array[Rect2] = [
	Rect2(0, 34, 128, 60),    # 0 cracked plain
	Rect2(129, 34, 128, 60),  # 1 cracked plain
	Rect2(258, 34, 128, 60),  # 2 fine cracks
	Rect2(387, 34, 128, 60),  # 3 dense cracks
	Rect2(0, 163, 128, 60),   # 4 crater (accent)
	Rect2(129, 163, 128, 60), # 5 mottled
	Rect2(258, 157, 128, 66), # 6 plant tuft (accent, taller)
	Rect2(387, 163, 128, 60), # 7 log debris (accent)
	Rect2(0, 292, 128, 60),   # 8 sandy waves
	Rect2(129, 292, 128, 60), # 9 sandy cracks
]

# The desert sheet's plant tuft is the one tile drawn taller than its diamond.
# The later sheets are uniform, so their accents sit inside the diamond and
# every region is the same 128x60 face.
const TILE_REGIONS_FLAT: Array[Rect2] = [
	Rect2(0, 34, 128, 60),    # 0 zone B base
	Rect2(129, 34, 128, 60),  # 1 zone B base
	Rect2(258, 34, 128, 60),  # 2 zone B base
	Rect2(387, 34, 128, 60),  # 3 zone C base
	Rect2(0, 163, 128, 60),   # 4 zone C accent
	Rect2(129, 163, 128, 60), # 5 zone C base
	Rect2(258, 163, 128, 60), # 6 zone A accent
	Rect2(387, 163, 128, 60), # 7 zone B accent
	Rect2(0, 292, 128, 60),   # 8 zone A base
	Rect2(129, 292, 128, 60), # 9 zone A base
]

const SHEET_REGIONS := {
	"desert": TILE_REGIONS,
	"salt": TILE_REGIONS_FLAT,
	"ash": TILE_REGIONS_FLAT,
	"compound": TILE_REGIONS_FLAT,
}

# Tile families by terrain zone (indices into TILE_REGIONS), carved out of
# the map by smooth noise so neighboring cells read as one terrain patch.
const ZONE_NOISE_FREQ := 0.17
const ZONE_FAMILIES: Array = [
	[8, 9],     # 0: sandy wash
	[0, 1, 2],  # 1: lightly cracked hardpan
	[3, 5],     # 2: heavily cracked / mottled hardpan
]
# One themed accent per zone: plants grow in sand, debris lies among the
# light cracks, craters pock the heavy hardpan.
const ZONE_ACCENTS: Array[int] = [6, 7, 4]

## Fallback for a floor with no mood entry. Live rates come from FLOOR_MOODS.
const ACCENT_CHANCE := 0.07
const ACCENT_MIN_SPACING := 2  # Chebyshev cells between any two accents

## The world past the boundary. The arena used to float on the window's clear
## colour, which reads as a slab over darkness; the apron continues the level's
## own ground outward, each ring dimmed and washed harder toward that colour
## until it dissolves into it - the fight happens SOMEWHERE, and the somewhere
## fades out instead of ending on a line.
##
## Thirteen rings covers the worst shipped exposure: a 9x6 field camp at the
## pinned 1.0 zoom leaves ~350px of window past the top edge, and a ring only
## buys TILE_H/2 = 30px of that. Bigger boards waste a few offscreen rings,
## which a repaint-on-level-load layer can afford.
const APRON_RINGS := 13
## Tiles outside the arena render at most this bright. The board's own shade
## noise runs 0.94..1.0, so the step down is what marks the boundary - the
## playable diamond stays the lit part of the world without needing an edge.
const APRON_SHADE := 0.82
## How much of the ground has already dissolved into the clear colour right at
## the boundary, easing to everything by APRON_RINGS cells out. The dissolve is
## per PIXEL, not per tile: the apron's tiles draw opaque into a CanvasGroup
## and its shader (apron_fade.gdshader, fed these numbers) fades the composited
## result by distance past the arena. Composite-then-fade is load-bearing -
## fading the tiles individually double-blends their shared 1px art edges into
## a bright seam lattice. The window's clear colour shows through whatever the
## shader removes, so the fade target can never drift from the background. The
## exponent holds the near ground readable while the far rings do most of the
## dissolving.
const APRON_FADE_START := 0.20
const APRON_FADE_EXP := 1.35

# Ground contact shadows for props, matching Unit's sun direction. Positive
# values are ellipse radii; DIAMOND_SHADOW means "shrunk tile diamond", so
# adjacent walls and structure footprints union into one cast shadow.
const SHADOW_SQUASH := 0.469  # TILE_H / TILE_W
const SHADOW_OFFSET := Vector2(3, 2)
const SHADOW_COLOR := Color(0.16, 0.10, 0.06, 0.24)
const DIAMOND_SHADOW := -1.0
const SHADOW_RADII := {
	"#": 22.0, "j": 20.0, "p": 12.0, "d": 15.0, "s": 18.0, "c": 20.0,
	# Wire throws almost nothing - a row of posts and some thread.
	"=": 11.0,
	# A claim stake is a post and a rag, so it throws about what a plant does.
	"t": 11.0,
	"W": DIAMOND_SHADOW,
}

## What an informant's word looks like on the ground. Deliberately the objective
## beacon's amber rather than the danger red: this is knowledge the squad was
## given, not a threat the squad worked out.
const INTEL_EDGE := Color(1.0, 0.69, 0.18, 0.85)

const GRID_LINE := Color(0.35, 0.27, 0.15, 0.25)
# Corner ticks on route-only cells: the quiet remnant of the full lattice,
# shown exactly where a movement decision is being made.
const GRID_TICK := Color(0.35, 0.27, 0.15, 0.5)
const GRID_TICK_LEN := 6.0
const MOVE_HL := Color(0.95, 0.85, 0.3, 0.35)
const ATTACK_HL := Color(0.9, 0.2, 0.15, 0.4)
const DANGER_FILL := Color(0.85, 0.15, 0.1, 0.13)
const DANGER_HATCH := Color(0.85, 0.2, 0.12, 0.30)
const HOVER_OUTLINE := Color(1.0, 0.97, 0.85, 0.9)
const PATH_DOT := Color(1.0, 0.95, 0.7, 0.9)
const AIM_LINE := Color(1.0, 0.45, 0.3, 0.85)
const ATTACK_HOVER_HL := Color(1.0, 0.35, 0.25, 0.55)
# Amber variants signal a shot that clips junk cover (half damage).
const AIM_LINE_COVER := Color(1.0, 0.82, 0.25, 0.85)
const ATTACK_HOVER_COVER_HL := Color(1.0, 0.65, 0.2, 0.5)
# Armed-fire-mode highlights: hotter than the normal attack red.
const BURST_HL := Color(1.0, 0.45, 0.05, 0.5)
const AUTO_HL := Color(1.0, 0.72, 0.1, 0.55)
const SUPPRESS_HL := Color(0.45, 0.72, 0.9, 0.5)
# Cyan means "flanking - cover ignored" (amber is already taken by cover).
const AIM_LINE_FLANK := Color(0.45, 0.95, 1.0, 0.9)
const ATTACK_HOVER_FLANK_HL := Color(0.3, 0.85, 1.0, 0.5)
# Overwatch arcs, hatched on the opposite diagonal from danger. Amber for
# enemy arcs (a threat), green for your own (ground you have covered).
# Thrown ordnance. The blast preview is the footprint a grenade would cover
# if released at the hovered cell; smoke is live cover already on the board.
const BLAST_FRAG_HL := Color(1.0, 0.42, 0.12, 0.42)
const BLAST_SMOKE_HL := Color(0.80, 0.84, 0.88, 0.38)
const BLAST_EDGE := Color(1.0, 0.85, 0.6, 0.75)
const SMOKE_FILL := Color(0.74, 0.72, 0.68, 0.50)
const SMOKE_EDGE := Color(0.84, 0.83, 0.80, 0.30)

# Mission objectives. Caches pulse so they read as things to act on rather
# than scenery; the extraction zone goes flat green and only lights up once
# it is actually open.
const CACHE_FILL := Color(0.95, 0.35, 0.12, 0.30)
const CACHE_EDGE := Color(1.0, 0.66, 0.26, 0.95)
const CACHE_REACH_EDGE := Color(1.0, 0.95, 0.55, 1.0)
const EXTRACT_FILL := Color(0.35, 0.9, 0.45, 0.16)
const EXTRACT_EDGE := Color(0.5, 1.0, 0.6, 0.55)
const EXTRACT_ARMED_FILL := Color(0.4, 1.0, 0.5, 0.30)
const EXTRACT_ARMED_EDGE := Color(0.7, 1.0, 0.8, 0.95)

# Cover readability. A bar hugging a tile edge means "something to get behind
# on that side"; a dot in the middle of a reachable tile means "there is cover
# here somewhere", so a route between covered tiles can be read at a glance.
const HAZARD_HL := Color(1.0, 0.55, 0.08, 0.42)
const HAZARD_EDGE := Color(1.0, 0.82, 0.3, 0.95)

const COVER_HALF_PIP := Color(0.55, 0.86, 0.62, 0.95)
const COVER_FULL_PIP := Color(0.45, 1.0, 0.58, 1.0)
const COVER_DEST_DOT := Color(0.55, 0.95, 0.65, 0.55)
# Which diamond vertices bound the edge facing each orthogonal neighbour.
# _diamond() is ordered [top, right, bottom, left] and +x reads south-east.
const COVER_EDGES := {
	Vector2i(1, 0): [1, 2],   # south-east
	Vector2i(0, 1): [2, 3],   # south-west
	Vector2i(-1, 0): [3, 0],  # north-west
	Vector2i(0, -1): [0, 1],  # north-east
}

const WATCH_FILL := Color(1.0, 0.72, 0.28, 0.10)
const WATCH_HATCH := Color(1.0, 0.72, 0.28, 0.26)
const WATCH_FILL_ALLY := Color(0.45, 0.92, 0.5, 0.10)
const WATCH_HATCH_ALLY := Color(0.5, 0.95, 0.55, 0.26)
# The high-contrast alternates cover the one pairing that leans on red-green
# telling: friendly arcs go BLUE instead of green, so hostile amber and your
# own covered ground read apart by hue family under every kind of color
# vision. Everything else on the board already separates by lightness.
const WATCH_FILL_ALLY_HC := Color(0.35, 0.62, 1.0, 0.12)
const WATCH_HATCH_ALLY_HC := Color(0.42, 0.68, 1.0, 0.30)
# Set from the settings by Battle; a bare Board (tests, the camp) keeps green.
var high_contrast := false

const NO_CELL := Vector2i(-1, -1)

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

# Level state, loaded by set_level().
var size := Vector2i(12, 8)
var map_rows: Array = []
var _kind: Array = []                     # size.y rows of Array[int] CellKind
var _structure_cells: Dictionary = {}     # Vector2i -> true

# Per-cell render info ({region, flip, shade}) built by set_level.
var tile_cache: Array = []
# Out-of-bounds ground, Vector2i -> {sheet, region, flip, shade}, built
# alongside the tile cache. The tiles are opaque; the dissolve toward the
# window's clear colour is the apron CanvasGroup's shader, not per-cell state.
# Purely cosmetic: nothing walks, shoots or spawns here, so no gameplay code
# may ever read it. FloorLayer.ApronLayer paints it under everything.
var apron_cache: Dictionary = {}
# Road cells OUTSIDE the arena (Vector2i -> true): the level's authored
# "apron_roads" plus the automatic continuation of every in-board road that
# reaches the boundary. As cosmetic as the rest of the apron - but roads are
# the one thing out there gameplay code may see, because _road_tile reads
# these to keep a border road cell from capping at the world's edge.
var apron_roads: Dictionary = {}
# A level may opt out of the whole apron with "apron": false - an interior
# room is INSIDE somewhere, and desert dissolving around its walls would say
# otherwise.
var _apron_enabled := true
# Contact shadows for apron scenery, [{pos: local px, radius}] - filled by
# ApronScenery, drawn by the ApronLayer INSIDE the group so they fade with
# the ground they fall on.
var apron_shadows: Array = []

# Which ground this level is fought on, resolved by set_level(). A level may
# also name an inset - the ground inside a compound wall, say - which is drawn
# from a second sheet so a fortress interior reads as built rather than as the
# same sand as the desert outside it.
var _floor_sheet: Texture2D = FLOOR_SHEETS[DEFAULT_FLOOR]
var _floor_regions: Array[Rect2] = TILE_REGIONS
var _floor_name := DEFAULT_FLOOR
var _floor_accent := ACCENT_CHANCE
var _floor_spacing := ACCENT_MIN_SPACING
var _inset_rect := Rect2i()
var _inset_sheet: Texture2D = null
var _inset_regions: Array[Rect2] = TILE_REGIONS
var _inset_name := ""
var _inset_accent := ACCENT_CHANCE
var _inset_spacing := ACCENT_MIN_SPACING
# Sidecar catalogs for the two sheets, when the art pipeline has shipped one
# ({} otherwise - the current state of every sheet). A catalog swaps the
# hardcoded family/accent tables for the sheet's own, restricts mirroring to
# tiles flagged symmetric, and unlocks corner-transition tiles at zone seams.
var _floor_catalog: Dictionary = {}
var _inset_catalog: Dictionary = {}
# Optional per-cell zone override painted by the level ("zone_map" rows of
# '012.'), consumed by _build_tile_cache; '.' defers to the noise.
var _zone_map: Array = []
# Optional road overlay painted by the level ("roads" rows of 'r.'). Purely
# cosmetic: the tile cache swaps the floor art under an 'r' for the road tile
# whose open edges match its road neighbours - CellKind, cover and LOS never
# see it. The catalog is the floor's ROAD_SHEETS entry, parsed once.
var _road_map: Array = []
var _road_catalog: Dictionary = {}
# The air over this board. Follows the MAIN floor even on a level with an
# inset: a compound courtyard inside a desert outpost is still a desert
# afternoon, and hazing half the props toward concrete would split the place
# in two rather than reading as one location.
var _mood: Dictionary = FLOOR_MOODS[DEFAULT_FLOOR]

# cell -> came_from cell, for every cell the selected unit can route
# THROUGH. Paths are reconstructed from this.
var move_cells: Dictionary = {}
# The subset of those it could actually stop on - drawn and clickable.
# Squadmates can be walked past but not stood on, so these differ.
var move_dests: Dictionary = {}
# Cells containing enemies the selected unit can shoot.
var attack_cells: Array[Vector2i] = []
# Hover feedback state, pushed in by Battle.
var hover_cell := NO_CELL
var path_preview: Array[Vector2i] = []
var aim_from := NO_CELL
var aim_covered := false
var aim_flanking := false
var fire_mode := 0  # mirrors Battle.FireMode; tints the attack highlights
# Cells covered by overwatch arcs: cell -> true if the watcher is hostile.
# Objectives. cache_cells maps an intact cache cell -> true if a selected
# scout is close enough to demolish it this turn.
# Cover overlay: the one cell to spell out edge by edge, and the set of
# reachable cells that have cover at all.
var cover_focus := NO_CELL
var cover_dests: Dictionary = {}

# Contact shadows for props that are not map characters. Objective targets are
# spawned from the objective list rather than a map char, so without this they
# sit on the sand with nothing under them and read as pasted on.
var prop_shadows: Dictionary = {}

# Debug escape hatch: true restores the full lattice over every tile. Off by
# default - at rest the board reads as a place, and the tactical grid shows
# only as corner ticks on the cells a move is actually being plotted through.
var show_grid := false

# Paints the static floor (tiles, haze, contact shadows) on its own canvas
# item below everything, so those 160+ blits repaint on level changes rather
# than on every highlight. Created in _ready; headless tools that new() a bare
# Board never enter the tree and simply run without one.
var floor_layer: FloorLayer = null

# The out-of-bounds ground, composited as ONE layer so its fade shader works
# on the finished picture (see APRON_FADE_START). The group sits at z -3:
# under the FloorLayer, which is under everything else.
var apron_group: CanvasGroup = null
var apron_layer: Node2D = null

# Flat ground clutter - bones, scorch, tyre-flattened scrap, the extraction
# zone's signal panels. Shares the floor's z index and is added straight after
# it, so it paints ON the ground: above the tiles and their contact shadows,
# below fx_ground (-1), the Board's own highlights (0) and every unit. A decal
# is scenery that can never be stood in front of, which is exactly why it does
# not go in `Entities` with the standing props - nothing here occludes anybody,
# so nothing here has to fade. Battle fills it; Board only owns the node.
var decal_layer: Node2D = null

# Fuel drums the selected unit could put a round into. Drawn hotter than an
# attack tile so a hazard never reads as an enemy.
var hazard_cells: Dictionary = {}

var cache_cells: Dictionary = {}
var extract_cells: Dictionary = {}
var extract_armed := false
var _pulse := 0.0

# Live smoke: blocks line of sight for both sides but never movement.
var smoke_cells: Dictionary = {}
# Preview footprint while a grenade is being aimed; true = frag, false = smoke.
var blast_cells: Dictionary = {}
var blast_is_frag := true

var watch_cells: Dictionary = {}
# Cells any enemy could shoot next turn (selection-independent; cleared
# only via set_danger, never by clear_highlights).
var danger_cells: Dictionary = {}

## Positions an informant gave away before the first shot. A SEPARATE set from
## danger_cells on purpose: danger is recomputed every time the selection or the
## toggle changes, so intel written into it survived exactly until the next
## refresh - and while it was there it lit every cell the marked enemies could
## shoot, which is the whole danger overlay rather than three positions. This is
## written once at deploy and nothing recomputes it.
var intel_cells: Dictionary = {}


func _ready() -> void:
	apron_group = CanvasGroup.new()
	apron_group.name = "Apron"
	apron_group.z_index = -3
	var apron_mat := ShaderMaterial.new()
	apron_mat.shader = preload("res://assets/shaders/apron_fade.gdshader")
	apron_mat.set_shader_parameter("half_tile", Vector2(TILE_W / 2.0, TILE_H / 2.0))
	apron_mat.set_shader_parameter("rings", float(APRON_RINGS))
	apron_mat.set_shader_parameter("fade_start", APRON_FADE_START)
	apron_mat.set_shader_parameter("fade_exp", APRON_FADE_EXP)
	apron_mat.set_shader_parameter("board_size", Vector2(size))
	apron_group.material = apron_mat
	add_child(apron_group)
	apron_layer = FloorLayer.ApronLayer.new()
	apron_layer.board = self
	apron_group.add_child(apron_layer)
	floor_layer = FloorLayer.new()
	floor_layer.board = self
	floor_layer.z_index = -2
	add_child(floor_layer)
	decal_layer = Node2D.new()
	decal_layer.name = "Decals"
	decal_layer.z_index = -2  # same band as the floor; tree order puts it above
	decal_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(decal_layer)


func set_highlights(moves: Dictionary, dests: Dictionary,
		attacks: Array[Vector2i], hazards := {}) -> void:
	move_cells = moves
	move_dests = dests
	attack_cells = attacks
	hazard_cells = hazards
	queue_redraw()


func set_hover(cell: Vector2i, path: Array[Vector2i], p_aim_from: Vector2i,
		p_aim_covered := false, p_aim_flanking := false) -> void:
	if cell == hover_cell and path == path_preview and p_aim_from == aim_from \
			and p_aim_covered == aim_covered and p_aim_flanking == aim_flanking:
		return
	hover_cell = cell
	path_preview = path
	aim_from = p_aim_from
	aim_covered = p_aim_covered
	aim_flanking = p_aim_flanking
	queue_redraw()


func set_watch_cells(cells: Dictionary) -> void:
	watch_cells = cells
	queue_redraw()


func set_danger(cells: Dictionary) -> void:
	danger_cells = cells
	queue_redraw()


func set_cover_overlay(focus: Vector2i, dests: Dictionary) -> void:
	if focus == cover_focus and dests == cover_dests:
		return
	cover_focus = focus
	cover_dests = dests
	queue_redraw()


func set_objectives(caches: Dictionary, extracts: Dictionary, armed: bool) -> void:
	cache_cells = caches
	extract_cells = extracts
	extract_armed = armed
	set_process(not caches.is_empty() or not extracts.is_empty())
	queue_redraw()


## Objective markers breathe so they stay findable on a busy board.
func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 2.2, TAU)
	queue_redraw()


func set_smoke(cells: Dictionary) -> void:
	smoke_cells = cells
	queue_redraw()


func set_blast_cells(cells: Dictionary, is_frag: bool) -> void:
	if cells == blast_cells and is_frag == blast_is_frag:
		return
	blast_cells = cells
	blast_is_frag = is_frag
	queue_redraw()


func set_fire_mode(value: int) -> void:
	if fire_mode != value:
		fire_mode = value
		queue_redraw()


func clear_highlights() -> void:
	hover_cell = NO_CELL
	path_preview = []
	aim_from = NO_CELL
	aim_covered = false
	aim_flanking = false
	set_blast_cells({}, true)  # smoke is board state and deliberately survives
	set_cover_overlay(NO_CELL, {})
	set_highlights({}, {}, [])


## Load a level definition: cell kinds from the map chars plus structure
## footprints, then rebuild the floor with the level's noise character.
func set_level(data: Dictionary) -> void:
	size = data.size
	map_rows = data.map
	_structure_cells = {}
	for s: Dictionary in data.structures:
		var anchor: Vector2i = s.anchor
		var struct_size: Vector2i = s.size
		for dy in struct_size.y:
			for dx in struct_size.x:
				_structure_cells[anchor + Vector2i(dx, dy)] = true
	_kind = []
	for y in size.y:
		var row: Array[int] = []
		for x in size.x:
			var cell := Vector2i(x, y)
			var ch: String = map_rows[y][x]
			if ch == "#" or ch == "W" or _structure_cells.has(cell):
				row.append(CellKind.BLOCK)
			elif ch == "=":
				row.append(CellKind.WIRE)
			elif ch == "j" or ch == "d" or ch == "s" or ch == "c":
				# A fuel drum is cover you can shoot over, exactly like junk -
				# right up until somebody sets it off. Sandbags and the Thirst's
				# own crate stacks are the same tier; what differs is that
				# somebody built them there on purpose.
				row.append(CellKind.COVER)
			else:
				row.append(CellKind.OPEN)
		_kind.append(row)
	var floor_name := _resolve_floor(data.get("floor", DEFAULT_FLOOR))
	_floor_name = floor_name
	_floor_sheet = FLOOR_SHEETS[floor_name]
	_floor_regions = SHEET_REGIONS[floor_name]
	_floor_catalog = TileCatalog.load_for(_floor_sheet.resource_path)
	_mood = floor_mood_of(floor_name)
	_floor_accent = float(_mood.get("accent", ACCENT_CHANCE))
	_floor_spacing = int(_mood.get("spacing", ACCENT_MIN_SPACING))
	_inset_sheet = null
	_inset_rect = Rect2i()
	_inset_name = ""
	_inset_catalog = {}
	_inset_accent = _floor_accent
	_inset_spacing = _floor_spacing
	var inset: Dictionary = data.get("floor_inset", {})
	if not inset.is_empty():
		var inset_name := _resolve_floor(inset.get("floor", DEFAULT_FLOOR))
		_inset_name = inset_name
		_inset_rect = inset.get("rect", Rect2i())
		_inset_sheet = FLOOR_SHEETS[inset_name]
		_inset_regions = SHEET_REGIONS[inset_name]
		_inset_catalog = TileCatalog.load_for(_inset_sheet.resource_path)
		_inset_accent = float(floor_mood_of(inset_name).get("accent", ACCENT_CHANCE))
		_inset_spacing = int(floor_mood_of(inset_name).get("spacing", ACCENT_MIN_SPACING))
	_zone_map = data.get("zone_map", [])
	_road_map = data.get("roads", [])
	_road_catalog = {}
	if not _road_map.is_empty() or data.has("apron_roads"):
		if ROAD_SHEETS.has(floor_name):
			_road_catalog = TileCatalog.load_road_for(
					(ROAD_SHEETS[floor_name] as Texture2D).resource_path)
		if _road_catalog.is_empty():
			push_warning("[Board] level paints roads but floor '%s' has no road set"
					% floor_name)
	_apron_enabled = bool(data.get("apron", true))
	_build_apron_roads(data)
	var thresholds: Array = data.get("zone_thresholds", [-0.12, 0.22])
	_build_tile_cache(data.get("zone_seed", 7), data.get("shade_seed", 13), thresholds)
	queue_redraw()
	if floor_layer != null:
		floor_layer.queue_redraw()
	if apron_group != null:
		(apron_group.material as ShaderMaterial).set_shader_parameter(
				"board_size", Vector2(size))
		apron_layer.queue_redraw()


## Contact shadows for the apron's scenery, from ApronScenery. A setter for
## the same reason set_prop_shadows is one: the ApronLayer paints them and
## only repaints when told.
func set_apron_shadows(shadows: Array) -> void:
	apron_shadows = shadows
	if apron_layer != null:
		apron_layer.queue_redraw()


## Contact shadows for props spawned from objective lists rather than map
## chars. Routed through a setter because the FloorLayer paints them, and it
## only repaints when told the world changed.
func set_prop_shadows(shadows: Dictionary) -> void:
	prop_shadows = shadows
	if floor_layer != null:
		floor_layer.queue_redraw()


## The air over a named ground. A sheet with no entry inherits the desert's,
## which is what the whole game looked like before moods existed.
static func floor_mood_of(name: String) -> Dictionary:
	return FLOOR_MOODS.get(name, FLOOR_MOODS[DEFAULT_FLOOR])


## What this board is currently lit like. Scenery reads it to tint itself.
func floor_mood() -> Dictionary:
	return _mood


## A ground-appropriate shadow at the caller's own strength. Callers keep their
## own alphas - a corpse still pools darker than a rock - and this scales all of
## them together so shadows stay equally readable on pale salt and dark ash.
func shadow_tone(alpha: float) -> Color:
	var tone: Color = _mood.get("shadow", SHADOW_COLOR)
	tone.a = clampf(alpha * float(_mood.get("shadow_gain", 1.0)), 0.0, 1.0)
	return tone


## The road cells past the boundary. Two sources: the level's authored
## "apron_roads" list (a lane that only exists out there, like the one out of
## the garrison gate), and the automatic continuation of any painted road
## that reaches the board edge - a lane a level says comes in FROM somewhere
## now visibly does, straight out to where the apron dissolves.
func _build_apron_roads(data: Dictionary) -> void:
	apron_roads = {}
	if not _apron_enabled or _road_catalog.is_empty():
		return
	for cell: Vector2i in data.get("apron_roads", []):
		if not in_bounds(cell):
			apron_roads[cell] = true
	for y in size.y:
		for x in size.x:
			if not _is_road(Vector2i(x, y)):
				continue
			var outward: Array[Vector2i] = []
			if x == 0:
				outward.append(Vector2i(-1, 0))
			if x == size.x - 1:
				outward.append(Vector2i(1, 0))
			if y == 0:
				outward.append(Vector2i(0, -1))
			if y == size.y - 1:
				outward.append(Vector2i(0, 1))
			for dir: Vector2i in outward:
				for i in range(1, APRON_RINGS + 1):
					apron_roads[Vector2i(x, y) + dir * i] = true


## The apron dissolve at a cell: 0 solid ground, 1 fully the background. The
## GDScript twin of apron_fade.gdshader's falloff - scenery standing on the
## apron reads it so a tower fades exactly as fast as the ground it stands on.
func apron_fade_at(cell: Vector2i) -> float:
	var dx := maxf(maxf(-0.5 - float(cell.x),
			float(cell.x) - (float(size.x) - 0.5)), 0.0)
	var dy := maxf(maxf(-0.5 - float(cell.y),
			float(cell.y) - (float(size.y) - 0.5)), 0.0)
	var d := maxf(dx, dy)
	return lerpf(APRON_FADE_START, 1.0,
			pow(clampf(d / float(APRON_RINGS), 0.0, 1.0), APRON_FADE_EXP))


## A floor name, or the desert fallback if the level asks for one we lack.
func _resolve_floor(name: String) -> String:
	if FLOOR_SHEETS.has(name):
		return name
	push_error("[Board] unknown floor '%s', falling back to %s"
			% [name, DEFAULT_FLOOR])
	return DEFAULT_FLOOR


## Diamond center of a cell, in Board-local pixels (2:1 isometric projection).
func cell_to_local(cell: Vector2i) -> Vector2:
	return Vector2(
		(cell.x - cell.y) * TILE_W / 2.0,
		(cell.x + cell.y) * TILE_H / 2.0,
	)


func cell_to_global(cell: Vector2i) -> Vector2:
	return to_global(cell_to_local(cell))


func global_to_cell(point: Vector2) -> Vector2i:
	var p := to_local(point)
	var fx := p.x / (TILE_W / 2.0)
	var fy := p.y / (TILE_H / 2.0)
	return Vector2i(roundi((fx + fy) / 2.0), roundi((fy - fx) / 2.0))


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < size.x and cell.y >= 0 and cell.y < size.y


func cell_kind(cell: Vector2i) -> CellKind:
	return _kind[cell.y][cell.x]


func is_blocker(cell: Vector2i) -> bool:
	return cell_kind(cell) == CellKind.BLOCK


func is_walkable(cell: Vector2i) -> bool:
	return cell_kind(cell) == CellKind.OPEN


func map_char(cell: Vector2i) -> String:
	return map_rows[cell.y][cell.x] if in_bounds(cell) else ""


func is_structure(cell: Vector2i) -> bool:
	return _structure_cells.has(cell)


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Facing sector (0=E, 1=SE .. 7=NE) pointing from one cell toward another.
## Uses the same screen-space formula as Unit.set_facing, so a previewed
## flank and a resolved flank can never disagree. -1 for the same cell.
static func sector_from_to(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return -1
	var d := to - from
	var screen := Vector2(
			float(d.x - d.y) * TILE_W / 2.0,
			float(d.x + d.y) * TILE_H / 2.0)
	return wrapi(roundi(screen.angle() / (TAU / 8.0)), 0, 8)


## True if a straight shot between the two cell centers crosses no full
## blocker and no smoke. Junk (COVER) does not stop sight - it attenuates
## damage instead. Samples the segment in cell space; endpoints themselves are
## ignored, so a unit standing in its own smoke can still shoot out of it and
## be shot at - only lines that pass THROUGH the cloud are cut.
## Every sight test in the game routes through here, so smoke shortens overwatch
## cones, hides the danger overlay, and blinds the AI without further plumbing.
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var a := Vector2(from)
	var b := Vector2(to)
	var steps := int(a.distance_to(b) * 4.0) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		var cell := Vector2i(roundi(p.x), roundi(p.y))
		if cell == from or cell == to:
			continue
		if is_blocker(cell) or smoke_cells.has(cell):
			return false
	return true


# ------------------------------------------------------------------- cover --
# Cover is a property of the cell you STAND on, not of the line a bullet
# happens to cross. A unit is covered from a direction when the neighbouring
# cell that way is something to get behind - so hugging a wall is a decision,
# and the ground between two positions is a route rather than a lottery.
#
# Junk gives HALF cover: you can shoot over it, and it can be shot over, at
# reduced damage. Rock, wall and building give FULL cover: much harder to hit
# past, and it blocks sight both ways - which is what the peek rule exists to
# work around.

enum CoverLevel { NONE, HALF, FULL }

## An adjacent blocker shields the sector pointing at it plus the sector each
## side, so one wall covers a 135 degree wedge and an inside corner covers most
## of the field. Matches the 135 degree front arc units already use.
const COVER_SPREAD := 1


## Note the map edge grants nothing. Putting your back to it is a good
## instinct, but this model hands out cover by sector, and the sectors an
## off-map neighbour would protect are the ones a shooter would have to stand
## off-map to occupy - so no shot on any shipped level ever received edge cover
## (tools/check_cover_rules.gd measures this: 0 pairs across all 7 maps).
## Returning FULL here only advertised it: 33-46 cells per map drew the cover
## dot and the full-cover bars, and units visibly crouched on them, for
## protection that could never apply. If edge cover should be real, make it
## real in cover_map_at - do not restore the promise here.
func cover_level_of(cell: Vector2i) -> CoverLevel:
	if not in_bounds(cell):
		return CoverLevel.NONE
	match cell_kind(cell):
		CellKind.BLOCK:
			return CoverLevel.FULL
		CellKind.COVER:
			return CoverLevel.HALF
	return CoverLevel.NONE


## Best cover this cell has against each of the 8 facing sectors.
## Returns sector -> CoverLevel for every sector that has any.
func cover_map_at(cell: Vector2i) -> Dictionary:
	var out := {}
	for dir in DIRS:
		var level := cover_level_of(cell + dir)
		if level == CoverLevel.NONE:
			continue
		var sector := sector_from_to(cell, cell + dir)
		for offset in range(-COVER_SPREAD, COVER_SPREAD + 1):
			var s := wrapi(sector + offset, 0, 8)
			if int(out.get(s, CoverLevel.NONE)) < int(level):
				out[s] = level
	return out


## The cover a target standing at `target` has against a shot from `from`.
func cover_between(from: Vector2i, target: Vector2i) -> CoverLevel:
	var sector := sector_from_to(target, from)
	return cover_map_at(target).get(sector, CoverLevel.NONE)


## Which neighbouring cell is actually doing the protecting, so effects can
## spark off the right piece of scenery. NO_CELL when the target is exposed.
func cover_source(from: Vector2i, target: Vector2i) -> Vector2i:
	var want := sector_from_to(target, from)
	var best := NO_CELL
	var best_level := CoverLevel.NONE
	for dir in DIRS:
		var level := cover_level_of(target + dir)
		if level == CoverLevel.NONE:
			continue
		var sector := sector_from_to(target, target + dir)
		if absi(wrapi(want - sector + 4, 0, 8) - 4) > COVER_SPREAD:
			continue
		if int(level) > int(best_level):
			best_level = level
			best = target + dir
	return best


## True if this cell is worth moving to for protection at all.
func has_any_cover(cell: Vector2i) -> bool:
	return not cover_map_at(cell).is_empty()


## Line of sight that ignores a given set of cells - used by the peek rule to
## look past the specific piece of cover the shooter is hugging, and nothing
## else on the line.
func _los_ignoring(from: Vector2i, to: Vector2i, ignore: Dictionary) -> bool:
	var a := Vector2(from)
	var b := Vector2(to)
	var steps := int(a.distance_to(b) * 4.0) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		var cell := Vector2i(roundi(p.x), roundi(p.y))
		if cell == from or cell == to or ignore.has(cell):
			continue
		if is_blocker(cell) or smoke_cells.has(cell):
			return false
	return true


## Can a shooter at `from` lean around the edge of its own full cover to hit
## `to`? Only fires when the direct line is blocked. The shooter does not move:
## it leans **perpendicular** to whatever it is hugging and shoots past the
## edge, so the piece being hugged stops blocking but nothing else does.
##
## That is what separates a corner from a wall. Lean past the end of a wall run
## and the shot is there; lean against the middle of an unbroken wall and the
## next section of the same wall is still in the way.
## Returns the cell leaned toward, or NO_CELL when there is no angle.
func peek_origin(from: Vector2i, to: Vector2i) -> Vector2i:
	if has_line_of_sight(from, to):
		return NO_CELL  # nothing to lean around
	# Only full cover is worth leaning past; junk never blocked sight anyway.
	# in_bounds first: off-map neighbours read as FULL so that a unit can put
	# its back to the map edge, but there is no scenery there to lean around,
	# and treating it as such handed every unit on the perimeter a free shot.
	var hugged := {}
	for dir in DIRS:
		if in_bounds(from + dir) and cover_level_of(from + dir) == CoverLevel.FULL:
			hugged[from + dir] = true
	if hugged.is_empty():
		return NO_CELL
	for cover_cell: Vector2i in hugged:
		var d: Vector2i = cover_cell - from
		for perp in [Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:
			var side: Vector2i = from + perp
			if not in_bounds(side) or is_blocker(side) or smoke_cells.has(side):
				continue
			# Ignore only the one piece being leaned past - not every blocker
			# adjacent to the shooter. Passing the whole `hugged` set let a unit
			# hugging two walls lean around one and shoot through the other,
			# which is exactly the wall-vs-corner distinction this rule exists
			# to draw.
			if _los_ignoring(side, to, {cover_cell: true}):
				return side
	return NO_CELL


func can_peek(from: Vector2i, to: Vector2i) -> bool:
	return peek_origin(from, to) != NO_CELL


## Can a shooter at `from` engage `to` at all - straight down the line, or by
## leaning around the edge of whatever it is tucked behind?
func can_engage(from: Vector2i, to: Vector2i) -> bool:
	return has_line_of_sight(from, to) or peek_origin(from, to) != NO_CELL


## BFS from start up to max_range steps. Walls and cells where blocked.call(cell)
## is true are impassable. Returns {reachable_cell: came_from_cell}, excluding start.
func flood_fill(start: Vector2i, max_range: int, blocked: Callable) -> Dictionary:
	var came_from := {start: start}
	var dist := {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		if dist[cur] == max_range:
			continue
		for dir in DIRS:
			var nxt := cur + dir
			if not in_bounds(nxt) or came_from.has(nxt):
				continue
			if not is_walkable(nxt) or blocked.call(nxt):
				continue
			came_from[nxt] = cur
			dist[nxt] = dist[cur] + 1
			frontier.push_back(nxt)
	came_from.erase(start)
	return came_from


## Ordered path (first step .. dest) from a flood_fill result.
func reconstruct_path(came_from: Dictionary, dest: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [dest]
	while came_from.has(path[0]):
		path.push_front(came_from[path[0]])
	path.pop_front()  # drop the start cell itself
	return path


func _diamond(cell: Vector2i) -> PackedVector2Array:
	var c := cell_to_local(cell)
	return PackedVector2Array([
		c + Vector2(0, -TILE_H / 2.0),
		c + Vector2(TILE_W / 2.0, 0),
		c + Vector2(0, TILE_H / 2.0),
		c + Vector2(-TILE_W / 2.0, 0),
	])


## Deterministic per-cell pseudo-random in [0, 1); salt separates streams.
static func _hash01(cell: Vector2i, salt: int) -> float:
	return float(absi(cell.x * 92821 + cell.y * 31337 + salt * 53987) % 997) / 997.0


## A cell remapped so that a SECOND hash taken off it is independent of a first.
##
## _hash01 is linear in its salt: hash(cell, s) = (A(cell) + 149*s) mod 997,
## because 53987 mod 997 is 149. Two salts are therefore a fixed offset apart
## and never decorrelate - so gating a cell on one salt and then picking with
## another confines the pick to a narrow band of the range. That is not
## theoretical: the ground detritus gated at 17% on salt 12 and picked on salt
## 13, which pinned every pick to index 1 or 2, so six of the eight decals never
## appeared on any board in the game and 60% of them were the same sprite.
##
## Translating the cell does NOT fix it - a translation is another offset. The
## coordinates have to be SCALED, which is the only thing that changes the
## structure of A(cell). Pass a different (a, b) per stream to get streams that
## are independent of each other as well as of the gate.
static func decorrelate(cell: Vector2i, a: int, b: int) -> Vector2i:
	return Vector2i(cell.x * a + 41, cell.y * b + 89)


## Precompute each cell's tile region, mirror flag, and shade tint.
## Everything is seeded/hashed, so a level's floor is identical every run.
##
## When a sheet ships transition sets in its sidecar, zone boundaries resolve
## corner-Wang style: cell zones are sampled onto the (w+1)x(h+1) vertex grid
## and a cell whose corners disagree draws the transition tile indexed by
## which corners sit in the upper terrain. Sheets without sidecars (all of
## them today) skip those passes and land byte-identical to the legacy path.
func _build_tile_cache(zone_seed: int, shade_seed: int, thresholds: Array) -> void:
	var zone_noise := FastNoiseLite.new()
	zone_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	zone_noise.seed = zone_seed
	zone_noise.frequency = ZONE_NOISE_FREQ
	var shade_noise := FastNoiseLite.new()
	shade_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shade_noise.seed = shade_seed
	shade_noise.frequency = 0.09

	# 1. Cell zone pass - unchanged classification, so uniform cells pick the
	# same variants they always have.
	var zones: Array = []
	for y in size.y:
		var zone_row: Array[int] = []
		for x in size.x:
			zone_row.append(_cell_zone(Vector2i(x, y), zone_noise, thresholds))
		zones.append(zone_row)

	# 2-4. Vertex passes, run only when some sidecar actually ships transition
	# art - without any, corners can never change what a cell draws.
	var cross_key := "%s|%s" % [_floor_name, _inset_name]
	var has_zone_sets := _has_set(_floor_catalog, "0|1") \
			or _has_set(_floor_catalog, "1|2") \
			or _has_set(_inset_catalog, "0|1") or _has_set(_inset_catalog, "1|2")
	var has_cross_set: bool = _inset_sheet != null \
			and (_has_set(_floor_catalog, cross_key)
					or _has_set(_inset_catalog, cross_key))
	var zone_verts: Array = []
	var inset_verts: Array = []
	if has_zone_sets or has_cross_set:
		zone_verts = _zone_vertices(zones)
		inset_verts = _inset_vertices()
		_settle_vertices(zone_verts)

	var accent_cells: Array[Vector2i] = []
	tile_cache = []
	for y in size.y:
		var row: Array = []
		for x in size.x:
			var cell := Vector2i(x, y)
			var zone: int = zones[y][x]
			# Which sheet this cell comes off has to be settled before the
			# accent roll, because the scatter rate belongs to the sheet.
			var sheet := _floor_sheet
			var regions := _floor_regions
			var catalog := _floor_catalog
			var accent_rate := _floor_accent
			var accent_gap := _floor_spacing
			if _inset_sheet != null and _inset_rect.has_point(cell):
				sheet = _inset_sheet
				regions = _inset_regions
				catalog = _inset_catalog
				accent_rate = _inset_accent
				accent_gap = _inset_spacing
			# Subtle brightness patches (0.94..1.0) fake large-scale lighting.
			var shade := 0.94 + 0.06 * (shade_noise.get_noise_2d(cell.x, cell.y) * 0.5 + 0.5)
			var shadow: float = DIAMOND_SHADOW if is_structure(cell) \
					else SHADOW_RADII.get(map_char(cell), 0.0)
			# 5. Corner disagreements draw transition tiles instead of the
			# uniform family: never mirrored, never accented.
			var entry := {}
			if has_cross_set or has_zone_sets:
				entry = _transition_entry(cell, catalog, zone_verts, inset_verts,
						cross_key, has_cross_set, has_zone_sets)
			if entry.is_empty():
				# Uniform cell: family variant, accent roll, mirror. The
				# legacy tables, or the sheet's own catalog when it has one.
				if catalog.is_empty():
					var family: Array = ZONE_FAMILIES[zone]
					var variant: int = family[int(_hash01(cell, 1) * family.size()) \
							% family.size()]
					if _accent_here(cell, accent_rate, accent_gap, accent_cells):
						variant = ZONE_ACCENTS[zone]
						accent_cells.append(cell)
					entry = {
						"sheet": sheet,
						"region": regions[variant],
						"flip": _hash01(cell, 3) < 0.5,
					}
				else:
					var family: Array = catalog.families[zone]
					var slot: Dictionary = family[int(_hash01(cell, 1) * family.size()) \
							% family.size()]
					var zone_accents: Array = catalog.accents[zone]
					if not zone_accents.is_empty() \
							and _accent_here(cell, accent_rate, accent_gap, accent_cells):
						slot = zone_accents[mini(
								int(_hash01(cell, 4) * zone_accents.size()),
								zone_accents.size() - 1)]
						accent_cells.append(cell)
					entry = {
						"sheet": sheet,
						"region": slot.rect,
						# Only art flagged symmetric may mirror - flipping a
						# directionally lit tile turns it against the sun.
						"flip": bool(slot.symmetric) and _hash01(cell, 3) < 0.5,
					}
			# 6. Roads pave over whatever they were laid across - family,
			# accent and transition tiles alike - so the track stays continuous
			# through a zone seam. The cell's shade and shadow stay its own.
			if not _road_catalog.is_empty() and _is_road(cell):
				var road := _road_tile(cell)
				if not road.is_empty():
					entry = road
			entry["shade"] = Color(shade, shade, shade)
			entry["shadow"] = shadow
			row.append(entry)
		tile_cache.append(row)

	# 7. The apron: the same ground continued past every edge of the arena.
	# Base family tiles only - no accents, roads, insets or transitions, because
	# detail out where nobody can walk competes with the board for the eye. The
	# zone and shade noise fields are continuous across the boundary, so terrain
	# patches and lighting drift flow over the edge instead of restarting on it.
	# Zones come straight off the noise here: _cell_zone would consult the
	# level's zone_map, whose rows would wrap under a negative index.
	apron_cache = {}
	if not _apron_enabled:
		return
	for y in range(-APRON_RINGS, size.y + APRON_RINGS):
		for x in range(-APRON_RINGS, size.x + APRON_RINGS):
			var cell := Vector2i(x, y)
			if in_bounds(cell):
				continue
			var n := zone_noise.get_noise_2d(x, y)
			var zone := 0 if n < thresholds[0] else (1 if n < thresholds[1] else 2)
			var entry := {}
			# Same picks and salts as the uniform-cell branch above, so a tile
			# at the boundary continues its in-board neighbourhood's character.
			if _floor_catalog.is_empty():
				var family: Array = ZONE_FAMILIES[zone]
				var variant: int = family[int(_hash01(cell, 1) * family.size()) \
						% family.size()]
				entry = {
					"sheet": _floor_sheet,
					"region": _floor_regions[variant],
					"flip": _hash01(cell, 3) < 0.5,
				}
			else:
				var family: Array = _floor_catalog.families[zone]
				var slot: Dictionary = family[int(_hash01(cell, 1) * family.size()) \
						% family.size()]
				entry = {
					"sheet": _floor_sheet,
					"region": slot.rect,
					"flip": bool(slot.symmetric) and _hash01(cell, 3) < 0.5,
				}
			# A road cell paves over its base tile exactly as in-board roads
			# do, so a lane runs unbroken from the arena to where it dissolves.
			if apron_roads.has(cell) and not _road_catalog.is_empty():
				var road := _road_tile(cell)
				if not road.is_empty():
					entry = road
			var dim := APRON_SHADE \
					* (0.94 + 0.06 * (shade_noise.get_noise_2d(x, y) * 0.5 + 0.5))
			entry["shade"] = Color(dim, dim, dim)
			apron_cache[cell] = entry


## True where the level's optional "roads" overlay paints an 'r'. Rows shorter
## than the map read as no road, same as zone_map's forgiveness.
func _is_road(cell: Vector2i) -> bool:
	if not in_bounds(cell) or cell.y >= _road_map.size():
		return false
	var row := str(_road_map[cell.y])
	return cell.x < row.length() and row[cell.x] == "r"


## True where a road runs, on the board or on the apron past it. The apron
## side matters to both worlds: an apron road cell reads its neighbours with
## this, and a border road cell that used to end in a cap now opens toward
## its continuation outside.
func _road_at(cell: Vector2i) -> bool:
	return _is_road(cell) or apron_roads.has(cell)


## The road tile whose open edges match this cell's road neighbours, or {}
## when the set lacks that mask. Bit order is TileCatalog.EDGE_BITS: bit0
## north (y-1), bit1 east (x+1), bit2 south (y+1), bit3 west (x-1). Works for
## apron cells as well as board cells - it only ever looks at neighbours.
func _road_tile(cell: Vector2i) -> Dictionary:
	var mask := 0
	if _road_at(cell + Vector2i(0, -1)):
		mask |= 1
	if _road_at(cell + Vector2i(1, 0)):
		mask |= 2
	if _road_at(cell + Vector2i(0, 1)):
		mask |= 4
	if _road_at(cell + Vector2i(-1, 0)):
		mask |= 8
	var rect: Rect2 = _road_catalog.tiles[mask]
	if rect.size.x <= 0.0:
		return {}
	return {"sheet": _road_catalog.sheet, "region": rect, "flip": false}


## Which terrain zone a cell belongs to: the level's optional "zone_map"
## overlay wins where it paints a digit, the noise threshold split decides
## everything else - which is all of it on every shipped level.
func _cell_zone(cell: Vector2i, zone_noise: FastNoiseLite, thresholds: Array) -> int:
	if cell.y < _zone_map.size():
		var row := str(_zone_map[cell.y])
		if cell.x < row.length() and row[cell.x] != ".":
			return clampi(int(row[cell.x]), 0, 2)
	var n := zone_noise.get_noise_2d(cell.x, cell.y)
	return 0 if n < thresholds[0] else (1 if n < thresholds[1] else 2)


## The shared accent roll: open sand only, hashed per cell, and never within
## `gap` Chebyshev cells of an accent already placed this build.
func _accent_here(cell: Vector2i, rate: float, gap: int,
		placed: Array[Vector2i]) -> bool:
	if map_char(cell) != "." or is_structure(cell):
		return false
	if _hash01(cell, 2) >= rate:
		return false
	for other in placed:
		if maxi(absi(other.x - cell.x), absi(other.y - cell.y)) <= gap:
			return false
	return true


## Cell zones sampled onto the dual (w+1)x(h+1) grid: a vertex takes the
## highest zone among its up-to-four in-bounds cells, so the upper terrain
## owns its own edges and the transition art always faces downhill.
func _zone_vertices(zones: Array) -> Array:
	var verts: Array = []
	for vy in size.y + 1:
		var vrow: Array[int] = []
		for vx in size.x + 1:
			var best := 0
			for cell in [Vector2i(vx - 1, vy - 1), Vector2i(vx, vy - 1),
					Vector2i(vx - 1, vy), Vector2i(vx, vy)]:
				if in_bounds(cell):
					best = maxi(best, zones[cell.y][cell.x])
			vrow.append(best)
		verts.append(vrow)
	return verts


## True at every vertex touching a cell inside the floor inset - the built
## ground is the upper terrain of the cross-floor transition set.
func _inset_vertices() -> Array:
	var verts: Array = []
	for vy in size.y + 1:
		var vrow: Array[bool] = []
		for vx in size.x + 1:
			var inside := false
			if _inset_sheet != null:
				for cell in [Vector2i(vx - 1, vy - 1), Vector2i(vx, vy - 1),
						Vector2i(vx - 1, vy), Vector2i(vx, vy)]:
					if in_bounds(cell) and _inset_rect.has_point(cell):
						inside = true
						break
			vrow.append(inside)
		verts.append(vrow)
	return verts


## No transition set spans more than one zone step, so a cell whose corners
## span two ({0, 2}) cannot be drawn. Promote its lowest corners a step in the
## shared vertex array and re-check; two passes settle the worst case of a
## zone-0 cell cornering a zone-2 cell.
func _settle_vertices(verts: Array) -> void:
	for fixup_pass in 2:
		var changed := false
		for y in size.y:
			for x in size.x:
				var corners: Array[int] = [verts[y][x], verts[y][x + 1],
						verts[y + 1][x + 1], verts[y + 1][x]]
				var lo: int = corners.min()
				if corners.max() - lo < 2:
					continue
				for v: Vector2i in [Vector2i(x, y), Vector2i(x + 1, y),
						Vector2i(x + 1, y + 1), Vector2i(x, y + 1)]:
					if verts[v.y][v.x] == lo:
						verts[v.y][v.x] = lo + 1
						changed = true
		if not changed:
			return


## The transition tile for a cell whose corners disagree, or {} for a uniform
## cell (or when the needed set is not shipped, in which case the caller falls
## back to the uniform family). Inset boundaries outrank zone seams: the edge
## of a built floor is authored, a noise seam is weather.
##
## Corner order everywhere is the screen-space diamond's [top, right, bottom,
## left], mapping to grid vertices (x,y), (x+1,y), (x+1,y+1), (x,y+1); mask
## bit i is set when corner i sits in the upper terrain.
func _transition_entry(cell: Vector2i, catalog: Dictionary, zone_verts: Array,
		inset_verts: Array, cross_key: String, has_cross_set: bool,
		has_zone_sets: bool) -> Dictionary:
	var x := cell.x
	var y := cell.y
	if has_cross_set:
		var flags: Array[bool] = [inset_verts[y][x], inset_verts[y][x + 1],
				inset_verts[y + 1][x + 1], inset_verts[y + 1][x]]
		if flags.has(true) and flags.has(false):
			var mask := 0
			for i in 4:
				if flags[i]:
					mask |= 1 << i
			var entry := _set_tile(_floor_catalog, cross_key, mask)
			if entry.is_empty():
				entry = _set_tile(_inset_catalog, cross_key, mask)
			if not entry.is_empty():
				return entry
	if has_zone_sets:
		var corners: Array[int] = [zone_verts[y][x], zone_verts[y][x + 1],
				zone_verts[y + 1][x + 1], zone_verts[y + 1][x]]
		var lo: int = corners.min()
		if corners.max() > lo:
			var mask := 0
			for i in 4:
				if corners[i] > lo:
					mask |= 1 << i
			return _set_tile(catalog, "%d|%d" % [lo, lo + 1], mask)
	return {}


## One tile out of a named transition set: {sheet, region, flip=false}, or {}
## when the set (or that particular mask) is missing.
static func _set_tile(catalog: Dictionary, key: String, mask: int) -> Dictionary:
	var sets: Dictionary = catalog.get("transitions", {})
	if not sets.has(key):
		return {}
	var set_data: Dictionary = sets[key]
	var rect: Rect2 = set_data.tiles[mask]
	if rect.size.x <= 0.0:
		return {}
	return {"sheet": set_data.sheet, "region": rect, "flip": false}


static func _has_set(catalog: Dictionary, key: String) -> bool:
	return catalog.get("transitions", {}).has(key)


func _draw() -> void:
	if tile_cache.is_empty():
		return
	# The floor itself - tiles, haze, and every contact shadow - is painted by
	# the FloorLayer below. From here up it is all live overlay.
	if show_grid:
		# Debug escape hatch: the full lattice over every cell.
		for y in size.y:
			for x in size.x:
				var outline := _diamond(Vector2i(x, y))
				outline.append(outline[0])
				draw_polyline(outline, GRID_LINE, 1.5, true)
	else:
		# At rest the board is a place. The grid surfaces as corner ticks on
		# just the cells a selected unit could route through but not stop on -
		# the one moment tile boundaries are actually being read.
		for cell: Vector2i in move_cells:
			if move_dests.has(cell):
				continue
			var tick := _diamond(cell)
			var tick_centre := cell_to_local(cell)
			for vertex in tick:
				draw_line(vertex,
						vertex + (tick_centre - vertex).normalized() * GRID_TICK_LEN,
						GRID_TICK, 1.5, true)
	# Smoke is world, not overlay: it goes down with the props so every
	# gameplay marking still reads on top of it.
	for cell: Vector2i in smoke_cells:
		var s := _diamond(cell)
		draw_colored_polygon(s, SMOKE_FILL)
		var ring := s.duplicate()
		ring.append(ring[0])
		draw_polyline(ring, SMOKE_EDGE, 2.0, true)
	# Objectives sit above smoke and below the move/attack overlays: they are
	# where you are going, not what you can do this instant.
	var breath := 0.5 + 0.5 * sin(_pulse)
	for cell: Vector2i in extract_cells:
		var e := _diamond(cell)
		draw_colored_polygon(e, EXTRACT_ARMED_FILL if extract_armed else EXTRACT_FILL)
		var e_ring := e.duplicate()
		e_ring.append(e_ring[0])
		if extract_armed:
			draw_polyline(e_ring, EXTRACT_ARMED_EDGE.lerp(EXTRACT_EDGE, breath), 2.5, true)
		else:
			draw_polyline(e_ring, EXTRACT_EDGE, 1.5, true)
	for cell: Vector2i in cache_cells:
		var in_reach: bool = cache_cells[cell]
		var k := _diamond(cell)
		draw_colored_polygon(k, CACHE_FILL)
		var k_ring := k.duplicate()
		k_ring.append(k_ring[0])
		var edge := CACHE_REACH_EDGE if in_reach else CACHE_EDGE
		draw_polyline(k_ring, edge.lerp(CACHE_FILL, breath * 0.6),
				3.0 if in_reach else 2.0, true)
	# Informant intel: a ring on the cell somebody is standing on, under the
	# danger hatching so the two read as different claims - one is "he is here",
	# the other is "he can shoot here".
	for cell: Vector2i in intel_cells:
		var ring := _diamond(cell)
		ring.append(ring[0])
		draw_polyline(ring, INTEL_EDGE, 2.0, true)
	for cell: Vector2i in danger_cells:
		var d := _diamond(cell)
		draw_colored_polygon(d, DANGER_FILL)
		for f in [0.25, 0.5, 0.75]:
			draw_line(d[3].lerp(d[2], f), d[0].lerp(d[1], f), DANGER_HATCH, 1.0, true)
	# Overwatch arcs, hatched on the opposite diagonal from danger so the
	# two stay legible where they overlap.
	for cell: Vector2i in watch_cells:
		var hostile: bool = watch_cells[cell]
		var w := _diamond(cell)
		var ally_fill := WATCH_FILL_ALLY_HC if high_contrast else WATCH_FILL_ALLY
		draw_colored_polygon(w, WATCH_FILL if hostile else ally_fill)
		var hatch := WATCH_HATCH if hostile \
				else (WATCH_HATCH_ALLY_HC if high_contrast else WATCH_HATCH_ALLY)
		for f in [0.3, 0.6]:
			draw_line(w[3].lerp(w[0], f), w[2].lerp(w[1], f), hatch, 1.0, true)
	for cell: Vector2i in move_dests:
		draw_colored_polygon(_diamond(cell), MOVE_HL)
	# A dot marks a reachable tile that has cover of some kind, so a bound
	# from one piece of cover to the next can be planned without hovering
	# every candidate.
	for cell: Vector2i in cover_dests:
		draw_circle(cell_to_local(cell) + Vector2(0, 4.0), 3.5, COVER_DEST_DOT)
	# The focused tile gets it spelled out: a bar on every edge that has
	# something worth hiding behind, thicker for a wall than for scrap.
	if cover_focus != NO_CELL:
		var d := _diamond(cover_focus)
		var centre := cell_to_local(cover_focus)
		for dir: Vector2i in COVER_EDGES:
			var level := cover_level_of(cover_focus + dir)
			if level == CoverLevel.NONE:
				continue
			var pair: Array = COVER_EDGES[dir]
			var a: Vector2 = d[int(pair[0])]
			var b: Vector2 = d[int(pair[1])]
			var inward := (centre - (a + b) * 0.5).normalized() * 6.0
			var full := level == CoverLevel.FULL
			draw_line(a.lerp(b, 0.22) + inward, a.lerp(b, 0.78) + inward,
					COVER_FULL_PIP if full else COVER_HALF_PIP,
					5.0 if full else 3.0, true)
	var attack_color := ATTACK_HL
	if fire_mode == 1:
		attack_color = BURST_HL
	elif fire_mode == 2:
		attack_color = AUTO_HL
	elif fire_mode == 3:
		attack_color = SUPPRESS_HL
	for cell in attack_cells:
		draw_colored_polygon(_diamond(cell), attack_color)
	for cell: Vector2i in hazard_cells:
		var h := _diamond(cell)
		draw_colored_polygon(h, HAZARD_HL)
		var ring := h.duplicate()
		ring.append(ring[0])
		draw_polyline(ring, HAZARD_EDGE, 2.0, true)
	# Grenade footprint under the cursor, outlined so the exact cells that
	# will be caught are unambiguous before the throw is committed.
	# blast_cells maps cell -> damage. A frag falls off toward the corners, so
	# the softer ring is drawn dimmer and thinner-edged; smoke has no falloff
	# and stays uniform.
	var peak := 1
	for cell: Vector2i in blast_cells:
		peak = maxi(peak, int(blast_cells[cell]))
	for cell: Vector2i in blast_cells:
		var b := _diamond(cell)
		var col := BLAST_FRAG_HL if blast_is_frag else BLAST_SMOKE_HL
		var core := not blast_is_frag or int(blast_cells[cell]) >= peak
		if not core:
			col.a *= 0.45
		draw_colored_polygon(b, col)
		var edge := b.duplicate()
		edge.append(edge[0])
		draw_polyline(edge, BLAST_EDGE if core else Color(BLAST_EDGE, 0.45),
				2.0 if core else 1.0, true)
	if hover_cell != NO_CELL:
		if attack_cells.has(hover_cell):
			var hl := ATTACK_HOVER_HL
			if aim_flanking:
				hl = ATTACK_HOVER_FLANK_HL
			elif aim_covered:
				hl = ATTACK_HOVER_COVER_HL
			draw_colored_polygon(_diamond(hover_cell), hl)
		var outline := _diamond(hover_cell)
		outline.append(outline[0])
		draw_polyline(outline, HOVER_OUTLINE, 2.5, true)
	if not path_preview.is_empty():
		var centers := PackedVector2Array()
		for cell in path_preview:
			centers.append(cell_to_local(cell))
		if centers.size() >= 2:
			draw_polyline(centers, PATH_DOT, 2.0, true)
		for i in centers.size():
			draw_circle(centers[i], 8.0 if i == centers.size() - 1 else 5.0, PATH_DOT)
	if aim_from != NO_CELL and hover_cell != NO_CELL:
		var line_color := AIM_LINE
		if aim_flanking:
			line_color = AIM_LINE_FLANK
		elif aim_covered:
			line_color = AIM_LINE_COVER
		draw_dashed_line(cell_to_local(aim_from), cell_to_local(hover_cell),
				line_color, 2.0, 10.0)
