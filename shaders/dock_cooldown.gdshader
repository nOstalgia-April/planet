shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 accent : source_color = vec4(0.5, 0.65, 1.0, 1.0);
uniform vec2 rect_size = vec2(190.0, 76.0);
varying vec2 local_uv;

void vertex() {
	local_uv = VERTEX / rect_size;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float grain = fract(sin(dot(floor(local_uv * vec2(380.0, 152.0)), vec2(127.1, 311.7))) * 43758.5453);
	float filled = smoothstep(1.0 - progress - 0.012, 1.0 - progress + 0.012, local_uv.y);
	float edge = 1.0 - smoothstep(0.006, 0.025, abs(local_uv.y - (1.0 - progress)));
	vec3 ink = mix(vec3(0.015), accent.rgb, filled);
	ink = mix(ink, vec3(1.0), max(edge * 0.7, flash));
	float opacity = mix(0.52, 0.32 + grain * 0.14, filled);
	opacity = max(opacity, edge * 0.7);
	opacity = mix(opacity, 0.65, flash);
	COLOR = vec4(ink, source.a * opacity);
}
