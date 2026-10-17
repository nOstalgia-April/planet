shader_type canvas_item;
render_mode unshaded;

uniform sampler2D jewelry_mask : filter_linear, repeat_disable;
uniform vec4 mask_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 texture_size = vec2(1.0);
uniform float phase = -1.0;
varying vec4 canvas_tint;

void vertex() {
	canvas_tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (phase >= 0.0 && phase <= 1.0) {
		vec2 pixel = UV * texture_size;
		vec2 mask_uv = (pixel - mask_region.xy) / mask_region.zw;
		float inside = step(0.0, mask_uv.x) * step(mask_uv.x, 1.0)
			* step(0.0, mask_uv.y) * step(mask_uv.y, 1.0);
		float projection = ((pixel.x - bounds.x) + (bounds.w - pixel.y))
			/ ((bounds.z - bounds.x) + (bounds.w - bounds.y));
		float centre = mix(-0.20, 1.20, phase);
		float distance_to_band = abs(projection - centre);
		float core = 1.0 - smoothstep(0.035, 0.12, distance_to_band);
		float soft_edge = 1.0 - smoothstep(0.09, 0.22, distance_to_band);
		float amount = clamp(core * 0.91 + soft_edge * 0.20, 0.0, 1.0);
		amount *= texture(jewelry_mask, mask_uv).r * inside;
		source.rgb = mix(source.rgb, vec3(1.0), amount);
	}
	COLOR = source * canvas_tint;
}
