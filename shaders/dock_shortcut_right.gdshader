shader_type canvas_item;
render_mode unshaded;

uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform float selected : hint_range(0.0, 1.0) = 0.0;
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform vec4 accent : source_color = vec4(0.5, 0.65, 1.0, 1.0);
varying vec2 local_uv;
varying vec4 item_color;

void vertex() {
	local_uv = VERTEX / vec2(52.0);
	item_color = COLOR;
}

float mask_at(sampler2D art, vec2 uv) {
	vec4 source = texture(art, uv);
	return source.a * smoothstep(0.1, 0.65, source.r);
}

void fragment() {
	float mask = mask_at(TEXTURE, UV);
	vec2 step_uv = TEXTURE_PIXEL_SIZE * 1.7;
	float inside = min(min(mask_at(TEXTURE, UV + vec2(step_uv.x, 0.0)), mask_at(TEXTURE, UV - vec2(step_uv.x, 0.0))), min(mask_at(TEXTURE, UV + vec2(0.0, step_uv.y)), mask_at(TEXTURE, UV - vec2(0.0, step_uv.y))));
	float rim = clamp(mask - inside, 0.0, 1.0);
	float grain = fract(sin(dot(floor(local_uv * 104.0), vec2(127.1, 311.7))) * 43758.5453);
	float sweep = local_uv.x * 0.72 + local_uv.y * 0.18 + grain * 0.1;
	float painted = smoothstep(sweep, sweep + 0.12, reveal * 1.14);
	vec3 ink = mix(vec3(0.07 + grain * 0.08), vec3(0.34 + grain * 0.22), hover_amount);
	ink = mix(ink, accent.rgb * (0.65 + hover_amount * 0.12), painted);
	vec3 border = mix(vec3(0.65), mix(accent.rgb, vec3(1.0), 0.35), painted);
	COLOR = vec4(mix(ink, border, rim * (0.65 + hover_amount * 0.35)), mask) * item_color;
}
