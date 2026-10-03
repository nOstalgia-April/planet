shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 position = UV - vec2(0.48, 0.45);
	float halo = 1.0 - smoothstep(0.02, 0.65, length(position));
	vec3 base = mix(vec3(0.062, 0.100, 0.087), vec3(0.14, 0.20, 0.17), halo);
	float grain = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(base + (grain - 0.5) * 0.011, 1.0);
}
