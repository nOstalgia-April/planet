shader_type canvas_item;

// Exclude neighboring atlas artwork without changing the supplied sprite pixels.
uniform vec4 excluded_region = vec4(0.0);

void fragment() {
	vec2 source_pixel = UV / TEXTURE_PIXEL_SIZE;
	if (excluded_region.z > 0.0 && source_pixel.x >= excluded_region.x
			&& source_pixel.y >= excluded_region.y
			&& source_pixel.x < excluded_region.x + excluded_region.z
			&& source_pixel.y < excluded_region.y + excluded_region.w) {
		COLOR.a = 0.0;
	}
}
