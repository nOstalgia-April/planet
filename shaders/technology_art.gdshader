shader_type canvas_item;

uniform sampler2D artwork : source_color;
uniform vec4 quiet_top : source_color = vec4(0.13, 0.055, 0.09, 1.0);
uniform vec4 quiet_bottom : source_color = vec4(0.24, 0.09, 0.145, 1.0);
uniform float quiet_strength : hint_range(0.0, 1.0) = 0.92;
// Retained for the existing background comparison scenes.
uniform vec2 cursor_uv = vec2(0.5);
uniform float cursor_activity = 0.0;

void fragment() {
	vec4 source = texture(artwork, UV);
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 ink = mix(vec3(luminance), source.rgb, 0.72) * 0.65;
	// Keep the supplied brush texture at the perimeter, with a quiet reading field inside.
	vec2 edge = min(UV, vec2(1.0) - UV);
	float interior = smoothstep(0.015, 0.15, edge.x) * smoothstep(0.055, 0.23, edge.y);
	vec3 quiet = mix(quiet_top.rgb, quiet_bottom.rgb, smoothstep(0.12, 0.9, UV.y));
	COLOR = vec4(mix(ink, quiet, interior * quiet_strength), source.a);
}
