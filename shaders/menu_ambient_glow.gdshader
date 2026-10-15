shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 halo_color : source_color = vec4(0.78, 0.11, 0.32, 1.0);
uniform vec4 space_color : source_color = vec4(0.19, 0.08, 0.25, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.38;
uniform float breath_period : hint_range(4.0, 30.0) = 12.0;
uniform vec2 planet_center = vec2(0.53, 0.48);

float grain(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float soft_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(grain(cell), grain(cell + vec2(1.0, 0.0)), f.x),
		mix(grain(cell + vec2(0.0, 1.0)), grain(cell + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = (UV - planet_center) * vec2(1.777778, 1.0);
	float radius = length(p);
	float breath = 0.84 + 0.16 * sin(TIME * 6.283185 / breath_period);
	float cloud = soft_noise(p * 6.0 + vec2(TIME * 0.012, -TIME * 0.008));
	float halo = exp(-pow((radius - 0.425) / 0.115, 2.0));
	float rim = exp(-pow((radius - 0.405) / 0.032, 2.0));
	float outer_air = smoothstep(0.36, 0.58, radius);
	float side_light = exp(-dot((p - vec2(0.45, 0.14)) * vec2(1.6, 2.0),
		(p - vec2(0.45, 0.14)) * vec2(1.6, 2.0)));
	// Light falls outside the painted planet; its grey body and white title stay crisp.
	vec3 light = halo_color.rgb * (halo * 0.30 + rim * 0.09) * breath * (0.7 + cloud * 0.3);
	light += space_color.rgb * outer_air * (0.20 + side_light * 0.16);
	float paper = mix(0.91, 1.0, grain(floor(UV * vec2(1920.0, 1080.0))));
	COLOR = vec4(light * intensity * paper, 1.0);
}
