shader_type canvas_item;
render_mode unshaded;

uniform sampler2D tail_texture : source_color, filter_linear, repeat_disable;
uniform float tail_opacity_gain : hint_range(1.0, 2.0) = 1.655844;
instance uniform vec4 body_region;
instance uniform vec4 tail_region;
instance uniform vec2 sample_lengths = vec2(32.0, 12.0);
instance uniform float path_offset = 0.0;
varying float opacity;

void vertex() {
	opacity = COLOR.a;
}

void fragment() {
	// UV.x is distance from the oldest point; UV.y spans the full source height.
	float along = 1.0 - abs(1.0 - mod((UV.x + path_offset) / sample_lengths.x, 2.0));
	float tail_progress = clamp(UV.x / sample_lengths.y, 0.0, 1.0);
	vec2 body_uv = body_region.xy + vec2(along, UV.y) * body_region.zw;
	vec2 tail_uv = tail_region.xy + vec2(tail_progress * 0.5, UV.y) * tail_region.zw;
	vec4 tail = texture(tail_texture, tail_uv);
	// The short source's solid paint is alpha 154; match the opaque body at the join.
	tail.a = min(tail.a * tail_opacity_gain, 1.0);
	vec4 body = texture(TEXTURE, body_uv);
	vec4 paint = mix(tail, body, smoothstep(0.55, 1.0, tail_progress));
	COLOR = vec4(paint.rgb, paint.a * opacity);
}
