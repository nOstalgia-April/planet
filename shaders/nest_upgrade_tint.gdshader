shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint : source_color = vec4(0.878, 0.0, 0.392, 1.0);
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform float flow_time = 0.0;
uniform float outline_width : hint_range(1.0, 12.0) = 5.5;
uniform vec4 hover_fill : source_color = vec4(0.025, 0.018, 0.035, 1.0);
varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

void fragment() {
	float fill = texture(TEXTURE, UV).a;
	float polar = atan(UV.y - 0.5, UV.x - 0.5);
	// Integer angular frequencies keep the flowing edge seamless across the angle wrap.
	float wave = 0.5 + 0.5 * sin(polar * 3.0 - flow_time * 2.0);
	float ripple = 0.5 + 0.5 * sin(polar * 5.0 - flow_time * 3.0 + 0.8);
	float bead = pow(0.5 + 0.5 * cos(polar - flow_time), 14.0);
	float width = outline_width + wave * 2.4 + ripple * 1.3 + bead * 4.0 + hover_amount * 1.8;
	float edge = fill;
	for (int i = 0; i < 12; i++) {
		float angle = float(i) * 6.283185 / 12.0;
		vec2 offset = vec2(cos(angle), sin(angle)) * TEXTURE_PIXEL_SIZE * width;
		edge = max(edge, texture(TEXTURE, UV + offset).a);
	}
	vec3 milk = vec3(1.0, 0.94, 0.79);
	vec3 border = mix(mix(tint.rgb, milk, 0.35), milk, smoothstep(0.1, 0.9, wave));
	border = mix(border, vec3(1.0, 0.99, 0.92), bead * 0.85);
	border = mix(border, mix(border, milk, 0.4), hover_amount);
	vec3 body = mix(tint.rgb, hover_fill.rgb, hover_amount);
	COLOR = vec4(mix(border, body, fill), edge * tint.a) * item_color;
}
