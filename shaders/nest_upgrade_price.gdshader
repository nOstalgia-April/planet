shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint : source_color = vec4(0.878, 0.0, 0.392, 1.0);
uniform float flow_time = 0.0;
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform float availability : hint_range(0.0, 1.0) = 1.0;
varying vec2 text_position;
varying float is_fill;

void vertex() {
	// Glyph atlas UVs restart per digit; local positions keep the sweep continuous.
	text_position = VERTEX;
	is_fill = step(0.5, max(COLOR.r, max(COLOR.g, COLOR.b)));
}

void fragment() {
	float phase = text_position.x * 0.105 - text_position.y * 0.045 - flow_time * 2.2;
	float wave = 0.5 + 0.5 * sin(phase);
	float sheen = pow(0.5 + 0.5 * sin(phase + 0.9), 9.0);
	vec3 milk = vec3(1.0, 0.94, 0.79);
	vec3 ink = mix(mix(tint.rgb, milk, 0.28), milk, smoothstep(0.15, 0.95, wave));
	ink = mix(ink, vec3(1.0, 0.99, 0.94), sheen * (0.7 + hover_amount * 0.25));
	ink = mix(vec3(0.72, 0.65, 0.69), ink, availability);
	// Keep the dark outline and Godot's font alpha intact.
	COLOR.rgb *= mix(vec3(1.0), ink, is_fill);
}
