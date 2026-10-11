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

varying vec2 art_position;
varying vec4 vertex_color;

void vertex() {
	// Expand the quad as well as the UV domain so displaced pixels aren't clipped.
	VERTEX += (art_to_sprite * vec3(0.0, UV.y * bottom_padding, 0.0)).xy;
	art_position = (sprite_to_art * vec3(VERTEX, 1.0)).xy;
	vertex_color = COLOR;
}

void fragment() {
	float b = ground_curve.x + ground_curve.y * art_position.x;
	float c = ground_curve.z * art_position.x * art_position.x;
	float bend = c / max(-b + sqrt(max(b * b - c, 0.0)), 0.0001);
	float band_start = contact_y - bend_height;
	float source_bottom = contact_y;
	float ground_limit = contact_y;
	if (follow_contour) {
		vec2 local_pixel = (art_to_sprite * vec3(art_position, 1.0)).xy - sprite_rect_origin;
		vec2 foot = texture(foot_profile, vec2(local_pixel.x * TEXTURE_PIXEL_SIZE.x, 0.5)).rg;
		float profile_u = (art_position.x - ground_span.x) / ground_span.y;
		profile_u = (profile_u * 255.0 + 0.5) / 256.0;
		float ground_y = texture(ground_profile, vec2(profile_u, 0.5)).r + ground_overlap;
		ground_limit = ground_y;
		source_bottom = (sprite_to_art * vec3(local_pixel.x + sprite_rect_origin.x, foot.r + sprite_rect_origin.y, 1.0)).y;
		// Only columns with actual artwork in the contact strip get pulled to the soil.
		bend = foot.g > 0.5 && source_bottom > band_start ? ground_y - source_bottom : 0.0;
		band_start = min(band_start, source_bottom - max(1.0, -2.1 * bend));
	}
	float height = max(1.0, source_bottom - band_start);
	float distance = max(art_position.y - band_start, 0.0);
	// Invert y = band_start + height*t + bend*t² analytically.
	// The quadratic starts with zero slope, preserving the upper silhouette.
	float t = 2.0 * distance / (height + sqrt(max(height * height + 4.0 * bend * distance, 0.0001)));
	vec2 source_position = art_position;
	if (art_position.y > source_bottom + bend) {
		source_position.y -= bend;
	} else if (art_position.y > band_start) {
		source_position.y = band_start + height * t;
	}
	vec2 source_uv = ((art_to_sprite * vec3(source_position, 1.0)).xy - sprite_rect_origin) * TEXTURE_PIXEL_SIZE;
	vec4 texel = texture(TEXTURE, source_uv);
	if (any(lessThan(source_uv, vec2(0.0))) || any(greaterThan(source_uv, vec2(1.0)))) {
		texel = vec4(0.0);
	}
	if (follow_contour) {
		// Smooth warping preserves texture continuity; this cut follows the exact soil edge.
		float feather = max(fwidth(art_position.y), 0.001);
		texel.a *= 1.0 - smoothstep(ground_limit - feather, ground_limit, art_position.y);
	}
	COLOR = texel * vertex_color;
}
