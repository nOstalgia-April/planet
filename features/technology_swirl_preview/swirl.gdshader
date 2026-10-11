// Adapted from Paper Shaders' Swirl by Lost Coast Labs, Inc. (Apache-2.0).
// Source revision: 43cd68db79fa0b1759f72ffc941b3238e2a3954c.
// Changes: Godot CanvasItem coordinates/uniforms, three editable colors,
// premultiplied blending, and a deterministic preview-time override.
// See THIRD_PARTY_NOTICES.txt for the original notice and license.
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform vec4 background_color : source_color = vec4(0.071, 0.016, 0.035, 1.0);
uniform vec4 color_a : source_color = vec4(0.36, 0.11, 0.20, 1.0);
uniform vec4 color_b : source_color = vec4(0.58, 0.23, 0.38, 1.0);
uniform vec4 color_c : source_color = vec4(0.30, 0.48, 0.43, 1.0);
uniform float band_count : hint_range(0.0, 15.0, 1.0) = 2.0;
uniform float twist : hint_range(0.0, 1.0) = 0.6;
uniform float center : hint_range(0.0, 1.0) = 1.0;
uniform float proportion : hint_range(0.0, 1.0) = 0.5;
uniform float softness : hint_range(0.0, 1.0) = 1.0;
uniform float noise_amount : hint_range(0.0, 1.0) = 0.0;
uniform float noise_frequency : hint_range(0.0, 1.0) = 0.5;
uniform float speed : hint_range(-3.0, 3.0) = 1.0;
uniform float pattern_scale : hint_range(0.01, 4.0) = 1.0;
uniform float rotation_degrees : hint_range(0.0, 360.0) = 0.0;
uniform vec2 offset = vec2(0.0);
// Negative uses Godot TIME * speed. Nonnegative fixes Paper's u_time in seconds.
uniform float effect_time = -1.0;

vec3 permute(vec3 x) {
	return mod(((x * 34.0) + 1.0) * x, 289.0);
}

float simplex_noise(vec2 v) {
	const vec4 coefficients = vec4(
		0.211324865405187, 0.366025403784439,
		-0.577350269189626, 0.024390243902439
	);
	vec2 cell = floor(v + dot(v, coefficients.yy));
	vec2 point = v - cell + dot(cell, coefficients.xx);
	vec2 corner = (point.x > point.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec4 adjacent = point.xyxy + coefficients.xxzz;
	adjacent.xy -= corner;
	cell = mod(cell, 289.0);
	vec3 permutation = permute(
		permute(cell.y + vec3(0.0, corner.y, 1.0))
		+ cell.x + vec3(0.0, corner.x, 1.0)
	);
	vec3 weight = max(0.5 - vec3(
		dot(point, point), dot(adjacent.xy, adjacent.xy), dot(adjacent.zw, adjacent.zw)
	), 0.0);
	weight *= weight;
	weight *= weight;
	vec3 x = 2.0 * fract(permutation * coefficients.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;
	weight *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 gradient;
	gradient.x = a0.x * point.x + h.x * point.y;
	gradient.yz = a0.yz * adjacent.xz + h.yz * adjacent.yw;
	return 130.0 * dot(weight, gradient);
}

void fragment() {
	// Paper's default contain fit uses a centered square with the shorter side.
	// Godot's downward-positive UV.y is flipped to match WebGL's object UV.
	vec2 rectangle_size = 1.0 / fwidth(UV);
	vec2 shape_uv = (UV - vec2(0.5)) * vec2(1.0, -1.0);
	shape_uv *= rectangle_size / min(rectangle_size.x, rectangle_size.y);
	shape_uv += vec2(-offset.x, offset.y);
	shape_uv /= pattern_scale;
	float rotation = radians(rotation_degrees);
	shape_uv = mat2(
		vec2(cos(rotation), sin(rotation)),
		vec2(-sin(rotation), cos(rotation))
	) * shape_uv;

	float radius = max(0.0001, length(shape_uv));
	float time = effect_time >= 0.0 ? effect_time : TIME * speed;
	float angle = ceil(band_count) * atan(shape_uv.y, shape_uv.x) + time;
	float angle_normalized = angle / TAU;
	float twist_power = 3.0 * clamp(twist, 0.0, 1.0);
	float phase = pow(radius, -twist_power) + angle_normalized;
	float shape = fract(phase);
	shape = 1.0 - abs(2.0 * shape - 1.0);
	if (noise_amount > 0.0) {
		shape += noise_amount * simplex_noise(15.0 * pow(noise_frequency, 2.0) * shape_uv);
	}
	float middle = smoothstep(0.2, 0.2 + 0.8 * center, pow(radius, twist_power));
	shape = mix(0.0, shape, middle);

	float color_proportion = clamp(proportion, 0.0, 1.0);
	float exponent = mix(0.25, 1.0, color_proportion * 2.0);
	exponent = mix(exponent, 10.0, max(0.0, color_proportion * 2.0 - 1.0));
	shape = pow(shape, exponent);

	float mixer = shape * 3.0;
	vec4 gradient = color_a;
	gradient.rgb *= gradient.a;
	float outer_shape = 0.0;
	for (int i = 1; i <= 3; i++) {
		float amount = clamp(mixer - float(i - 1), 0.0, 1.0);
		float antialiasing = fwidth(amount);
		amount = smoothstep(
			0.5 - 0.5 * softness - antialiasing,
			0.5 + 0.5 * softness + antialiasing,
			amount
		);
		if (i == 1) {
			outer_shape = amount;
		}
		vec4 band_color = color_a;
		if (i == 2) {
			band_color = color_b;
		} else if (i == 3) {
			band_color = color_c;
		}
		band_color.rgb *= band_color.a;
		gradient = mix(gradient, band_color, amount);
	}
	float middle_antialiasing = 0.1 * fwidth(pow(radius, -twist_power));
	float outer_middle = smoothstep(0.2, 0.2 + middle_antialiasing, pow(radius, twist_power));
	outer_shape = mix(0.0, outer_shape, outer_middle);

	vec3 color = gradient.rgb * outer_shape;
	float opacity = gradient.a * outer_shape;
	vec3 background = background_color.rgb * background_color.a;
	color += background * (1.0 - opacity);
	opacity += background_color.a * (1.0 - opacity);
	// Original sub-8-bit dithering prevents visible bands in the soft gradients.
	color += (1.0 / 256.0) * (
		fract(sin(dot(0.014 * FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453123) - 0.5
	);
	COLOR = vec4(color, opacity);
}
