shader_type canvas_item;
render_mode unshaded;

// Use the middle of the cutout so the transparent ends cannot break the ribbon.
uniform vec4 source_region = vec4(0.198, 0.4475, 0.5847, 0.1602);
varying vec4 trail_color;

void vertex() {
	trail_color = COLOR;
}

void fragment() {
	float along = 1.0 - abs(1.0 - mod(UV.x, 2.0));
	vec2 source_uv = source_region.xy + vec2(along, UV.y) * source_region.zw;
	COLOR = trail_color * texture(TEXTURE, source_uv);
}
