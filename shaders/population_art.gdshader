shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/population_palette.gdshaderinc"

varying vec4 item_color;

void vertex() { item_color = COLOR; }

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(population_color(source.rgb), source.a) * item_color;
}
