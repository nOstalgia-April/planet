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

uniform float lobe_stretch : hint_range(0.0, 1.6) = 1.15;
uniform float bend : hint_range(0.0, 0.6) = 0.36;

float angle_distance(float a, float b) {
	return atan(sin(a - b), cos(a - b));
}

float lobe(float angle, float direction, float delay, float width) {
	float difference = angle_distance(angle, direction);
	float local_time = max(progress - delay, 0.0);
	float impulse = sin(local_time * 18.0) * exp(-local_time * 7.0);
	return exp(-difference * difference / width) * impulse;
}

void vertex() {
	VERTEX *= canvas_margin;
}

void fragment() {
	float grow = mix(0.025, 1.0, smoothstep(0.0, 0.13, progress));
	vec2 p = (UV - vec2(0.5)) * canvas_margin / grow;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float top = lobe(angle, -1.55, 0.025, 0.20);
	float right = lobe(angle, -0.35, 0.085, 0.22);
	float lower = lobe(angle, 1.05, 0.145, 0.24);
	float left = lobe(angle, 2.55, 0.205, 0.23);
	float rim = smoothstep(0.04, 0.28, radius);
	float stretch = max(0.42, 1.0 + (top + right + lower + left) * lobe_stretch * intensity * rim);
	float bent_angle = angle - bend * intensity * (right - top + left - lower) * rim;
	vec2 uv = vec2(cos(bent_angle), sin(bent_angle)) * radius / stretch + vec2(0.5);
	float alpha = source_alpha(uv);
	COLOR = vec4(tint.rgb, alpha * tint.a * smoothstep(0.0, 0.02, progress));
}
