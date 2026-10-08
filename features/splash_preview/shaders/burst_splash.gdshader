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

uniform float fling : hint_range(0.0, 1.6) = 1.05;

void vertex() {
	VERTEX *= canvas_margin;
}

void fragment() {
	float grow = mix(0.025, 1.0, smoothstep(0.0, 0.09, progress));
	float impulse = sin(progress * 16.0) * exp(-progress * 5.2) * intensity;
	vec2 p = (UV - vec2(0.5)) * canvas_margin / grow;
	p -= vec2(0.06, -0.025) * impulse;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float rim = smoothstep(0.025, 0.25, radius);
	float sectors = 0.62 + 0.38 * sin(angle * 5.0 + 0.6);
	float stretch = max(0.40, 1.0 + impulse * fling * sectors * rim);
	float curved_angle = angle - impulse * 0.25 * sin(angle * 2.0) * rim;
	vec2 uv = vec2(cos(curved_angle), sin(curved_angle)) * radius / stretch + vec2(0.5);
	float alpha = source_alpha(uv);
	COLOR = vec4(tint.rgb, alpha * tint.a * smoothstep(0.0, 0.02, progress));
}
