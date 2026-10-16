shader_type canvas_item;
render_mode unshaded;

uniform float reveal : hint_range(0.0, 1.0) = 0.0;
varying vec4 item_color;

void vertex() { item_color = COLOR; }

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(item_color.rgb, source.a * item_color.a * reveal);
}
