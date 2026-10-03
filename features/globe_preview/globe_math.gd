extends RefCounted

## Unit-sphere coordinates use +Y up and +Z toward the viewer.
## Only the camera orientation changes; geographic positions remain fixed.
## camera_distance > 1 enables perspective from (0, 0, distance).
## In that mode radius is the silhouette radius in pixels. An omitted focal
## length is derived from radius; zero camera distance keeps legacy orthography.


static func project_position(
	world_position: Vector3,
	orientation: Quaternion,
	center: Vector2,
	radius: float,
	camera_distance: float = 0.0,
	focal_length: float = 0.0
) -> Vector2:
	var view_position: Vector3 = orientation * world_position
	if camera_distance > 1.0:
		var focal: float = _resolved_focal_length(radius, camera_distance, focal_length)
		return (
			center
			+ (
				Vector2(view_position.x, -view_position.y)
				* focal
				/ (camera_distance - view_position.z)
			)
		)
	return center + Vector2(view_position.x, -view_position.y) * radius


static func unproject_position(
	screen_position: Vector2,
	orientation: Quaternion,
	center: Vector2,
	radius: float,
	camera_distance: float = 0.0,
	focal_length: float = 0.0
) -> Vector3:
	if camera_distance > 1.0:
		var focal: float = _resolved_focal_length(radius, camera_distance, focal_length)
		var visible_position: Vector3 = _perspective_view_point(
			screen_position - center, camera_distance, focal
		)
		return orientation.inverse() * visible_position
	var disc_position: Vector2 = (screen_position - center) / radius
	if disc_position.length_squared() > 1.0:
		return Vector3.ZERO
	var view_position: Vector3 = Vector3(
		disc_position.x, -disc_position.y, sqrt(maxf(0.0, 1.0 - disc_position.length_squared()))
	)
	return orientation.inverse() * view_position


static func arcball_vector(
	screen_position: Vector2,
	center: Vector2,
	radius: float,
	camera_distance: float = 0.0,
	focal_length: float = 0.0
) -> Vector3:
	if camera_distance > 1.0:
		return perspective_arcball_vector(
			screen_position, center, radius, camera_distance, focal_length
		)
	var disc_position: Vector2 = (screen_position - center) / radius
	if disc_position.length_squared() > 1.0:
		disc_position = disc_position.normalized()
		return Vector3(disc_position.x, -disc_position.y, 0.0)
	return Vector3(
		disc_position.x, -disc_position.y, sqrt(maxf(0.0, 1.0 - disc_position.length_squared()))
	)


static func perspective_arcball_vector(
	screen_position: Vector2,
	center: Vector2,
	radius: float,
	camera_distance: float,
	focal_length: float = 0.0
) -> Vector3:
	if camera_distance <= 1.0:
		return arcball_vector(screen_position, center, radius)
	var focal: float = _resolved_focal_length(radius, camera_distance, focal_length)
	var silhouette_radius: float = focal / sqrt(camera_distance * camera_distance - 1.0)
	var relative_position: Vector2 = screen_position - center
	if relative_position.length_squared() > silhouette_radius * silhouette_radius:
		relative_position = relative_position.normalized() * silhouette_radius
	return _perspective_view_point(relative_position, camera_distance, focal)


static func _resolved_focal_length(
	radius: float, camera_distance: float, focal_length: float
) -> float:
	return (
		focal_length
		if focal_length > 0.0
		else radius * sqrt(camera_distance * camera_distance - 1.0)
	)


static func _perspective_view_point(
	relative_position: Vector2, camera_distance: float, focal_length: float
) -> Vector3:
	var silhouette_radius: float = focal_length / sqrt(camera_distance * camera_distance - 1.0)
	if relative_position.length_squared() > silhouette_radius * silhouette_radius * 1.000001:
		return Vector3.ZERO
	var camera_position: Vector3 = Vector3(0.0, 0.0, camera_distance)
	var ray_direction: Vector3 = (
		Vector3(relative_position.x, -relative_position.y, -focal_length).normalized()
	)
	var camera_dot_ray: float = camera_position.dot(ray_direction)
	var discriminant: float = (
		camera_dot_ray * camera_dot_ray - (camera_distance * camera_distance - 1.0)
	)
	var nearest_distance: float = -camera_dot_ray - sqrt(maxf(0.0, discriminant))
	return (camera_position + nearest_distance * ray_direction).normalized()


static func drag_orientation(
	start_vector: Vector3, current_vector: Vector3, start_orientation: Quaternion
) -> Quaternion:
	return (Quaternion(start_vector, current_vector) * start_orientation).normalized()


static func geographic_position(latitude: float, longitude: float) -> Vector3:
	return Vector3(cos(latitude) * sin(longitude), sin(latitude), cos(latitude) * cos(longitude))


static func edge_opacity(view_depth: float) -> float:
	return smoothstep(0.015, 0.20, view_depth)
