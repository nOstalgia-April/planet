shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/dock_surface.gdshaderinc"

uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 accent : source_color = vec4(0.53, 0.12, 0.21, 1.0);
varying vec4 item_color;

void vertex() { item_color = COLOR; }

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float colored = smoothstep(0.08, 0.3, source.r - source.g);
	COLOR = vec4(mix(source.rgb, accent.rgb, colored), dock_surface_alpha(source, hover_amount)) * item_color;
}
