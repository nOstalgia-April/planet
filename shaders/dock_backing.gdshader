shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/dock_surface.gdshaderinc"

uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
varying vec4 item_color;

void vertex() { item_color = COLOR; }

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(source.rgb, dock_surface_alpha(source, hover_amount)) * item_color;
}
