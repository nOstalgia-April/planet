shader_type canvas_item;
render_mode unshaded;

uniform vec4 fill_color : source_color = vec4(0.16, 0.08, 0.12, 1.0);
uniform vec4 rim_color : source_color = vec4(0.65, 0.3, 0.45, 1.0);

void fragment() {
	vec2 step_uv = TEXTURE_PIXEL_SIZE * 1.6;
	float alpha = texture(TEXTURE, UV).a;
	float inner = texture(TEXTURE, UV + vec2(step_uv.x, 0.0)).a;
	inner = min(inner, texture(TEXTURE, UV - vec2(step_uv.x, 0.0)).a);
	inner = min(inner, texture(TEXTURE, UV + vec2(0.0, step_uv.y)).a);
	inner = min(inner, texture(TEXTURE, UV - vec2(0.0, step_uv.y)).a);
	float rim = clamp(alpha - inner, 0.0, 1.0);
	COLOR = vec4(mix(fill_color.rgb, rim_color.rgb, rim * rim_color.a), alpha * fill_color.a);
}
