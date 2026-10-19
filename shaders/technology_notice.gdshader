shader_type canvas_item;
render_mode unshaded;

uniform bool emphasized = false;
uniform float flow_speed : hint_range(0.0, 4.0) = 1.6;
uniform float outline_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 notice_size = vec2(23.0, 24.0);
varying vec2 local_position;
varying vec4 item_color;

void vertex() {
	local_position = VERTEX;
	item_color = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (emphasized) {
		// Preserve the supplied badge contour; white paper surrounds a dark mark.
		float mark = smoothstep(0.3, 0.85, min(source.r, min(source.g, source.b)));
		float phase = local_position.x * 0.32 - local_position.y * 0.22 - TIME * flow_speed;
		float grain = sin(local_position.x * 7.3 + sin(local_position.y * 4.7)) * 0.025;
		float sheen = pow(0.5 + 0.5 * sin(phase), 4.0);
		vec3 paper = vec3(clamp(0.83 + sheen * 0.17 + grain, 0.0, 1.0));
		source.rgb = mix(paper, vec3(0.10, 0.08, 0.12), mark);
	}
	// Trace the supplied badge silhouette clockwise from the top.
	vec2 step_uv = TEXTURE_PIXEL_SIZE * 1.5;
	float outer_alpha = source.a;
	float inner_alpha = source.a;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.785398;
		float sample_alpha = texture(TEXTURE, UV + vec2(cos(angle), sin(angle)) * step_uv).a;
		outer_alpha = max(outer_alpha, sample_alpha);
		inner_alpha = min(inner_alpha, sample_alpha);
	}
	vec2 centered = local_position / notice_size - vec2(0.5);
	float sweep = mod(atan(centered.y, centered.x) + 7.853982, 6.283185) / 6.283185;
	float revealed = step(sweep, outline_progress) * step(0.001, outline_progress);
	float edge = (outer_alpha - inner_alpha) * revealed;
	source.rgb = mix(source.rgb, vec3(1.0), edge);
	source.a = max(source.a, edge);
	COLOR = source * item_color;
}
