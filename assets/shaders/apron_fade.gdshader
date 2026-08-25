shader_type canvas_item;
render_mode unshaded;

// The apron's dissolve, run on the CanvasGroup that composites the
// out-of-bounds ground (see Board's APRON_* constants, which feed every
// uniform here). Working on the composited picture rather than on the tiles
// is the point of the arrangement: tiles faded one by one double-blend their
// shared edge pixels into a bright seam lattice, while a single fade over the
// finished layer cannot seam. Alpha removed here exposes the window's clear
// colour, so the fade target is the background by construction.

// A CanvasGroup with a custom material loses its built-in composite shader,
// so this one replicates it (screen_texture sample + un-premultiply, per the
// CanvasGroup class docs) and adds the fade on top.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Half a diamond's width and height in pixels - the 2:1 projection's scale.
uniform vec2 half_tile = vec2(64.0, 30.0);
// The arena's size in cells; distance past its boundary drives the fade.
uniform vec2 board_size = vec2(16.0, 10.0);
// How many cells out the ground has fully dissolved, how much of it is
// already gone at the boundary, and the easing between the two.
uniform float rings = 13.0;
uniform float fade_start = 0.2;
uniform float fade_exp = 1.35;

varying vec2 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	// The composite arrives premultiplied; return to straight alpha so the
	// faded result blends normally over the clear colour.
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	// Local pixels back to grid cells: the diamond lattice is a plain square
	// grid in this space, so "how far past the edge" is two axis clamps.
	vec2 g = vec2((lpos.x / half_tile.x + lpos.y / half_tile.y) * 0.5,
			(lpos.y / half_tile.y - lpos.x / half_tile.x) * 0.5);
	float dx = max(max(-0.5 - g.x, g.x - (board_size.x - 0.5)), 0.0);
	float dy = max(max(-0.5 - g.y, g.y - (board_size.y - 0.5)), 0.0);
	float d = max(dx, dy);
	float fade = mix(fade_start, 1.0, pow(clamp(d / rings, 0.0, 1.0), fade_exp));
	c.a *= 1.0 - fade;
	COLOR = c;
}
