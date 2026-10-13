shader_type canvas_item;

uniform mat3 sprite_to_art;
uniform mat3 art_to_sprite;
uniform vec2 sprite_rect_origin;
// Circle intersection in art coordinates: y² + 2(b0 + bx*x)y + cx*x² = 0.
uniform vec3 ground_curve = vec3(-1000.0, 0.0, 0.0);
uniform float contact_y = 0.0;
uniform float bend_height = 1.0;
uniform float bottom_padding = 0.0;
uniform bool follow_contour = false;
uniform sampler2D ground_profile : filter_linear, repeat_disable;
uniform sampler2D foot_profile : filter_linear, repeat_disable;
uniform vec2 ground_span;
uniform float ground_overlap = 0.0;
uniform float emergence_progress : hint_range(0.0, 1.0) = 1.0;
uniform float emergence_height = 1.0;
uniform float emergence_width = 1.0;
uniform float emergence_center_x = 0.0;
uniform float emergence_perspective : hint_range(0.0, 1.0) = 0.7;
uniform float emergence_overshoot_degrees : hint_range(0.0, 18.0) = 12.0;

varying vec2 art_position;
varying vec4 vertex_color;

void vertex() {
	// Expand the quad as well as the UV domain so displaced pixels aren't clipped.
	float envelope = max(0.0, sin(emergence_progress * 3.14159265));
	vec2 padding = vec2(
		(UV.x * 2.0 - 1.0) * emergence_width * 0.12 * envelope,
		UV.y * bottom_padding - (1.0 - UV.y) * emergence_height * 0.25 * envelope
	);
	VERTEX += (art_to_sprite * vec3(padding, 0.0)).xy;
	art_position = (sprite_to_art * vec3(VERTEX, 1.0)).xy;
	vertex_color = COLOR;
}

float soil_y(float x) {
	if (!follow_contour) {
		return contact_y;
	}
	float profile_u = (x - ground_span.x) / ground_span.y;
	profile_u = (profile_u * 255.0 + 0.5) / 256.0;
	return texture(ground_profile, vec2(profile_u, 0.5)).r + ground_overlap;
}

float unfolding_angle() {
	// A paper cutout hinges around the soil: edge-on, forward overshoot, rebound.
	float degrees = mix(88.0, -emergence_overshoot_degrees, smoothstep(0.0, 0.62, emergence_progress));
	if (emergence_progress > 0.62) {
		degrees = mix(-emergence_overshoot_degrees, 4.0, smoothstep(0.62, 0.82, emergence_progress));
	}
	if (emergence_progress > 0.82) {
		degrees = mix(4.0, 0.0, smoothstep(0.82, 1.0, emergence_progress));
	}
	return radians(degrees);
}

void fragment() {
	bool unfolding = emergence_progress < 1.0;
	float ground_limit = contact_y;
	vec2 unfolded_position = art_position;
	float hinge_cos = 1.0;
	float denominator = 1.0;
	if (unfolding) {
		ground_limit = soil_y(art_position.x);
		float angle = unfolding_angle();
		hinge_cos = cos(angle);
		float hinge_sin = sin(angle) * emergence_perspective;
		float projected_y = (art_position.y - ground_limit) / max(emergence_height, 1.0);
		// Invert a perspective-projected plane rotated about its bottom X axis.
		// Top pixels change width as well as height; no vertical texture sliding.
		denominator = hinge_cos + projected_y * hinge_sin;
		float plane_y = projected_y / max(denominator, 0.0001);
		float perspective_w = 1.0 - plane_y * hinge_sin;
		unfolded_position.x = emergence_center_x + (art_position.x - emergence_center_x) * perspective_w;
		unfolded_position.y = soil_y(unfolded_position.x) + plane_y * emergence_height;
	}
	float b = ground_curve.x + ground_curve.y * unfolded_position.x;
	float c = ground_curve.z * unfolded_position.x * unfolded_position.x;
	float bend = c / max(-b + sqrt(max(b * b - c, 0.0)), 0.0001);
	float band_start = contact_y - bend_height;
	float source_bottom = contact_y;
	if (follow_contour) {
		vec2 local_pixel = (art_to_sprite * vec3(unfolded_position, 1.0)).xy - sprite_rect_origin;
		vec2 foot = texture(foot_profile, vec2(local_pixel.x * TEXTURE_PIXEL_SIZE.x, 0.5)).rg;
		float ground_y = soil_y(unfolded_position.x);
		if (!unfolding) {
			ground_limit = ground_y;
		}
		source_bottom = (sprite_to_art * vec3(local_pixel.x + sprite_rect_origin.x, foot.r + sprite_rect_origin.y, 1.0)).y;
		// Only columns with actual artwork in the contact strip get pulled to the soil.
		bend = foot.g > 0.5 && source_bottom > band_start ? ground_y - source_bottom : 0.0;
		band_start = min(band_start, source_bottom - max(1.0, -2.1 * bend));
	}
	float height = max(1.0, source_bottom - band_start);
	float distance = max(unfolded_position.y - band_start, 0.0);
	// Invert y = band_start + height*t + bend*t² analytically.
	// The quadratic starts with zero slope, preserving the upper silhouette.
	float t = 2.0 * distance / (height + sqrt(max(height * height + 4.0 * bend * distance, 0.0001)));
	vec2 source_position = unfolded_position;
	if (unfolded_position.y > source_bottom + bend) {
		source_position.y -= bend;
	} else if (unfolded_position.y > band_start) {
		source_position.y = band_start + height * t;
	}
	vec2 source_uv = ((art_to_sprite * vec3(source_position, 1.0)).xy - sprite_rect_origin) * TEXTURE_PIXEL_SIZE;
	vec4 texel = texture(TEXTURE, source_uv);
	if (any(lessThan(source_uv, vec2(0.0))) || any(greaterThan(source_uv, vec2(1.0)))) {
		texel = vec4(0.0);
	}
	texel.rgb *= mix(0.68, 1.0, hinge_cos);
	texel.a *= smoothstep(0.0, 0.055, emergence_progress) * step(0.0001, denominator);
	if (follow_contour) {
		// Smooth warping preserves texture continuity; this cut follows the exact soil edge.
		float feather = max(fwidth(art_position.y), 0.001);
		texel.a *= 1.0 - smoothstep(ground_limit - feather, ground_limit, art_position.y);
	}
	COLOR = texel * vertex_color;
}
