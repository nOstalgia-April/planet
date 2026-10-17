shader_type canvas_item;
render_mode unshaded;

uniform bool emphasized = false;
uniform float flow_speed : hint_range(0.0, 4.0) = 1.6;
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
	COLOR = source * item_color;
}
