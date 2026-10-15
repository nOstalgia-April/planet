shader_type canvas_item;

// Split the moon from the original five star frames without changing the art.
uniform bool moon_only = false;
uniform vec2 moon_center = vec2(270.0, 232.0);
uniform float moon_radius = 126.0;

void fragment() {
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;
	float inside = 1.0 - step(moon_radius, distance(pixel, moon_center));
	COLOR.a *= moon_only ? inside : (1.0 - inside);
}
