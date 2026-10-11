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
uniform vec4 echo_color : source_color = vec4(0.48, 0.21, 0.24, 1.0);
uniform float echo_strength : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	float time = (effect_time >= 0.0 ? effect_time : TIME) * animation_speed;
	vec2 point = UV - vec2(0.5);
	float aspect = fwidth(UV.y) / max(fwidth(UV.x), 0.000001);
	point.x *= aspect;
	vec2 band_distance = (UV.y - wave_band_heights - vec2(sin(time), cos(time * 0.7)) * 0.018) / wave_band_width;
	vec2 band_envelope = exp(-band_distance * band_distance);
	float bend = sin(point.y * 38.0 - time * 4.0 + sin(point.x * 2.2)) * band_envelope.x;
	bend += sin(point.y * 32.0 + time * 3.2 + point.x * 1.5) * band_envelope.y;
	bend *= wave_amplitude;
	vec2 cursor_offset = (UV - cursor_uv) * vec2(aspect, 1.0);
	float radius = length(cursor_offset);
	float cursor_envelope = exp(-pow(radius / mouse_radius, 2.0) * 2.0);
	float ripple = sin(radius * 65.0 - time * 7.0) * cursor_envelope;
	bend += ripple * cursor_offset.x / max(radius, 0.025) * mouse_strength * cursor_activity;
	float phase = (point.x + bend) * wave_density;
	float ridge = 0.5 + 0.5 * cos(phase * TAU);
	float bands = pow(ridge, 5.0);
	float distance_to_line = abs(fract(phase + 0.5) - 0.5);
	float fine_line = 1.0 - smoothstep(0.018, 0.018 + fwidth(phase), distance_to_line);
	float depth = 0.72 + 0.28 * sin(point.x * 2.8 + point.y * 3.0 + time * 0.3);
	float ink = (0.09 + bands * 0.25 + fine_line * line_strength * 0.48) * depth;
	vec3 color = mix(shadow_color.rgb, wave_color.rgb, ink);
	// Colour briefly gathers on the existing folds, like the ship drawing a charge.
	// The staggered envelopes avoid a full-screen flash or an extra scanning stripe.
	float upper_charge = pow(0.5 + 0.5 * sin(time * 1.8 + point.x * 2.0), 3.0);
	float lower_charge = pow(0.5 + 0.5 * sin(time * 1.8 + point.x * 2.0 + 2.3), 3.0);
	float echo = band_envelope.x * upper_charge + band_envelope.y * lower_charge;
	float afterglow = exp(-pow((band_distance.x + 0.65) * 0.65, 2.0)) * upper_charge;
	afterglow += exp(-pow((band_distance.y - 0.65) * 0.65, 2.0)) * lower_charge;
	color += echo_color.rgb * echo_strength * (echo * (bands * 0.2 + fine_line * 0.32) + afterglow * 0.035);
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
