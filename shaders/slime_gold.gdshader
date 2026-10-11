shader_type canvas_item;

uniform bool gold = false;
varying vec4 canvas_tint;

void vertex() {
	canvas_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (gold) {
		float shade = dot(source.rgb, vec3(0.299, 0.587, 0.114));
		source.rgb = mix(vec3(0.40, 0.24, 0.06), vec3(1.0, 0.89, 0.43), shade);
	}
	COLOR = source * canvas_tint;
}
