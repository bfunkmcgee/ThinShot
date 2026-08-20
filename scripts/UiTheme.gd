class_name UiTheme

## The battle HUD's palette and widget styling, in one place.
##
## Everything here is chosen against the board rather than against a style
## guide: the game is warm ochre sand under a hot sky, so the interface is the
## dark side of that palette - burnt umber panels with brass edges - and never
## a neutral grey. A grey HUD over this board reads as a different program's
## window sitting on top of the game.
##
## The accent colours are deliberately the ones the BOARD already uses. Squad
## highlights, the objective beacon, the suppression tint and the danger
## hatching all have established meanings out on the tiles, and a panel that
## used a seventh shade of orange for "objective" would be teaching a second
## vocabulary for the same idea. Where a colour appears in both places it is
## quoted from the class that owns it.

# --- surfaces ----------------------------------------------------------------
## Panel interiors. Translucent, because the board runs underneath the HUD and
## the corners of the screen still want to show ground rather than a slab.
const PANEL_FILL := Color(0.086, 0.071, 0.051, 0.90)
const PANEL_FILL_DEEP := Color(0.055, 0.047, 0.035, 0.94)
## The brass edge, and the brighter corner brackets drawn over it.
const EDGE := Color(0.40, 0.33, 0.20, 0.95)
const EDGE_BRIGHT := Color(0.66, 0.53, 0.30, 1.0)
const EDGE_HOT := Color(1.0, 0.69, 0.18, 1.0)   # a panel demanding attention

# --- type --------------------------------------------------------------------
const HEADER := Color(0.85, 0.70, 0.36, 1.0)    # panel titles, small caps
const TEXT := Color(0.84, 0.79, 0.68, 1.0)
const TEXT_DIM := Color(0.56, 0.52, 0.43, 1.0)
const TEXT_BRIGHT := Color(0.96, 0.90, 0.72, 1.0)

# --- the two sides -----------------------------------------------------------
## Kestrel blue and Thirst red. Both are desaturated well below the board's
## own markers so a roster card never competes with a live target ring.
const SQUAD := Color(0.44, 0.64, 0.80, 1.0)
const SQUAD_DEEP := Color(0.13, 0.21, 0.29, 0.92)
const ENEMY := Color(0.72, 0.30, 0.25, 1.0)
const ENEMY_DEEP := Color(0.24, 0.10, 0.09, 0.92)

# --- state -------------------------------------------------------------------
## Quoted from the classes that own them, so the HUD and the board cannot drift.
const READY := Unit.PIP_FULL                    # a pip still available
const SPENT := Color(0.22, 0.20, 0.16, 0.9)     # a pip used up
const HP_LOW := Color("ff5a3c")
const WARN := Color("ffb84a")
const OBJECTIVE := ObjectiveMarks.BEACON_COLOR  # the beacon over the real thing
const DONE := Color(0.42, 0.62, 0.38, 1.0)

const FONT_TITLE := 30
const FONT_HEAD := 15
const FONT_BODY := 17
const FONT_SMALL := 14
const FONT_TINY := 12


## A flat panel style. `deep` is for wells sunk INTO a panel (a stat block
## inside a card), which want to read as a hole rather than another card.
static func panel_style(deep := false, edge := EDGE, pad := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_FILL_DEEP if deep else PANEL_FILL
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


## Buttons: a flat brass-edged chip that lifts on hover and sinks when held.
## Disabled is drawn as an empty socket rather than a greyed button, because
## half this bar is unavailable at any moment and a row of grey rectangles
## reads as broken rather than as "not now".
static func button_style(kind: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	sb.set_border_width_all(1)
	match kind:
		"hover":
			sb.bg_color = Color(0.20, 0.16, 0.10, 0.96)
			sb.border_color = EDGE_HOT
		"pressed":
			sb.bg_color = Color(0.30, 0.21, 0.09, 0.98)
			sb.border_color = EDGE_HOT
		"disabled":
			sb.bg_color = Color(0.07, 0.06, 0.05, 0.55)
			sb.border_color = Color(0.24, 0.21, 0.16, 0.7)
		_:
			sb.bg_color = Color(0.13, 0.11, 0.08, 0.92)
			sb.border_color = EDGE
	return sb


## The theme every HUD control inherits. Built once and handed to the UI root,
## so no widget carries its own theme overrides and restyling is one file.
static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_BODY

	t.set_stylebox("panel", "PanelContainer", panel_style())

	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		if state == "focus":
			# No focus ring: the bar is driven by hotkeys, and a stray outline
			# on whatever was clicked last is noise.
			t.set_stylebox(state, "Button", StyleBoxEmpty.new())
			continue
		t.set_stylebox(state, "Button", button_style(state))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT_BRIGHT)
	t.set_color("font_pressed_color", "Button", Color(1, 0.86, 0.55))
	t.set_color("font_disabled_color", "Button", Color(0.40, 0.37, 0.31, 0.75))
	t.set_font_size("font_size", "Button", FONT_SMALL)

	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", FONT_BODY)
	return t


## The head-and-shoulders slice of a unit sprite, as a portrait chip.
##
## There is no portrait art in this game and there is deliberately not going to
## be: the face on the roster card should be the same pixels as the figure on
## the board, so a soldier cannot be recognised in one place and not the other.
## The crop is measured off the sprite's own alpha bounds rather than hardcoded,
## because the canvases differ per kind (56, 60 and 64 all ship) and a fixed
## rectangle would decapitate somebody eventually.
##
## Cached per texture: this reads the image back off the GPU, which is far too
## slow to do per frame, and there are only ~13 distinct sprites in a mission.
static var _portrait_cache: Dictionary = {}

static func portrait(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var key := texture.get_rid().get_id()
	if _portrait_cache.has(key):
		return _portrait_cache[key]
	var image := texture.get_image()
	var used := image.get_used_rect() if image != null else Rect2i()
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	if used.size.x <= 0 or used.size.y <= 0:
		atlas.region = Rect2(Vector2.ZERO, texture.get_size())
	else:
		# The top 58% of the figure is head, shoulders and weapon-hand, which
		# is what makes a kind recognisable; below that every soldier is boots.
		var h := maxi(int(used.size.y * 0.58), 8)
		var w := h  # square chip, centred on the figure's own axis
		var cx := used.position.x + used.size.x / 2.0
		var x := clampf(cx - w / 2.0, 0.0, maxf(texture.get_width() - w, 0.0))
		var y := clampf(float(used.position.y) - 1.0, 0.0,
				maxf(texture.get_height() - h, 0.0))
		atlas.region = Rect2(roundf(x), roundf(y), w, h)
	_portrait_cache[key] = atlas
	return atlas
