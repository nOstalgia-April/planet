shader_type canvas_item;
render_mode unshaded;

varying vec4 pool_color;

void vertex() {
	pool_color = COLOR;
}

void fragment() {
	// Use the same source texel and alpha threshold as the ground contact mask.
	ivec2 size = textureSize(TEXTURE, 0);
	ivec2 pixel = ivec2(floor(UV * vec2(size)));
	if (any(lessThan(pixel, ivec2(0))) || any(greaterThanEqual(pixel, size))) {
		discard;
	}
	float alpha = texelFetch(TEXTURE, pixel, 0).a;
	if (alpha <= 0.1) {
		discard;
	}
	COLOR = pool_color * vec4(texture(TEXTURE, UV).rgb, alpha);
}
