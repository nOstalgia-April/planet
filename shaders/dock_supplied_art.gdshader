shader_type canvas_item;
render_mode unshaded;

uniform sampler2D active_texture : source_color, filter_linear;
uniform bool has_active_texture = false;
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform float selected : hint_range(0.0, 1.0) = 0.0;
varying vec4 item_color;

void vertex() { item_color = COLOR; }

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (has_active_texture) {
		source = mix(source, texture(active_texture, UV), max(selected, hover_amount));
	} else {
		source.rgb = mix(source.rgb, min(source.rgb + vec3(0.08), vec3(1.0)), hover_amount);
	}
	COLOR = source * item_color;
}
