// White pixels are the supplied soft edge; dark/colored pixels are the body.
float dock_surface_alpha(vec4 source, float hover_amount) {
	float white_edge = smoothstep(0.45, 0.9, min(source.r, min(source.g, source.b)));
	float quiet_edge = smoothstep(0.32, 0.48, source.a) * 0.24;
	float idle_alpha = mix(source.a, quiet_edge, white_edge);
	return mix(idle_alpha, source.a, hover_amount);
}
