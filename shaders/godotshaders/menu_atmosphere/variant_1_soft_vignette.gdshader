// Source: https://godotshaders.com/shader/vignette-3/
// Author: Lu. License: CC0 (verified on the source page; taxonomy fetch returned HTTP 455).
// Notes: Godot 4.x adaptation; smooth outer falloff protects the central title.
shader_type canvas_item;
render_mode unshaded;

uniform vec4 vignette_color : source_color = vec4(0.018, 0.004, 0.025, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.20;
uniform float inner_radius : hint_range(0.0, 1.5) = 0.58;
uniform float outer_radius : hint_range(0.0, 1.5) = 1.25;

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(1.48, 1.0) * 2.0;
	float edge = smoothstep(inner_radius, outer_radius, length(centered));
	// The title is baked into the cover, so keep the whole central wordmark clear.
	float title_band = smoothstep(0.29, 0.39, UV.y) * (1.0 - smoothstep(0.57, 0.66, UV.y));
	COLOR = vec4(vignette_color.rgb, edge * strength * (1.0 - title_band * 0.92));
}
