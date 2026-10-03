shader_type canvas_item;
render_mode unshaded;

uniform vec4 orientation = vec4(0.0, 0.0, 0.0, 1.0);
uniform float camera_distance = 0.0;
uniform vec3 sea_color : source_color = vec3(0.54, 0.66, 0.59);
uniform vec3 land_color : source_color = vec3(0.88, 0.88, 0.73);
uniform vec3 ink_color : source_color = vec3(0.26, 0.37, 0.31);

vec3 rotate_by_quaternion(vec3 point, vec4 rotation) {
	return point + 2.0 * cross(rotation.xyz, cross(rotation.xyz, point) + rotation.w * point);
}

float hash31(vec3 point) {
	return fract(sin(dot(point, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float noise3(vec3 point) {
	vec3 cell = floor(point);
	vec3 f = fract(point);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash31(cell), hash31(cell + vec3(1,0,0)), f.x),
			mix(hash31(cell + vec3(0,1,0)), hash31(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash31(cell + vec3(0,0,1)), hash31(cell + vec3(1,0,1)), f.x),
			mix(hash31(cell + vec3(0,1,1)), hash31(cell + vec3(1,1,1)), f.x), f.y), f.z);
}

float terrain(vec3 point) {
	return noise3(point * 3.8 + vec3(8.2, 2.3, 5.7)) * 0.68
		+ noise3(point * 9.0 + vec3(1.9, 9.3, 2.0)) * 0.22
		+ noise3(point * 21.0) * 0.10;
}

void fragment() {
	vec2 disc = (UV - vec2(0.5)) * 2.0;
	float radial_distance = length(disc);
	float aa = max(fwidth(radial_distance), 0.001);
	float opacity = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, radial_distance);
	vec2 bounded_disc = disc / max(1.0, radial_distance);
	vec3 view_point = vec3(bounded_disc.x, -bounded_disc.y, sqrt(max(0.0, 1.0 - dot(bounded_disc, bounded_disc))));
	if (camera_distance > 1.0) {
		// UV is normalized by the sphere silhouette radius, f / sqrt(d*d - 1).
		float silhouette_factor = sqrt(camera_distance * camera_distance - 1.0);
		vec3 ray_direction = normalize(vec3(bounded_disc.x, -bounded_disc.y, -silhouette_factor));
		vec3 camera_position = vec3(0.0, 0.0, camera_distance);
		float camera_dot_ray = dot(camera_position, ray_direction);
		float discriminant = camera_dot_ray * camera_dot_ray - (camera_distance * camera_distance - 1.0);
		float nearest_distance = -camera_dot_ray - sqrt(max(0.0, discriminant));
		view_point = normalize(camera_position + nearest_distance * ray_direction);
	}
	// A visible surface point is transformed back to geography before sampling.
	vec3 world_point = rotate_by_quaternion(view_point, vec4(-orientation.xyz, orientation.w));
	float height = terrain(world_point);
	float coast = smoothstep(0.50, 0.525, height);
	float coastline = 1.0 - smoothstep(0.0, 0.012, abs(height - 0.514));
	vec3 pigment = mix(sea_color, land_color, coast);
	pigment = mix(pigment, ink_color, coastline * 0.25);
	float detail = noise3(world_point * 92.0) - 0.5;
	pigment += detail * 0.045;
	float longitude = atan(world_point.x, world_point.z);
	float latitude = asin(clamp(world_point.y, -1.0, 1.0));
	float grid = pow(abs(cos(longitude * 6.0)), 100.0) + pow(abs(cos(latitude * 6.0)), 100.0);
	pigment = mix(pigment, ink_color, min(grid, 1.0) * 0.065);
	float light = max(0.0, dot(view_point, normalize(vec3(-0.55, 0.65, 1.2))));
	pigment *= 0.76 + 0.27 * light;
	float rim = smoothstep(0.975, 0.998, radial_distance);
	pigment = mix(pigment, ink_color, rim * 0.76);
	// Fixed geographic landmark: the first monster has the same unit vector.
	vec3 landmark = normalize(vec3(-0.37, 0.13, 1.0));
	float landmark_distance = length(world_point - landmark);
	float landmark_ring = 1.0 - smoothstep(0.006, 0.014, abs(landmark_distance - 0.079));
	pigment = mix(pigment, vec3(0.84, 0.66, 0.33), landmark_ring * 0.65);
	COLOR = vec4(pigment, opacity);
}
