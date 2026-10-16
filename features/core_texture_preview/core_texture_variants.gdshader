shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/population_palette.gdshaderinc"
#include "res://shaders/planet_core_paper.gdshaderinc"

// Coordinates are inside one cropped frame, not the whole streaming atlas.
uniform vec4 frame_region = vec4(0.0, 0.0, 356.0, 300.0);
uniform vec2 core_center = vec2(178.0, 164.5);
uniform float core_radius : hint_range(1.0, 100.0) = 57.5;
uniform vec4 core_color : source_color = vec4(1.0, 0.0, 0.5019608, 1.0);
uniform float outer_deformation : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform sampler2D core_brush_texture : source_color, filter_linear_mipmap, repeat_disable;
// Use the original concept canvas directly; sample only inside its painted disk.
uniform vec2 brush_center_uv = vec2(0.542592593, 0.507407407);
uniform float brush_radius_uv = 0.293518519;
uniform float brush_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform int variant_mode : hint_range(0, 2, 1) = 1;
uniform float motion_seconds = 0.0;

varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

float painted_extent(sampler2D atlas, vec2 pixel_size, vec2 direction) {
	// Find this frame's silhouette along the ray. The same atlas frame drives
	// both the outline and the brush stretch, including music pauses and seeks.
	vec2 reach = mix(core_center - vec2(0.5), frame_region.zw - core_center - vec2(0.5), step(vec2(0.0), direction));
	vec2 limits = reach / max(abs(direction), vec2(0.001));
	float low = core_radius;
	float high = max(core_radius, min(limits.x, limits.y));
	for (int sample_index = 0; sample_index < 8; sample_index++) {
		float probe = (low + high) * 0.5;
		vec2 atlas_uv = (frame_region.xy + core_center + direction * probe) * pixel_size;
		if (textureLod(atlas, atlas_uv, 0.0).a >= 0.5) {
			low = probe;
		} else {
			high = probe;
		}
	}
	return core_radius + (low - core_radius) * outer_deformation;
}

vec2 painted_point(sampler2D atlas, vec2 pixel_size, vec2 from_center, float radius) {
	vec2 direction = from_center / max(radius, 0.001);
	if (variant_mode != 1) {
		// A: stretch the entire painted disk with the animated silhouette.
		float extent = painted_extent(atlas, pixel_size, direction);
		float normalized_radius = clamp(radius / extent, 0.0, 1.0);
		if (variant_mode == 2) {
			// C: advect pigment around the same silhouette using the source
			// frame clock. Pausing or seeking repeats the exact same material.
			float angle = atan(direction.y, direction.x);
			float rim = smoothstep(0.35, 0.86, normalized_radius);
			float drift = rim * (motion_seconds * 0.65 + 0.16 * sin(angle * 3.0 - motion_seconds * 1.4));
			float breathing = sin(normalized_radius * 3.141592654) * rim;
			normalized_radius += breathing * (0.035 * sin(angle * 5.0 + motion_seconds * 3.2) + 0.012 * sin(angle * 11.0 - motion_seconds * 4.1));
			direction = vec2(cos(angle + drift), sin(angle + drift));
		}
		return direction * clamp(normalized_radius, 0.0, 1.0);
	}
	// Keep the inner disk anchored. The surrounding pigment fans out into
	// each lobe instead of leaving a hard circular seam underneath the motion.
	float anchor = core_radius * 0.78;
	float brush_radius = radius / core_radius * 0.85;
	if (radius > anchor) {
		float extent = painted_extent(atlas, pixel_size, direction);
		brush_radius = mix(0.663, 1.0, clamp((radius - anchor) / max(extent - anchor, 0.001), 0.0, 1.0));
	}
	return direction * brush_radius;
}

void fragment() {
	vec2 local_pixel = UV / TEXTURE_PIXEL_SIZE - frame_region.xy;
	vec2 from_center = local_pixel - core_center;
	float radius = length(from_center);
	// Keep the radius of the core fixed. Only distance beyond its edge is reduced:
	// displayed_radius = core_radius + (source_radius - core_radius) * strength.
	float source_radius = core_radius + max(radius - core_radius, 0.0) / max(outer_deformation, 0.001);
	vec2 source_pixel = core_center + from_center / max(radius, 0.001) * source_radius;
	vec4 outer = vec4(0.0);
	if (outer_deformation > 0.0 && all(greaterThanEqual(source_pixel, vec2(0.5))) && all(lessThan(source_pixel, frame_region.zw - vec2(0.5)))) {
		outer = texture(TEXTURE, (frame_region.xy + source_pixel) * TEXTURE_PIXEL_SIZE);
	}
	// A fixed, antialiased circle replaces the compressed, frame-dependent inner disk.
	float edge = max(fwidth(radius), 0.75);
	float core_alpha = 1.0 - smoothstep(core_radius - edge * 0.5, core_radius + edge * 0.5, radius);
	float alpha = core_alpha + outer.a * (1.0 - core_alpha);
	vec3 premultiplied = core_color.rgb * core_alpha + outer.rgb * outer.a * (1.0 - core_alpha);
	vec3 original = premultiplied / max(alpha, 0.00001);
	vec3 painted = original;
	vec2 paper_point = from_center / core_radius;
	if (alpha > 0.001 && brush_strength > 0.0) {
		vec2 brush_point = painted_point(TEXTURE, TEXTURE_PIXEL_SIZE, from_center, radius);
		vec3 brush = texture(core_brush_texture, brush_center_uv + brush_point * brush_radius_uv).rgb;
		painted = mix(original, brush, brush_strength);
		// The paper reveal follows the same silhouette so its clamped border
		// cannot smear into straight stripes when a lobe stretches past the disk.
		paper_point = mix(paper_point, brush_point, brush_strength);
	}
	vec3 colored = population_color(painted);
	vec3 paper = core_paper_color(paper_point);
	COLOR = vec4(mix(colored, paper, core_white_mix), alpha) * item_color;
}
