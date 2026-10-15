shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float softness : hint_range(0.1, 2.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float glow = pow(max(0.0, 1.0 - radius), 2.8 * softness);
	float core = exp(-radius * radius * 48.0);
	COLOR = vec4(COLOR.rgb, COLOR.a * (glow * 0.55 + core * 0.45));
}
