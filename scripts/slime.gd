@tool
class_name PrototypeSlime
extends Node2D

signal left_screen(slime: PrototypeSlime)
signal landed(slime: PrototypeSlime)

@export_range(8.0, 30.0, 0.5) var body_size: float = 15.0:
	set(value):
		body_size = value
		queue_redraw()
@export var body_color: Color = Color("f1eedb")
@export var outline_color: Color = Color("454944")
@export_range(5.0, 40.0, 1.0) var wander_speed: float = 16.0
@export_range(0.1, 0.8, 0.01) var local_angle_range: float = 0.42
@export_range(20.0, 100.0, 1.0) var surface_inner_offset: float = 65.0
@export_range(10.0, 70.0, 1.0) var surface_outer_offset: float = 35.0
@export_range(0.3, 0.5, 0.01) var launch_seconds: float = 0.38
@export_range(30.0, 50.0, 1.0) var launch_distance: float = 40.0
@export_range(8.0, 25.0, 1.0) var launch_height: float = 16.0
@export_range(-4.0, 4.0, 0.1) var flight_spin_speed: float = 1.5

var nest_id: int = -1
var capture_progress: float = 0.0
var consumed: bool = false

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


func setup(owner_id: int, home: Vector2, planet_radius: float) -> void:
	nest_id = owner_id
	_home = home
	_planet_radius = planet_radius
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
	_launch_elapsed = launch_seconds
	position = _random_destination()
	_update_surface_rotation()
	_wander_target = position
	_wander_wait = _rng.randf_range(0.2, 1.5)
	_speed_variation = _rng.randf_range(0.8, 1.2)
	visible = true
	set_process(true)
	queue_redraw()


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
		launch_direction = _home.normalized()
	_launch_start = _project_to_surface(_home)
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
	var angular_distance: float = _rng.randf_range(1.2, PI)
	if _rng.randf() < 0.5:
		angular_distance = -angular_distance
	_wander_target = Vector2.from_angle(_home.angle() + angular_distance) * _random_radius()
	_wander_wait = 0.0


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
	return position + Vector2(0.0, -body_size * 0.65).rotated(rotation)


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
	_capture_hold = maxf(0.0, _capture_hold - delta)
	_attraction_hold = maxf(0.0, _attraction_hold - delta)
	if _attraction_hold <= 0.0:
		var recovery: float = 1.0 - exp(-delta * 12.0)
		_attraction_offset = _attraction_offset.lerp(Vector2.ZERO, recovery)
		_attraction_strength = lerpf(_attraction_strength, 0.0, recovery)
	if _capture_hold <= 0.0:
		if _launch_elapsed < launch_seconds:
			_advance_launch(delta)
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
	capture_progress = minf(1.0, capture_progress + delta / maxf(capture_seconds, 0.05))
	var body_center: Vector2 = get_capture_point().move_toward(
		target, delta * (24.0 + capture_progress * 46.0)
	)
	position = body_center - body_center.normalized() * body_size * 0.65
	_update_surface_rotation()
	queue_redraw()
	if capture_progress >= 1.0:
		consumed = true
		return true
	return false


func release_capture(delta: float) -> void:
	_capture_hold = 0.0
	capture_progress = maxf(0.0, capture_progress - delta * 0.75)
	queue_redraw()


func _advance_launch(delta: float) -> void:
	_launch_elapsed = minf(launch_seconds, _launch_elapsed + delta)
	var progress: float = _launch_elapsed / launch_seconds
	var travel_progress: float = 1.0 - (1.0 - progress) * (1.0 - progress)
	var angle: float = lerp_angle(_launch_start.angle(), _launch_end.angle(), travel_progress)
	var radial_distance: float = lerpf(
		_launch_start.length(), _launch_end.length(), travel_progress
	)
	position = Vector2.from_angle(angle) * radial_distance


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
		var angle: float = current.angle() if not current.is_zero_approx() else _home.angle()
		return Vector2.from_angle(angle) * _planet_radius
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
	rotation = position.angle() + PI / 2.0


func _move_on_surface(target: Vector2, travel_distance: float) -> void:
	var radial_distance: float = position.length()
	var angular_step: float = travel_distance / maxf(radial_distance, 1.0)
	var angle: float = (
		position.angle()
		+ clampf(angle_difference(position.angle(), target.angle()), -angular_step, angular_step)
	)
	radial_distance = move_toward(radial_distance, target.length(), travel_distance * 0.65)
	position = _project_to_surface(Vector2.from_angle(angle) * radial_distance)


func _random_destination() -> Vector2:
	var angle: float = _rng.randf_range(-PI, PI)
	if _has_active_nest:
		angle = _home.angle() + _rng.randf_range(-local_angle_range, local_angle_range)
		if _rng.randf() < 0.3:
			angle = lerp_angle(angle, _home.angle(), 0.65)
	return Vector2.from_angle(angle) * _random_radius()


func _random_radius() -> float:
	return _rng.randf_range(
		_planet_radius - surface_inner_offset, _planet_radius + surface_outer_offset
	)


func _project_to_surface(point: Vector2) -> Vector2:
	var angle: float = point.angle() if not point.is_zero_approx() else _home.angle()
	var radial_distance: float = clampf(
		point.length(), _planet_radius - surface_inner_offset, _planet_radius + surface_outer_offset
	)
	return Vector2.from_angle(angle) * radial_distance


func _draw() -> void:
	var bounce: float = sin(_elapsed * 4.5 + _phase)
	var squash: float = bounce * 0.045
	var launch_bob: float = 0.0
	if _launch_elapsed < launch_seconds:
		var progress: float = _launch_elapsed / launch_seconds
		launch_bob = -sin(progress * PI) * launch_height
		squash += sin(progress * TAU) * 0.14
	var body_width: float = body_size * (1.0 + squash - capture_progress * 0.37)
	var body_height: float = body_size * (1.0 - squash + capture_progress * 0.60)
	var bob: float = -maxf(0.0, bounce) * 2.0 + launch_bob
	if not _flying:
		var shadow_color: Color = Color(0.15, 0.18, 0.14, 0.12 * (1.0 - capture_progress * 0.6))
		draw_set_transform(Vector2(0.0, 3.0) + _attraction_offset * 0.15, 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, body_size * 0.85, shadow_color)
	draw_set_transform(
		Vector2(0.0, bob) + _attraction_offset,
		_attraction_offset.x * 0.012,
		Vector2(1.0 - _attraction_strength * 0.05, 1.0 + _attraction_strength * 0.12)
	)
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
	draw_circle(Vector2(-body_width * 0.33, -body_height * 0.86), body_size * 0.19, Color("fbfcf5"))
	draw_circle(Vector2(body_width * 0.33, -body_height * 0.83), body_size * 0.19, Color("fbfcf5"))
	draw_circle(Vector2(-body_width * 0.30, -body_height * 0.83), body_size * 0.085, outline_color)
	draw_circle(Vector2(body_width * 0.30, -body_height * 0.80), body_size * 0.085, outline_color)
	draw_arc(
		Vector2(0.0, -body_height * 0.55),
		body_size * 0.13,
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
		draw_arc(
			Vector2(0.0, -body_size * 0.65),
			body_size * 1.28,
			-PI / 2.0,
			-PI / 2.0 + TAU * capture_progress,
			32,
			Color("809c69"),
			2.4,
			true
		)
