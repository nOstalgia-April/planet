shader_type canvas_item;
render_mode unshaded;

uniform float outline_width : hint_range(0.0, 16.0) = 13.0;
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float grain_amount : hint_range(0.0, 1.0) = 0.48;
uniform float candy_saturation : hint_range(0.0, 3.0) = 1.0;

varying vec4 icon_modulate;

void vertex() {
	icon_modulate = COLOR;
}

float grain(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Leave room for the ink inside the existing icon's layout rectangle.
	vec2 source_uv = (UV - 0.5) * 1.20 + 0.5;
	vec4 candy = texture(TEXTURE, clamp(source_uv, vec2(0.0), vec2(1.0)));
	float luminance = dot(candy.rgb, vec3(0.2126, 0.7152, 0.0722));
	candy.rgb = clamp(mix(vec3(luminance), candy.rgb, candy_saturation), vec3(0.0), vec3(1.0));
	candy.a *= float(all(greaterThanEqual(source_uv, vec2(0.0))) && all(lessThanEqual(source_uv, vec2(1.0))));
	vec2 pixel = source_uv / TEXTURE_PIXEL_SIZE;
	// Average subpixel grain when shrinking, instead of letting tiny flecks alias.
	float footprint = max(length(dFdx(pixel)), length(dFdy(pixel)));
	float grain_visibility = 1.0 - smoothstep(1.0, 3.0, footprint);
	float fleck = mix(0.5, grain(floor(pixel / 2.0)), grain_visibility);
	float radius = outline_width * mix(0.70, 1.0, fleck);
	float expanded = candy.a;
	for (int index = 0; index < 24; index++) {
		float angle = float(index) * 6.2831853 / 24.0;
		vec2 tap_uv = source_uv + vec2(cos(angle), sin(angle)) * TEXTURE_PIXEL_SIZE * radius;
		float tap_alpha = texture(TEXTURE, clamp(tap_uv, vec2(0.0), vec2(1.0))).a;
		tap_alpha *= float(all(greaterThanEqual(tap_uv, vec2(0.0))) && all(lessThanEqual(tap_uv, vec2(1.0))));
		expanded = max(expanded, tap_alpha);
	}
	float ink = smoothstep(0.12, 0.65, expanded) * mix(1.0 - grain_amount, 1.0, fleck);
	// Keep the source's translucent grain clear in the colored interior.
	ink *= smoothstep(0.43, 0.49, length(source_uv - 0.5));
	ink *= outline_color.a;
	float alpha = candy.a + ink * (1.0 - candy.a);
	vec3 color = candy.rgb * candy.a + outline_color.rgb * ink * (1.0 - candy.a);
	COLOR = icon_modulate * vec4(color / max(alpha, 0.0001), alpha);
}
