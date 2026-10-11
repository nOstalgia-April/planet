shader_type canvas_item;
render_mode unshaded;

uniform float glow_strength : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	// The supplied art contains a pink halo; attenuate that pigment only.
	float pink = smoothstep(0.06, 0.32, ink.r - ink.g);
	float strength = mix(1.0, glow_strength, pink);
	COLOR = vec4(ink.rgb, ink.a * strength);
}
