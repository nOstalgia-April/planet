shader_type canvas_item;
render_mode unshaded, blend_mul;

varying vec4 modulation;

void vertex() {
	modulation = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	// The supplied PNG is gray ink on opaque white. Recover its edge coverage.
	float coverage = clamp((1.0 - source.r) / (1.0 - 92.0 / 255.0), 0.0, 1.0);
	// White is neutral for multiplication; never brighten a dark patch of ground.
	float strength = coverage * source.a * modulation.a;
	COLOR = vec4(mix(vec3(1.0), vec3(92.0 / 255.0), strength), 1.0);
}
