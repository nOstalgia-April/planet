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

varying vec4 item_color;

void vertex() {
	item_color = COLOR;
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
	vec3 colored = population_color(premultiplied / max(alpha, 0.00001));
	vec3 paper = core_paper_color(from_center / core_radius);
	COLOR = vec4(mix(colored, paper, core_white_mix), alpha) * item_color;
}
