shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.85;
uniform float band_width : hint_range(0.05, 0.5) = 0.24;
uniform vec2 vertical_bounds = vec2(0.0, 1.0);

void fragment() {
	float height = (UV.y - vertical_bounds.x) / max(vertical_bounds.y - vertical_bounds.x, 0.001);
	float edge = mix(1.0 + band_width, -band_width, progress);
	float band = 1.0 - smoothstep(0.0, band_width, abs(height - edge));
	COLOR = vec4(vec3(1.0), texture(TEXTURE, UV).a * band * intensity);
}
