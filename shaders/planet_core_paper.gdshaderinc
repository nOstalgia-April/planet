uniform sampler2D core_paper_texture : source_color, filter_linear, repeat_disable;
uniform float core_white_mix : hint_range(0.0, 1.0) = 0.0;

vec3 core_paper_color(vec2 point) {
	// Reuse the shipped pastel background in sphere-local coordinates. Its
	// chalk grain stays attached to the planet through camera and atlas changes.
	vec2 paper_uv = clamp(vec2(0.5) + point * 0.48, vec2(0.0), vec2(1.0));
	vec3 paper = texture(core_paper_texture, paper_uv).rgb;
	return mix(paper, vec3(0.98, 0.98, 0.96), 0.18);
}
