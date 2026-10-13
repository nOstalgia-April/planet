shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.9, 1.0);
uniform float pulse_seconds : hint_range(0.5, 5.0) = 2.4;
uniform float strength : hint_range(0.0, 2.0) = 0.18;

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float halo = exp(-pow((radius - 0.66) / 0.23, 2.0));
	float edge = 1.0 - smoothstep(0.88, 1.0, radius);
	float pulse = 0.82 + 0.18 * sin(TIME * 6.283185 / pulse_seconds);
	COLOR = vec4(glow_color.rgb, halo * edge * pulse * strength * glow_color.a);
}
