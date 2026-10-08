shader_type canvas_item;
render_mode unshaded;

uniform vec2 viewport_size = vec2(1280.0, 800.0);
uniform vec2 planet_center = vec2(640.0, 400.0);
uniform float planet_radius = 265.0;
uniform vec4 ecology_color : source_color = vec4(0.35, 0.34, 0.38, 1.0);
uniform float activity : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 eased = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), eased.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), eased.x), eased.y);
}

void fragment() {
	vec2 pixel = UV * viewport_size;
	vec2 from_planet = (pixel - planet_center) / max(planet_radius, 1.0);
	float distance_from_planet = length(from_planet);
	float paper = noise(pixel * 0.13) * 0.58 + noise(pixel * 0.037) * 0.28 + hash(pixel) * 0.14;
	float fibers = sin(pixel.x * 0.83 + pixel.y * 0.41 + noise(pixel * 0.016) * 9.0);
	float halo = exp(-pow((distance_from_planet - 0.96) / 1.13, 2.0));
	float center_shadow = smoothstep(0.35, 0.87, distance_from_planet);
	vec3 neutral = vec3(0.078, 0.076, 0.073);
	vec3 glow = mix(neutral, ecology_color.rgb * 0.54, activity);
	vec3 background = vec3(0.012, 0.016, 0.020);
	background += glow * halo * mix(0.32, 1.0, center_shadow);
	background += (paper - 0.5) * 0.021 + fibers * 0.0018;
	float edge = length((UV - vec2(0.5)) * vec2(viewport_size.x / viewport_size.y, 1.0));
	background *= 1.0 - smoothstep(0.51, 1.14, edge) * 0.84;
	COLOR = vec4(max(background, vec3(0.003)), 1.0);
}
