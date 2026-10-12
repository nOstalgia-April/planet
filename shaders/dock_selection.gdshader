shader_type canvas_item;
render_mode unshaded;

uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float grain_size : hint_range(0.5, 3.0) = 0.8;
uniform vec2 rect_size = vec2(190.0, 76.0);
varying vec2 local_uv;
varying vec4 ink;

float grain(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	local_uv = VERTEX / rect_size;
	ink = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	// Follow the supplied white border, including its hand-drawn contour.
	float border = smoothstep(0.45, 0.9, min(source.r, min(source.g, source.b)));
	float speckle = grain(floor(local_uv * rect_size / grain_size));
	float pigment = mix(0.32, 1.0, smoothstep(0.12, 0.82, speckle));
	float sweep = local_uv.x * 0.72 + local_uv.y * 0.18 + speckle * 0.1;
	float painted = smoothstep(sweep, sweep + 0.12, reveal * 1.14);
	COLOR = vec4(ink.rgb, min(source.a * 2.4, 1.0) * border * pigment * painted * ink.a);
}
