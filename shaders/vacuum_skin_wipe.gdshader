shader_type canvas_item;

uniform sampler2D next_frame : source_color, filter_linear;
uniform sampler2D gray_frame : source_color, filter_linear;
uniform float gray_mix : hint_range(0.0, 1.0) = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float feather : hint_range(0.001, 0.1) = 0.025;
// Visible artwork spans y=28..238 on the original 286px canvas.
uniform vec2 vertical_bounds = vec2(0.098, 0.833);
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 previous = texture(TEXTURE, UV);
	vec4 next = texture(next_frame, UV);
	float edge = mix(vertical_bounds.y + feather, vertical_bounds.x - feather, progress);
	float reveal = smoothstep(edge - feather, edge + feather, UV.y);
	if (progress <= 0.0) { reveal = 0.0; }
	if (progress >= 1.0) { reveal = 1.0; }
	vec4 colored = mix(previous, next, reveal);
	COLOR = tint * mix(colored, texture(gray_frame, UV), gray_mix);
}
