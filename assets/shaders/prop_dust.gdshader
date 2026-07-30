shader_type canvas_item;

// Atmospheric unification for scenery.
//
// The props were generated separately over months, so they sit at different
// saturations and contrasts and read as a collage rather than one place. This
// pulls them all toward the same dusty desert palette without touching the
// source art: desaturate a little, warm-shift toward sand, then wash toward
// the horizon colour with distance so the far edge of the board sits back.
//
// Units deliberately do NOT get this - the actors should stay the crispest,
// most saturated things on screen so they read against the scenery.

uniform float saturation : hint_range(0.0, 1.0) = 0.78;
uniform vec3 tint : source_color = vec3(1.04, 0.99, 0.90);
// How far this prop is washed toward the haze colour. Driven by depth.
uniform float haze : hint_range(0.0, 1.0) = 0.0;
uniform vec3 haze_color : source_color = vec3(0.80, 0.71, 0.55);
// Flattens contrast slightly so nothing on the board is pure black or white.
uniform float lift : hint_range(0.0, 0.5) = 0.05;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	vec3 rgb = mix(vec3(luma), src.rgb, saturation) * tint;
	rgb = mix(rgb, vec3(luma * 0.5 + 0.5), lift * 0.35);
	rgb = mix(rgb, haze_color, haze);
	COLOR = vec4(rgb, src.a) * COLOR;
}
