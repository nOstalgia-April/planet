shader_type canvas_item;
render_mode unshaded;

uniform bool white_paper = false;
varying vec4 tint;

void vertex() { tint = COLOR; }

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	// Hide the X printed in the frames; the real button owns its visibility.
	bool printed_close = UV.x > 0.62 && UV.x < 0.655 && UV.y > 0.17 && UV.y < 0.23;
	if (printed_close && source.g > 0.12) {
		source.rgb = texture(TEXTURE, vec2(0.61, UV.y)).rgb;
	}
	if (white_paper) {
		float fold = smoothstep(0.42, 0.60, source.r);
		source.rgb = mix(vec3(0.97), vec3(0.78), fold);
	}
	COLOR = source * tint;
}
