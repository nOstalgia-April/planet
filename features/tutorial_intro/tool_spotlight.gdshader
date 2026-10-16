shader_type canvas_item;
render_mode unshaded;

uniform vec2 focus_center = vec2(0.0);
uniform vec2 focus_half_size = vec2(100.0, 40.0);
uniform vec2 viewport_size = vec2(1280.0, 800.0);
uniform float corner_radius = 20.0;

void fragment() {
	vec2 q = abs(UV * viewport_size - focus_center) - focus_half_size + corner_radius;
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner_radius;
	float shade = smoothstep(1.0, 18.0, distance) * 0.7;
	float rim = (1.0 - smoothstep(0.0, 3.0, abs(distance))) * 0.85;
	COLOR = vec4(mix(vec3(0.035, 0.025, 0.07), vec3(1.0, 0.89, 0.59), rim), max(shade, rim));
}
