shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.85;
uniform float outline_pixels : hint_range(0.5, 5.0) = 1.5;
uniform vec2 center_uv = vec2(0.5);

float flower_alpha(float sampled, vec2 uv) {
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return sampled * inside.x * inside.y;
}

void vertex() {
	// Leave room outside the source silhouette for the expanding contour.
	VERTEX += (UV - vec2(0.5)) / TEXTURE_PIXEL_SIZE * 0.5;
}

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * 1.5 + vec2(0.5);
	float expansion = mix(0.3, 1.24, 1.0 - pow(1.0 - progress, 2.0));
	vec2 sample_uv = center_uv + (uv - center_uv) / expansion;
	vec2 width = TEXTURE_PIXEL_SIZE * outline_pixels / expansion;
	float center = flower_alpha(texture(TEXTURE, sample_uv).a, sample_uv);
	float outer = center;
	float inner = center;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 neighbor = sample_uv + vec2(float(x), float(y)) * width;
			float alpha = flower_alpha(texture(TEXTURE, neighbor).a, neighbor);
			outer = max(outer, alpha);
			inner = min(inner, alpha);
		}
	}
	float fade = smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.65, 1.0, progress));
	float contour = outer - inner;
	COLOR = vec4(vec3(1.0), max(contour, center * 0.12) * fade * intensity);
}
