shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	// Keep the technology tooltip's painted edge, in white on black.
	float edge = smoothstep(0.1, 0.7, ink.r - ink.g);
	float gray = mix(dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722)) * 0.25, 0.95, edge);
	COLOR = vec4(vec3(gray), ink.a);
}
