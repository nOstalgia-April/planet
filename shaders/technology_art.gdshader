shader_type canvas_item;

#include "res://shaders/population_palette.gdshaderinc"

uniform sampler2D artwork : source_color;
uniform float artwork_brightness : hint_range(0.0, 1.0) = 1.0;
// Fill the page with the painted interior, excluding the source image's outer frame.
uniform vec4 artwork_region = vec4(32.0, 100.0, 1856.0, 910.0);
// Retained for the existing background comparison scenes.
uniform vec2 cursor_uv = vec2(0.5);
uniform float cursor_activity = 0.0;

void fragment() {
	vec2 art_uv = (artwork_region.xy + UV * artwork_region.zw) / vec2(textureSize(artwork, 0));
	vec3 source = texture(artwork, art_uv).rgb;
	COLOR = vec4(population_color(source) * artwork_brightness, 1.0);
}
