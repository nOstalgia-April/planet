shader_type canvas_item;
render_mode unshaded;

uniform vec4 ink : source_color = vec4(0.0, 0.0, 0.0, 1.0);
varying vec4 tint;

void vertex() { tint = COLOR; }

void fragment() {
	COLOR = vec4(ink.rgb, texture(TEXTURE, UV).a * ink.a) * tint;
}
