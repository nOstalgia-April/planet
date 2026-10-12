uniform bool population_palette_enabled = false;
uniform vec4 palette_dark : source_color = vec4(0.27, 0.035, 0.118, 1.0);
uniform vec4 palette_mid : source_color = vec4(0.533, 0.118, 0.208, 1.0);
uniform vec4 palette_ink : source_color = vec4(0.761, 0.122, 0.341, 1.0);
uniform vec4 palette_bright : source_color = vec4(0.827, 0.18, 0.369, 1.0);
uniform vec4 palette_light : source_color = vec4(0.965, 0.792, 0.839, 1.0);

vec3 population_color(vec3 source) {
	if (!population_palette_enabled) { return source; }
	// Lightness retains brush detail, black shading and pale highlights across hues.
	float lightness = (max(source.r, max(source.g, source.b)) + min(source.r, min(source.g, source.b))) * 0.5;
	if (lightness < 0.153) { return mix(vec3(0.0), palette_dark.rgb, lightness / 0.153); }
	if (lightness < 0.325) { return mix(palette_dark.rgb, palette_mid.rgb, (lightness - 0.153) / 0.172); }
	if (lightness < 0.441) { return mix(palette_mid.rgb, palette_ink.rgb, (lightness - 0.325) / 0.116); }
	if (lightness < 0.504) { return mix(palette_ink.rgb, palette_bright.rgb, (lightness - 0.441) / 0.063); }
	if (lightness < 0.878) { return mix(palette_bright.rgb, palette_light.rgb, (lightness - 0.504) / 0.374); }
	return mix(palette_light.rgb, vec3(1.0), clamp((lightness - 0.878) / 0.122, 0.0, 1.0));
}
