shader_type canvas_item;

// Source artwork uses discrete gray fills. Preserve its outlines, alpha and animation.
uniform vec3 color_progress = vec3(0.0);
uniform int piece_kind = 0;
uniform vec4 fill_a : source_color;
uniform vec4 fill_b : source_color;
uniform vec4 fill_c : source_color;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec3 paint = fill_a.rgb;
	float progress = color_progress.y;
	float gray = 186.0 / 255.0;
	if (piece_kind == 1) {
		paint = UV.x < 0.62 ? fill_a.rgb : fill_b.rgb;
		progress = color_progress.x;
		gray = 245.0 / 255.0;
	} else if (piece_kind == 2) {
		bool top = base.r > 0.8;
		paint = top ? fill_a.rgb : fill_b.rgb;
		progress = top ? color_progress.z : color_progress.y;
		gray = top ? 1.0 : 158.0 / 255.0;
	} else if (piece_kind == 3) {
		paint = base.r > 0.98 ? fill_b.rgb : (base.r > 0.85 ? fill_c.rgb : fill_a.rgb);
		gray = base.r > 0.98 ? 1.0 : (base.r > 0.85 ? 245.0 / 255.0 : 186.0 / 255.0);
		progress = color_progress.x;
	}
	// Carry edge coverage into the paint instead of leaving pale antialias fringes.
	paint *= min(base.r / gray, 1.0);
	float fill_mask = smoothstep(0.40, 0.55, base.r);
	COLOR = vertex_tint * vec4(mix(base.rgb, paint, progress * fill_mask), base.a);
}
