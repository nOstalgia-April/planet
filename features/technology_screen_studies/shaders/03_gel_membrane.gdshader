shader_type canvas_item;
render_mode unshaded;

uniform vec4 shadow_color : source_color = vec4(0.025, 0.006, 0.013, 1.0);
uniform vec4 wave_color : source_color = vec4(0.32, 0.035, 0.11, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.42, 0.68, 1.0);
uniform float wave_density : hint_range(60.0, 240.0) = 96.0;
uniform float wave_amplitude : hint_range(0.0, 0.05) = 0.032;
uniform float animation_speed : hint_range(0.0, 1.0) = 0.36;
uniform vec2 wave_band_heights = vec2(0.23, 0.67);
uniform float wave_band_width : hint_range(0.01, 0.15) = 0.075;
uniform float line_strength : hint_range(0.0, 1.0) = 0.7;
uniform float glow_strength : hint_range(0.0, 1.5) = 0.32;
uniform float glow_width : hint_range(0.01, 0.2) = 0.055;
uniform float mouse_radius : hint_range(0.02, 0.3) = 0.14;
uniform float mouse_strength : hint_range(0.0, 0.03) = 0.012;
uniform vec2 cursor_uv = vec2(0.5);
uniform float cursor_activity = 0.0;
uniform float crt_strength : hint_range(0.0, 1.0) = 0.18;
uniform float grain_strength : hint_range(0.0, 0.05) = 0.012;
uniform float effect_time = -1.0;
uniform float membrane_sheen : hint_range(0.0, 0.1) = 0.032;
uniform float membrane_push : hint_range(0.0, 3.0) = 1.65;

void fragment() {
	float source_time = effect_time >= 0.0 ? effect_time : TIME;
	float time = source_time * animation_speed;
	vec2 point = UV - vec2(0.5);
	float aspect = fwidth(UV.y) / max(fwidth(UV.x), 0.000001);
	point.x *= aspect;
	// Two supple folds pass through an otherwise straight, vertical membrane.
	vec2 band_motion = vec2(sin(time), cos(time * 0.7)) * 0.018;
	vec2 band_distance = (UV.y - wave_band_heights - band_motion) / wave_band_width;
	vec2 band_envelope = exp(-band_distance * band_distance);
	float upper_phase = point.y * 38.0 - time * 4.0 + sin(point.x * 2.2);
	float lower_phase = point.y * 32.0 + time * 3.2 + point.x * 1.5;
	float upper_fold = sin(upper_phase) + 0.15 * sin(upper_phase * 2.0 - 0.6);
	float lower_fold = sin(lower_phase) + 0.15 * sin(lower_phase * 2.0 + 0.6);
	float bend = (upper_fold * band_envelope.x + lower_fold * band_envelope.y) * wave_amplitude;
	// A local lens pushes the fibres apart without adding expanding ring patterns.
	vec2 cursor_offset = (UV - cursor_uv) * vec2(aspect, 1.0);
	vec2 lens_point = cursor_offset / mouse_radius;
	lens_point.y *= 1.12;
	float lens_distance_squared = dot(lens_point, lens_point);
	float cursor_envelope = exp(-lens_distance_squared * 2.0);
	float activity = clamp(cursor_activity, 0.0, 1.0);
	float elastic_settle = 0.92 + 0.08 * sin(time * 5.0);
	bend += lens_point.x * cursor_envelope * mouse_strength * membrane_push * elastic_settle * activity;
	float phase = (point.x + bend) * wave_density;
	float ridge = 0.5 + 0.5 * cos(phase * TAU);
	float bands = pow(ridge, 5.0);
	float distance_to_line = abs(fract(phase + 0.5) - 0.5);
	float pixel_width = fwidth(phase);
	float fine_line = 1.0 - smoothstep(0.018, 0.018 + pixel_width, distance_to_line);
	float depth = 0.72 + 0.28 * sin(point.x * 2.8 + point.y * 3.0 + time * 0.3);
	float ink = (0.09 + bands * 0.25 + fine_line * line_strength * 0.48) * depth;
	vec3 color = mix(shadow_color.rgb, wave_color.rgb, ink);
	// A narrow, pink grazing reflection makes the displaced surface read as gel.
	vec2 sheen_point = (lens_point + vec2(0.24, 0.32)) * vec2(1.45, 2.8);
	float pointer_sheen = exp(-dot(sheen_point, sheen_point) * 2.0) * activity;
	float fold_sheen = pow(max(cos(upper_phase + 0.7), 0.0), 8.0) * band_envelope.x;
	fold_sheen += pow(max(cos(lower_phase - 0.7), 0.0), 8.0) * band_envelope.y;
	color += glow_color.rgb * membrane_sheen * (pointer_sheen + fold_sheen * 0.12);
	color *= 1.0 - cursor_envelope * activity * 0.075;
	// Keep the same broad, weak edge diffusion as the existing technology screen.
	vec2 edge_distance = min(UV, 1.0 - UV) * vec2(aspect, 1.0);
	vec2 edge_halo = exp(-edge_distance / glow_width);
	float halo = 1.0 - (1.0 - edge_halo.x) * (1.0 - edge_halo.y);
	float rim = exp(-min(edge_distance.x, edge_distance.y) / 0.006);
	color += glow_color.rgb * (halo * 0.52 + rim * 0.18) * glow_strength;
	float scanline = 0.5 + 0.5 * cos(FRAGCOORD.y * TAU / 3.0);
	color *= 1.0 - scanline * crt_strength;
	float grain = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	color += (grain - 0.5) * grain_strength;
	COLOR = vec4(max(color, vec3(0.0)), 1.0);
}
