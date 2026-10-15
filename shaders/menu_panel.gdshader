shader_type canvas_item;
render_mode unshaded;

uniform vec4 accent : source_color = vec4(0.533, 0.118, 0.208, 1.0);
uniform float panel_height = 400.0;

varying float panel_y;

void vertex() {
	panel_y = VERTEX.y;
}

void fragment() {
	float fade = smoothstep(0.04, 0.82, panel_y / max(panel_height, 1.0));
	COLOR.rgb = mix(COLOR.rgb * accent.rgb * 4.0, COLOR.rgb, fade);
}
