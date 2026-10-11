shader_type canvas_item;

uniform vec2 center_uv = vec2(0.4792779, 0.5025249);
uniform float radius_width_ratio = 0.3788457;
uniform sampler2D flow_map : filter_linear, repeat_disable;
uniform vec4 flow_bounds = vec4(-0.78, -0.06, 1.56, 0.66);
uniform vec4 territory_color : source_color = vec4(1.0, 0.42, 0.62, 1.0);
uniform vec4 mucus_color : source_color = vec4(0.36, 0.38, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 1.0;
uniform float claim_progress : hint_range(0.0, 1.0) = 1.0;
uniform float mucus_progress : hint_range(0.0, 1.0) = 1.0;
uniform vec2 drip_progress = vec2(0.0);
uniform vec4 pink_drips[3];
uniform vec4 blue_drips[3];
uniform float shape_seed = 12.0;
uniform bool mucus_on_top = true;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

float drip_mask(vec2 point, vec4 outlet, float progress, float index) {
	if (progress <= 0.0 || outlet.z <= 0.0) { return 0.0; }
	float delay = 0.04 + index * 0.075;
	float t = clamp((progress - delay) / (0.88 - delay), 0.0, 1.0);
	float grow = smoothstep(0.12, 0.66, t);
	float release = smoothstep(0.76, 0.92, t);
	float length_now = outlet.w * grow;
	float retained = length_now * (1.0 - release * 0.34);
	float local_y = point.y - outlet.y;
	float along = clamp(local_y / max(retained, 0.001), 0.0, 1.0);
	float bend = sin(index * 2.1 + shape_seed) * outlet.z * 0.7;
	float center_x = outlet.x + bend * along * along;
	float width = outlet.z * mix(0.95, 0.45, along);
	float body = length(vec2(point.x - center_x, max(max(-local_y, local_y - retained), 0.0))) - width;
	float head_y = outlet.y + length_now + release * release * outlet.w * 0.72;
	vec2 head_delta = point - vec2(outlet.x + bend, head_y);
	float radius = outlet.z * mix(0.65, 1.25, smoothstep(0.0, 0.18, t));
	float head = length(head_delta / vec2(0.92, 1.23)) - radius;
	float aa = max(fwidth(point.y), 0.0005);
	float body_mask = 1.0 - smoothstep(-aa, aa, body);
	float head_mask = (1.0 - smoothstep(-aa, aa, head)) * (1.0 - smoothstep(0.93, 1.0, t));
	return max(body_mask, head_mask) * smoothstep(0.0, 0.10, t);
}

vec3 flat_paint(vec3 pigment, vec2 ground) {
	// Printed colour and dry grain only: no bevel, specular, normal or rock lighting.
	float paper = hash(floor(ground * 1550.0)) - 0.5;
	float patch = sin(ground.x * 9.0 + sin(ground.y * 12.0 + shape_seed * 0.1) * 1.4)
		+ sin(ground.y * 21.0 - ground.x * 6.0) * 0.32;
	float grain_density = mix(0.35, 1.0, smoothstep(-0.4, 0.6, patch));
	return pigment + paper * 0.085 * grain_density;
}

void fragment() {
	vec4 original = COLOR;
	vec2 texture_size = vec2(textureSize(TEXTURE, 0));
	vec2 point = (UV - center_uv) * vec2(1.0, texture_size.y / texture_size.x) / radius_width_ratio;
	vec2 ground = vec2(-point.x, 1.0 - point.y);
	vec2 field_uv = (ground - flow_bounds.xy) / flow_bounds.zw;
	float in_bounds = step(0.0, field_uv.x) * step(field_uv.x, 1.0)
		* step(0.0, field_uv.y) * step(field_uv.y, 1.0);
	vec4 field = texture(flow_map, field_uv);
	vec2 progress = vec2(claim_progress, mucus_progress);
	float resistance = noise(ground * 8.0 + shape_seed);
	vec2 pressure = progress + sin(progress * 3.14159265) * 0.018
		* sin(progress * 15.0 + resistance * 6.0 + vec2(0.0, 2.3));
	vec2 contour_aa = max(fwidth(field.ba), vec2(0.0004));
	vec2 contours = 1.0 - smoothstep(-contour_aa, contour_aa, field.ba);
	vec2 front_aa = max(fwidth(field.rg), vec2(0.0015));
	vec2 fronts = 1.0 - smoothstep(pressure - front_aa, pressure + front_aa, field.rg);
	vec2 coats = contours * fronts * step(vec2(0.001), progress);
	for (int i = 0; i < 3; i++) {
		coats.x = max(coats.x, drip_mask(ground, pink_drips[i], drip_progress.x, float(i)));
		coats.y = max(coats.y, drip_mask(ground, blue_drips[i], drip_progress.y, float(i) + 0.5));
	}
	coats *= in_bounds;
	vec3 pink = mix(original.rgb, flat_paint(territory_color.rgb, ground), tint_strength);
	vec3 blue = mix(original.rgb, flat_paint(mucus_color.rgb, ground), tint_strength);
	// The top coat is independent of the lower coat, including its drips.
	vec3 painted = mucus_on_top
		? mix(mix(original.rgb, pink, coats.x), blue, coats.y)
		: mix(mix(original.rgb, blue, coats.y), pink, coats.x);
	COLOR = vec4(painted, original.a);
}
