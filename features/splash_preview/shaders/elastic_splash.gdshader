shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.0, 0.49, 1.0);
uniform float canvas_margin = 2.8;
uniform sampler2D source_concept : filter_linear, repeat_disable;
uniform vec4 source_rect = vec4(195.0, 418.0, 66.0, 64.0);

float source_alpha(vec2 uv) {
	uv.y = 0.5 + (uv.y - 0.5) * source_rect.z / source_rect.w;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec2 image_size = vec2(textureSize(source_concept, 0));
	vec2 sample_uv = (source_rect.xy + clamp(uv, vec2(0.0), vec2(1.0)) * source_rect.zw) / image_size;
	vec3 source = texture(source_concept, sample_uv).rgb;
	// Pink over the original black cavity: gray artwork cancels in r - g.
	return clamp((source.r - source.g) / 0.984, 0.0, 1.0) * inside;
}


void vertex() {
	VERTEX *= canvas_margin;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * canvas_margin;
	float grow = mix(0.025, 1.0, smoothstep(0.0, 0.15, progress));
	float wave = sin(progress * 23.0) * exp(-progress * 6.0) * intensity;
	vec2 stretch = vec2(1.0 + 0.31 * wave, 1.0 - 0.23 * wave) * grow;
	vec2 uv = p / stretch + vec2(0.5);
	float alpha = source_alpha(uv);
	COLOR = vec4(tint.rgb, alpha * tint.a * smoothstep(0.0, 0.02, progress));
}
