@tool
class_name PrototypeSlime
extends Node2D

const SurfaceProjection = preload("res://scripts/surface_projection.gd")
const SlimeBodyCache = preload("res://scripts/slime_body_cache.gd")
const POPULATION_FONT: Font = preload("res://fonts/game_font.tres")
# P(-z < N(0, 1) < z) = 0.75.
const NORMAL_CENTRAL_75_Z: float = 1.15034938

enum Species { SLIME, MUCUS }

@export var species: Species = Species.SLIME:
	set(value):
		species = value
		_cached_body_texture = null
		queue_redraw()
@export var high_value: bool = false
@export_range(0.1, 2.0, 0.1) var peel_seconds: float = 2.0

var peel_progress: float = 0.0
var detached_remaining: float = 0.0
var reward: int = 2
@export_range(1, 200, 1) var population_units: int = 1
@export_range(1.0, 4.0, 0.1) var giant_body_multiplier: float = 2.3
var fused_value_units: int = 0
var on_mucus: bool = false

signal left_screen(slime: PrototypeSlime)
signal landed(slime: PrototypeSlime)

@export_range(8.0, 30.0, 0.5) var body_size: float = 15.0:
	set(value):
		body_size = value
		_cached_body_texture = null
		queue_redraw()
@export_range(0.25, 2.0, 0.05) var presentation_scale: float = 1.0:
	set(value):
		presentation_scale = value
		queue_redraw()
@export var body_color: Color = Color("f1eedb"):
	set(value):
		body_color = value
		_cached_body_texture = null
		queue_redraw()
@export var outline_color: Color = Color("454944"):
	set(value):
		outline_color = value
		_cached_body_texture = null
		queue_redraw()
@export_range(5.0, 40.0, 1.0) var wander_speed: float = 16.0
@export_range(0.3, 0.5, 0.01) var launch_seconds: float = 0.38
@export_range(30.0, 50.0, 1.0) var launch_distance: float = 40.0
@export_range(8.0, 25.0, 1.0) var launch_height: float = 16.0
@export_range(-4.0, 4.0, 0.1) var flight_spin_speed: float = 1.5

var nest_id: int = -1
var capture_progress: float = 0.0
var consumed: bool = false
var surface: PlanetSurface

var _home: Vector2 = Vector2(0.0, -225.0)
var _planet_radius: float = 240.0
var _wander_target: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _phase: float = 0.0
var _capture_hold: float = 0.0
var _attraction_offset: Vector2 = Vector2.ZERO
var _attraction_strength: float = 0.0
var _attraction_hold: float = 0.0
var _wander_wait: float = 0.0
var _has_active_nest: bool = true
var _speed_variation: float = 1.0
var _roaming_deviation: float = 0.76
var _activity_radius: float = 109.44
var _launch_start: Vector2 = Vector2.ZERO
var _launch_end: Vector2 = Vector2.ZERO
var _launch_elapsed: float = 0.38
var _flying: bool = false
var _flight_complete: bool = false
var _flight_velocity: Vector2 = Vector2.ZERO
var _flight_bounds: Rect2 = Rect2()
var _drop_settings: DropSettings
var _fall_elapsed: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _cached_body_texture: Texture2D
var _cached_shadow_texture: Texture2D


func setup(
	owner_id: int, home: Vector2, planet_surface: PlanetSurface, screen_half_angle: float = 0.875
) -> void:
	assert(planet_surface != null, "Slime movement requires its planet surface dependency.")
	nest_id = owner_id
	surface = planet_surface
	_home = surface.project_to_surface(home)
	_planet_radius = surface.radius
	configure_roaming(screen_half_angle)
	_rng.randomize()
	_phase = _rng.randf_range(0.0, TAU)
	_has_active_nest = true
	_flying = false
	_flight_complete = false
	_fall_elapsed = 0.0
	_capture_hold = 0.0
	clear_attraction()
	consumed = false
	capture_progress = 0.0
	on_mucus = false
	detached_remaining = 0.0
	peel_progress = 0.0
	_launch_elapsed = launch_seconds
	position = _random_destination()
	_update_surface_rotation()
	_wander_target = position
	_wander_wait = _rng.randf_range(0.2, 1.5)
	_speed_variation = _rng.randf_range(0.8, 1.2)
	visible = true
	set_process(true)
	queue_redraw()


func configure_roaming(screen_half_angle: float) -> void:
	assert(screen_half_angle > 0.0, "Nest roaming requires a positive viewing range.")
	_roaming_deviation = clampf(screen_half_angle / NORMAL_CENTRAL_75_Z, 0.35, 0.9)
	_activity_radius = get_activity_radius(_planet_radius, screen_half_angle)


# Gaussian wandering has no hard edge. Its standard radius is the shared
# activity-area measure for local fusion, and the spread used for destinations.
static func get_activity_radius(planet_radius: float, screen_half_angle: float) -> float:
	return planet_radius * clampf(screen_half_angle / NORMAL_CENTRAL_75_Z, 0.35, 0.9) * 0.6


func can_fuse() -> bool:
	return (
		population_units == 1
		and not consumed
		and not _flying
		and _launch_elapsed >= launch_seconds
		and capture_progress <= 0.0
		and peel_progress <= 0.0
		and _attraction_hold <= 0.0
	)


func configure_fusion(population: int, value_units: int, candy_reward: int) -> void:
	assert(population > 1 and value_units >= population)
	population_units = population
	fused_value_units = value_units
	reward = candy_reward
	body_size *= giant_body_multiplier
	wander_speed *= 0.55
	queue_redraw()


func get_visual_rect() -> Rect2:
	var extent: Rect2 = Rect2(
		Vector2(-body_size - 5.0, -body_size * 1.9 - 14.0),
		Vector2(body_size * 2.0 + 10.0, body_size * 1.9 + 24.0)
	)
	return (
		get_global_transform_with_canvas()
		* SurfaceProjection.get_visual_compensation(self)
		* Transform2D(0.0, Vector2.ONE * presentation_scale, 0.0, Vector2.ZERO)
		* extent
	)


func configure_species(kind: Species, valuable: bool, candy_reward: int) -> void:
	species = kind
	high_value = valuable
	reward = candy_reward
	body_color = Color("a9bff6") if species == Species.MUCUS else Color("ffa6c6")
	outline_color = Color("243672") if species == Species.MUCUS else Color("6c334e")
	if high_value:
		body_color = Color("f3ca6a")
	if species == Species.MUCUS:
		wander_speed = 10.0
		body_size = 18.0
	else:
		wander_speed = 16.0
		body_size = 15.0
	queue_redraw()


func is_anchored() -> bool:
	return detached_remaining <= 0.0 and not consumed and on_mucus


func pull_off_mucus(delta: float, target: Vector2, duration: float = -1.0) -> bool:
	if not is_anchored():
		return true
	apply_attraction(delta, target, 0.7)
	var seconds: float = peel_seconds if duration <= 0.0 else duration
	peel_progress = minf(1.0, peel_progress + delta / maxf(seconds, 0.05))
	if peel_progress < 1.0:
		return false
	detached_remaining = 6.0
	peel_progress = 0.0
	return true


func can_emit_ground_mucus() -> bool:
	return (
		species == Species.MUCUS
		and not consumed
		and detached_remaining <= 0.0
		and _launch_elapsed >= launch_seconds
	)


func launch(direction: Vector2) -> void:
	_flying = false
	_flight_complete = false
	_fall_elapsed = 0.0
	consumed = false
	capture_progress = 0.0
	_capture_hold = 0.0
	clear_attraction()
	var launch_direction: Vector2 = direction.normalized()
	if launch_direction.is_zero_approx():
		launch_direction = Vector2.from_angle(_rng.randf_range(-PI, PI))
	_launch_start = _home
	var distance: float = _rng.randf_range(launch_distance - 10.0, launch_distance + 10.0)
	_launch_end = _project_to_surface(_launch_start + launch_direction * distance)
	position = _launch_start
	_update_surface_rotation()
	_launch_elapsed = 0.0
	_wander_target = _random_destination()
	_wander_wait = _rng.randf_range(0.2, 0.7)
	visible = true
	set_process(true)
	queue_redraw()


func release_from_nest() -> void:
	if not _has_active_nest:
		return
	_has_active_nest = false
	_wander_target = _random_destination()
	_wander_wait = 0.0


func refresh_surface_bounds() -> void:
	if _flying:
		return
	position = _project_to_surface(position)
	_wander_target = _project_to_surface(_wander_target)
	_launch_end = _project_to_surface(_launch_end)
	_update_surface_rotation()
	queue_redraw()


func restore_to_surface(drop_position: Vector2) -> void:
	position = _project_to_surface(drop_position)
	_update_surface_rotation()
	_flying = false
	_flight_complete = false
	_fall_elapsed = 0.0
	consumed = false
	capture_progress = 0.0
	_capture_hold = 0.0
	clear_attraction()
	_launch_elapsed = launch_seconds
	_wander_target = _random_destination()
	_wander_wait = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func begin_fall(initial_velocity: Vector2, viewport_bounds: Rect2, settings: DropSettings) -> void:
	assert(settings != null and settings.max_step > 0.0)
	_drop_settings = settings
	_flying = true
	_flight_complete = false
	_fall_elapsed = 0.0
	_flight_velocity = initial_velocity + Vector2.DOWN * settings.release_down_speed
	_flight_bounds = viewport_bounds
	consumed = true
	capture_progress = 0.0
	_capture_hold = 0.0
	clear_attraction()
	_launch_elapsed = launch_seconds
	visible = true
	set_process(true)
	queue_redraw()


func update_fall_bounds(bounds: Rect2) -> void:
	_flight_bounds = bounds


func get_capture_point() -> Vector2:
	return position + _get_body_center_offset().rotated(rotation)


func _get_body_center_offset() -> Vector2:
	var height_scale: float = (
		(1.0 + capture_progress * 0.60) * lerpf(1.0, 0.2, capture_progress)
		if population_units > 1
		else 1.0
	)
	return (
		SurfaceProjection.get_visual_compensation(self)
		* Vector2(0.0, -body_size * 0.65 * presentation_scale * height_scale)
	)


func apply_attraction(delta: float, target: Vector2, strength: float) -> void:
	if consumed:
		return
	_capture_hold = 0.12
	_attraction_hold = 0.12
	var pull_strength: float = clampf(strength, 0.0, 1.0)
	var direction: Vector2 = (target - get_capture_point()).normalized().rotated(-rotation)
	var smoothing: float = 1.0 - exp(-delta * 18.0)
	_attraction_offset = _attraction_offset.lerp(direction * pull_strength * 7.0, smoothing)
	_attraction_strength = lerpf(_attraction_strength, pull_strength, smoothing)
	queue_redraw()


func clear_attraction() -> void:
	_attraction_offset = Vector2.ZERO
	_attraction_strength = 0.0
	_attraction_hold = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _flying:
		if not _flight_complete:
			_advance_fall(delta)
		return
	if consumed:
		return
	_elapsed += delta
	detached_remaining = maxf(0.0, detached_remaining - delta)
	if _capture_hold <= 0.0:
		peel_progress = maxf(0.0, peel_progress - delta * 2.0)
	_capture_hold = maxf(0.0, _capture_hold - delta)
	_attraction_hold = maxf(0.0, _attraction_hold - delta)
	if _attraction_hold <= 0.0:
		var recovery: float = 1.0 - exp(-delta * 12.0)
		_attraction_offset = _attraction_offset.lerp(Vector2.ZERO, recovery)
		_attraction_strength = lerpf(_attraction_strength, 0.0, recovery)
	if _capture_hold <= 0.0:
		if _launch_elapsed < launch_seconds:
			_advance_launch(delta)
		elif _has_active_nest:
			_advance_nest_roaming(delta)
		elif position.distance_to(_wander_target) <= 1.0:
			_wander_wait -= delta
			if _wander_wait <= 0.0:
				_wander_target = _random_destination()
				_wander_wait = _rng.randf_range(1.0, 2.7)
		else:
			_move_on_surface(_wander_target, wander_speed * _speed_variation * delta)
	_update_surface_rotation()
	queue_redraw()


func apply_capture(delta: float, capture_seconds: float, target: Vector2) -> bool:
	if consumed:
		return false
	clear_attraction()
	_launch_elapsed = launch_seconds
	_capture_hold = 0.12
	var body_center: Vector2 = get_capture_point()
	capture_progress = minf(1.0, capture_progress + delta / maxf(capture_seconds, 0.05))
	body_center = body_center.move_toward(target, delta * (24.0 + capture_progress * 46.0))
	position = body_center - _get_body_center_offset().rotated(rotation)
	_update_surface_rotation()
	queue_redraw()
	if capture_progress >= 1.0:
		consumed = true
		return true
	return false


func release_capture(delta: float) -> void:
	_capture_hold = 0.0
	peel_progress = 0.0
	capture_progress = maxf(0.0, capture_progress - delta * 0.75)
	queue_redraw()


func _advance_launch(delta: float) -> void:
	_launch_elapsed = minf(launch_seconds, _launch_elapsed + delta)
	var progress: float = _launch_elapsed / launch_seconds
	var travel_progress: float = 1.0 - (1.0 - progress) * (1.0 - progress)
	position = _project_to_surface(_launch_start.lerp(_launch_end, travel_progress))


func _advance_fall(delta: float) -> void:
	var remaining: float = delta
	while remaining > 0.0:
		var step: float = minf(remaining, _drop_settings.max_step)
		remaining -= step
		var previous: Vector2 = position
		var distance_squared: float = maxf(
			position.length_squared(), _planet_radius * _planet_radius
		)
		var planet_acceleration: float = (
			_drop_settings.planet_gravity * _planet_radius * _planet_radius / distance_squared
		)
		var acceleration: Vector2 = (
			Vector2.DOWN * _drop_settings.down_gravity - position.normalized() * planet_acceleration
		)
		_flight_velocity += acceleration * step
		position += _flight_velocity * step
		rotation += flight_spin_speed * step
		_fall_elapsed += step
		if _fall_elapsed >= _drop_settings.settle_delay:
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(
				Vector2.ZERO, previous, position
			)
			if nearest.length_squared() <= _planet_radius * _planet_radius:
				position = _surface_contact(previous, position)
				_finish_fall(true)
				return
		if not _flight_bounds.grow(body_size * 2.0).has_point(position):
			_finish_fall(false)
			return
	queue_redraw()


func _surface_contact(previous: Vector2, current: Vector2) -> Vector2:
	if previous.length_squared() <= _planet_radius * _planet_radius:
		return _project_to_surface(current)
	var segment: Vector2 = current - previous
	var quadratic_a: float = segment.length_squared()
	var quadratic_b: float = 2.0 * previous.dot(segment)
	var quadratic_c: float = previous.length_squared() - _planet_radius * _planet_radius
	var discriminant: float = quadratic_b * quadratic_b - 4.0 * quadratic_a * quadratic_c
	var contact_fraction: float = (
		(-quadratic_b - sqrt(maxf(0.0, discriminant))) / (2.0 * quadratic_a)
	)
	return previous + segment * clampf(contact_fraction, 0.0, 1.0)


func _finish_fall(on_surface: bool) -> void:
	_flight_complete = true
	_flight_velocity = Vector2.ZERO
	set_process(false)
	queue_redraw()
	if on_surface:
		landed.emit(self)
	else:
		left_screen.emit(self)


func _update_surface_rotation() -> void:
	# A two-dimensional surface has no radial "up" at its center. Keep actors
	# upright in the view while their ground positions still rotate with the planet.
	var local_right: Vector2 = get_global_transform_with_canvas().affine_inverse().basis_xform(
		Vector2.RIGHT
	)
	rotation += local_right.angle()


func _move_on_surface(target: Vector2, travel_distance: float) -> void:
	var candidate: Vector2 = position.move_toward(target, travel_distance)
	var inner: float = surface.get_activity_radius_bounds(position.angle()).x
	var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(
		Vector2.ZERO, position, candidate
	)
	if nearest.length_squared() < inner * inner - 0.0001:
		var difference: float = angle_difference(position.angle(), target.angle())
		var angular_step: float = minf(
			absf(difference), travel_distance / maxf(position.length(), inner)
		)
		var direction: float = -1.0 if difference < 0.0 else 1.0
		candidate = position.rotated(angular_step * direction)
	position = _project_to_surface(candidate)


func _random_destination() -> Vector2:
	if not _has_active_nest:
		var angle: float = _rng.randf_range(-PI, PI)
		return Vector2.from_angle(angle) * _random_radius(angle)
	var destination: Vector2 = _home
	for attempt: int in range(8):
		destination = _home + Vector2(_rng.randfn(), _rng.randfn()) * _activity_radius
		if surface.contains_surface_point(destination, surface.activity_edge_inset):
			return destination
	return _project_to_surface(destination)


func _advance_nest_roaming(delta: float) -> void:
	if delta <= 0.0 or wander_speed <= 0.0:
		return
	if position.distance_squared_to(_wander_target) <= 1.0:
		_wander_wait -= delta
		if _wander_wait <= 0.0:
			_wander_target = _random_destination()
			_wander_wait = _rng.randf_range(0.3, 1.4)
		return
	_move_on_surface(_wander_target, wander_speed * _speed_variation * delta)


func _random_radius(angle: float) -> float:
	var bounds: Vector2 = surface.get_activity_radius_bounds(angle)
	return sqrt(lerpf(bounds.x * bounds.x, bounds.y * bounds.y, _rng.randf()))


func _project_to_surface(point: Vector2) -> Vector2:
	return surface.project_to_surface(point)


func _draw() -> void:
	var compensation: Transform2D = SurfaceProjection.get_visual_compensation(self)
	var bounce: float = sin(_elapsed * 4.5 + _phase)
	var squash: float = bounce * 0.045
	var launch_bob: float = 0.0
	if _launch_elapsed < launch_seconds:
		var progress: float = _launch_elapsed / launch_seconds
		launch_bob = -sin(progress * PI) * launch_height
		squash += sin(progress * TAU) * 0.14
	var capture_scale: float = lerpf(1.0, 0.2, capture_progress)
	var body_width: float = (
		body_size * (1.0 + squash - peel_progress * 0.18 - capture_progress * 0.37) * capture_scale
	)
	var body_height: float = (
		body_size * (1.0 - squash + peel_progress * 0.40 + capture_progress * 0.60) * capture_scale
	)
	var bob: float = -maxf(0.0, bounce) * 2.0 + launch_bob
	var cached_body: bool = _can_use_cached_body()
	if cached_body and _cached_body_texture == null:
		_cached_body_texture = SlimeBodyCache.get_body_texture(
			body_size, species == Species.MUCUS, body_color, outline_color
		)
		_cached_shadow_texture = SlimeBodyCache.get_shadow_texture(
			body_size, species == Species.MUCUS, body_color, outline_color
		)
	if not _flying:
		var shadow_color: Color = Color(0.15, 0.18, 0.14, 0.12 * (1.0 - capture_progress * 0.6))
		draw_set_transform_matrix(
			(
				compensation
				* Transform2D(
					0.0,
					Vector2(1.0, 0.28) * presentation_scale,
					0.0,
					(Vector2(0.0, 3.0) + _attraction_offset * 0.15) * presentation_scale
				)
			)
		)
		if cached_body:
			draw_texture_rect(
				_cached_shadow_texture,
				SlimeBodyCache.get_shadow_rect(body_size),
				false,
				shadow_color
			)
		else:
			var shadow_scale: float = capture_scale if population_units > 1 else 1.0
			draw_circle(Vector2.ZERO, body_size * 0.85 * shadow_scale, shadow_color)
	var body_transform: Transform2D = (
		compensation
		* Transform2D(
			_attraction_offset.x * 0.012,
			(
				Vector2(1.0 - _attraction_strength * 0.05, 1.0 + _attraction_strength * 0.12)
				* presentation_scale
			),
			0.0,
			(Vector2(0.0, bob) + _attraction_offset) * presentation_scale
		)
	)
	draw_set_transform_matrix(body_transform)
	if cached_body:
		_draw_cached_body(body_transform, body_width, body_height)
		_draw_population_marker(compensation)
		return
	var body_points: PackedVector2Array = PackedVector2Array(
		[
			Vector2(-0.95 * body_width, -0.08 * body_height),
			Vector2(-1.00 * body_width, -0.44 * body_height),
			Vector2(-0.77 * body_width, -0.98 * body_height),
			Vector2(-0.52 * body_width, -1.27 * body_height),
			Vector2(-0.16 * body_width, -1.39 * body_height),
			Vector2(0.15 * body_width, -1.48 * body_height),
			Vector2(0.39 * body_width, -1.32 * body_height),
			Vector2(0.74 * body_width, -1.08 * body_height),
			Vector2(0.95 * body_width, -0.57 * body_height),
			Vector2(1.00 * body_width, -0.20 * body_height),
			Vector2(0.77 * body_width, 0.05 * body_height),
			Vector2(0.41 * body_width, 0.12 * body_height),
			Vector2(0.08 * body_width, 0.05 * body_height),
			Vector2(-0.25 * body_width, 0.11 * body_height),
			Vector2(-0.62 * body_width, 0.08 * body_height),
		]
	)
	draw_colored_polygon(body_points, body_color)
	body_points.append(body_points[0])
	draw_polyline(body_points, outline_color, 1.9, true)
	if species == Species.MUCUS:
		for spot: Vector2 in [Vector2(-0.6, -0.4), Vector2(0.6, -0.3), Vector2(0.2, -1.2)]:
			draw_circle(
				spot * Vector2(body_width, body_height),
				body_size * capture_scale * 0.13,
				Color("7293d9")
			)
	if high_value:
		_draw_value_marker(body_height)
	if peel_progress > 0.0:
		draw_arc(
			Vector2(0.0, -body_size * 0.65),
			body_size * 1.35,
			-PI / 2.0,
			-PI / 2.0 + TAU * peel_progress,
			24,
			Color("c9a5ea"),
			2.8,
			true
		)
	draw_circle(
		Vector2(-body_width * 0.33, -body_height * 0.86),
		body_size * capture_scale * 0.19,
		Color("fbfcf5")
	)
	draw_circle(
		Vector2(body_width * 0.33, -body_height * 0.83),
		body_size * capture_scale * 0.19,
		Color("fbfcf5")
	)
	draw_circle(
		Vector2(-body_width * 0.30, -body_height * 0.83),
		body_size * capture_scale * 0.085,
		outline_color
	)
	draw_circle(
		Vector2(body_width * 0.30, -body_height * 0.80),
		body_size * capture_scale * 0.085,
		outline_color
	)
	draw_arc(
		Vector2(0.0, -body_height * 0.55),
		body_size * capture_scale * 0.13,
		0.12,
		PI - 0.12,
		8,
		outline_color,
		1.5,
		true
	)
	draw_line(
		Vector2(-body_width * 0.53, -body_height * 1.11),
		Vector2(-body_width * 0.30, -body_height * 1.25),
		Color(1.0, 1.0, 0.97, 0.8),
		2.3,
		true
	)
	if capture_progress > 0.02:
		var ring_scale: float = capture_scale if population_units > 1 else 1.0
		var ring_height: float = body_height if population_units > 1 else body_size
		draw_arc(
			Vector2(0.0, -ring_height * 0.65),
			body_size * 1.28 * ring_scale,
			-PI / 2.0,
			-PI / 2.0 + TAU * capture_progress,
			32,
			Color("809c69"),
			2.4,
			true
		)
	_draw_population_marker(compensation)


func _draw_population_marker(compensation: Transform2D) -> void:
	if population_units <= 1:
		return
	draw_set_transform_matrix(
		compensation * Transform2D(0.0, Vector2.ONE * presentation_scale * 0.25, 0.0, Vector2.ZERO)
	)
	var caption: String = "×%d" % population_units
	var font_size: int = 36
	var width: float = (
		POPULATION_FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	)
	var height_scale: float = (1.0 + capture_progress * 0.60) * lerpf(1.0, 0.2, capture_progress)
	var origin: Vector2 = Vector2(-width * 0.5, (-body_size * 1.65 * height_scale - 5.0) * 4.0)
	draw_string_outline(
		POPULATION_FONT, origin, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, outline_color
	)
	draw_string(
		POPULATION_FONT, origin, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("fff6df")
	)


func _can_use_cached_body() -> bool:
	return (
		not _flying
		and _launch_elapsed >= launch_seconds
		and capture_progress <= 0.0
		and peel_progress <= 0.0
		and _attraction_strength <= 0.001
		and _attraction_offset.length_squared() <= 0.001
	)


func _draw_cached_body(body_transform: Transform2D, width: float, height: float) -> void:
	# Keep bob and squash continuous. Active handling retains the original vector
	# geometry so the eyes, progress rings and stretched body stay exact.
	draw_set_transform_matrix(
		body_transform * Transform2D(0.0, Vector2(width, height) / body_size, 0.0, Vector2.ZERO)
	)
	draw_texture_rect(_cached_body_texture, SlimeBodyCache.get_body_rect(body_size), false)
	if high_value:
		draw_set_transform_matrix(body_transform)
		_draw_value_marker(height)


func _draw_value_marker(body_height: float) -> void:
	var marker: Vector2 = Vector2(0.0, -body_height * 1.9)
	var diamond: PackedVector2Array = PackedVector2Array(
		[
			marker + Vector2(0.0, -6.0),
			marker + Vector2(4.0, 0.0),
			marker + Vector2(0.0, 6.0),
			marker + Vector2(-4.0, 0.0)
		]
	)
	draw_colored_polygon(diamond, Color("fff4b7"))
	diamond.append(diamond[0])
	draw_polyline(diamond, Color("ad7b35"), 1.3, true)
