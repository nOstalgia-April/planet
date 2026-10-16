shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/population_palette.gdshaderinc"
#include "res://shaders/planet_core_paper.gdshaderinc"

// Coordinates are inside one cropped frame, not the whole streaming atlas.
uniform vec4 frame_region = vec4(0.0, 0.0, 356.0, 300.0);
uniform vec2 core_center = vec2(178.0, 164.5);
uniform float core_radius : hint_range(1.0, 100.0) = 57.5;
uniform float outer_deformation : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform sampler2D core_brush_texture : source_color, filter_linear_mipmap, repeat_disable;
// Use the original concept canvas directly; sample only inside its painted disk.
uniform vec2 brush_center_uv = vec2(0.542592593, 0.507407407);
uniform float brush_radius_uv = 0.293518519;
// Retain finer brush strokes while still filtering small on-screen cores.
uniform float brush_mip_bias : hint_range(-1.5, 0.0, 0.05) = -0.75;
// Retained for the shared animation clock; B pigment is anchored.
uniform float motion_seconds = 0.0;
uniform float outline_width : hint_range(1.0, 6.0, 0.25) = 2.75;
uniform float brush_detail_strength : hint_range(0.0, 1.0, 0.05) = 0.22;

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

vec2 painted_point(vec2 from_center, float radius, float extent) {
	// B keeps the core pigment fixed; only the rim stretches into each lobe.
	vec2 direction = from_center / max(radius, 0.001);
	float anchor = core_radius * 0.78;
	float brush_radius = radius / core_radius * 0.85;
	if (radius > anchor) {
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
	// Tighten the source alpha to a one-screen-pixel antialiased boundary.
	// This removes the atlas fringe without replacing the animated silhouette.
	float alpha_width = max(fwidth(outer.a) * 0.5, 1.0 / 255.0);
	outer.a = smoothstep(0.5 - alpha_width, 0.5 + alpha_width, outer.a);
	float edge = max(fwidth(radius), 0.75);
	float core_alpha = 1.0 - smoothstep(core_radius - edge * 0.5, core_radius + edge * 0.5, radius);
	float alpha = core_alpha + outer.a * (1.0 - core_alpha);
	// Use the stable screen scale for filtering rather than local contour steps.
	// Keep minification filtered while preserving the fine brush strokes.
	float pixel_span = max(length(dFdx(from_center)), length(dFdy(from_center)));
	vec2 brush_size = vec2(textureSize(core_brush_texture, 0));
	float texel_span = pixel_span * brush_radius_uv * max(brush_size.x, brush_size.y) / core_radius;
	float brush_lod = max(log2(max(texel_span, 1.0)) + brush_mip_bias, 0.0);
	vec3 result = vec3(0.0);
	if (alpha > 0.0) {
		vec2 direction = from_center / max(radius, 0.001);
		float extent = painted_extent(TEXTURE, TEXTURE_PIXEL_SIZE, direction);
		vec2 brush_point = painted_point(from_center, radius, extent);
		vec3 brush = textureLod(core_brush_texture, brush_center_uv + brush_point * brush_radius_uv, brush_lod).rgb;
		vec3 fill = population_color(textureLod(core_brush_texture, brush_center_uv, brush_lod).rgb);
		vec3 painted = population_color(brush);
		vec3 colored = mix(fill, painted, brush_detail_strength);
		// A broad contour remains legible against the black interior of the planet.
		// One colored rim and one dark stroke replace the many hairline rings.
		float distance_to_edge = extent - radius;
		float stroke_width = max(outline_width, pixel_span * 1.5);
		float aa = max(pixel_span * 0.6, 0.25);
		float rim = 1.0 - smoothstep(stroke_width - aa, stroke_width + aa, distance_to_edge);
		float ink = smoothstep(stroke_width - aa, stroke_width + aa, distance_to_edge)
			* (1.0 - smoothstep(stroke_width * 2.0 - aa, stroke_width * 2.0 + aa, distance_to_edge));
		vec3 rim_color = mix(fill, vec3(1.0), 0.22);
		vec3 ink_color = fill * 0.28;
		colored = mix(colored, ink_color, ink * 0.92);
		colored = mix(colored, rim_color, rim);
		vec3 paper = core_paper_color(brush_point);
		// The white phase keeps a quiet, darker contour rather than losing its outline.
		paper = mix(paper, vec3(0.32, 0.30, 0.29), ink * 0.72);
		result = mix(colored, paper, core_white_mix);
	}
	COLOR = vec4(result, alpha) * item_color;
}
