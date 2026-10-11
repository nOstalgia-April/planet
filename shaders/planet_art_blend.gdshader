shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D overview_texture : source_color, filter_linear, repeat_disable;
uniform vec2 near_center_uv;
uniform vec2 near_radius_uv;
uniform vec2 overview_center_uv;
uniform vec2 overview_radius_uv;
uniform vec2 restored_offset_uv = vec2(-0.005208333, -0.026851852);
uniform vec2 land_offset_uv = vec2(0.0109375, 0.0);
uniform float overview_heading = 1.570796327;
uniform float overview_mix : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D pink_land : source_color, filter_linear, repeat_disable;
uniform sampler2D blue_land : source_color, filter_linear, repeat_disable;
uniform sampler2D green_land : source_color, filter_linear, repeat_disable;
uniform sampler2D restored_texture : source_color, filter_linear, repeat_disable;
uniform vec3 land_progress = vec3(0.0);
uniform vec2 reveal_screen_y = vec2(0.0, 1.0);
uniform float restored_mix = 0.0;
varying vec4 tint;

vec4 over(vec4 base, vec4 layer, float amount) {
	float alpha = layer.a * amount;
	return vec4(layer.rgb * alpha, alpha) + base * (1.0 - alpha);
}

float revealed(float progress, float screen_y) {
	if (progress <= 0.0) { return 0.0; }
	if (progress >= 1.0) { return 1.0; }
	return 1.0 - smoothstep(progress - 0.015, progress + 0.015, screen_y);
}

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 point = (UV - near_center_uv) / near_radius_uv;
	float c = cos(overview_heading);
	float s = sin(overview_heading);
	vec2 aligned = vec2(c * point.x - s * point.y, s * point.x + c * point.y);
	vec2 overview_uv = overview_center_uv + aligned * overview_radius_uv;
	vec2 restored_uv = overview_uv + restored_offset_uv;
	vec2 land_uv = restored_uv + land_offset_uv;
	vec4 near_color = texture(TEXTURE, UV);
	vec4 overview_color = texture(overview_texture, overview_uv);
	// Mix premultiplied samples once: overlapping opaque ground stays opaque.
	vec4 blended = mix(
		vec4(near_color.rgb * near_color.a, near_color.a),
		vec4(overview_color.rgb * overview_color.a, overview_color.a),
		overview_mix
	);
	float y = (SCREEN_UV.y - reveal_screen_y.x) / (reveal_screen_y.y - reveal_screen_y.x);
	blended = over(blended, texture(pink_land, land_uv), revealed(land_progress.x, y));
	blended = over(blended, texture(blue_land, land_uv), revealed(land_progress.y, y));
	blended = over(blended, texture(green_land, land_uv), revealed(land_progress.z, y));
	vec4 restored = texture(restored_texture, restored_uv);
	blended = mix(blended, vec4(restored.rgb * restored.a, restored.a), restored_mix);
	COLOR = blended * vec4(tint.rgb * tint.a, tint.a);
}
