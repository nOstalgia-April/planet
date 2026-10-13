shader_type canvas_item;
render_mode unshaded;

uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform float selected : hint_range(0.0, 1.0) = 0.0;
uniform vec4 accent : source_color = vec4(0.5, 0.65, 1.0, 1.0);

void fragment() {
	vec2 point = abs((UV - 0.5) * vec2(32.0, 22.0)) - vec2(12.0, 7.0);
	float distance = length(max(point, vec2(0.0))) + min(max(point.x, point.y), 0.0) - 3.0;
	float mask = 1.0 - smoothstep(-0.6, 0.6, distance);
	float rim = smoothstep(-1.8, -0.7, distance);
	float grain = fract(sin(dot(floor(UV * vec2(64.0, 44.0)), vec2(127.1, 311.7))) * 43758.5453);
	vec3 ink = mix(vec3(0.07 + grain * 0.08), vec3(0.34 + grain * 0.22), hover_amount);
	ink = mix(ink, accent.rgb * (0.65 + hover_amount * 0.12), selected);
	vec3 border = mix(vec3(0.65), mix(accent.rgb, vec3(1.0), 0.35), selected);
	COLOR = vec4(mix(ink, border, rim * (0.65 + hover_amount * 0.35)), mask);
}
