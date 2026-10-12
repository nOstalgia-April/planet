shader_type canvas_item;
render_mode unshaded;

varying vec4 trail_color;

void vertex() {
	trail_color = COLOR;
}

void fragment() {
	COLOR = trail_color * texture(TEXTURE, UV);
}
