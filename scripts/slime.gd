@tool
class_name PrototypeSlime
extends Node2D

const SurfaceProjection = preload("res://scripts/surface_projection.gd")
const SlimeArt = preload("res://scripts/slime_art.gd")
# P(-z < N(0, 1) < z) = 0.75.
const NORMAL_CENTRAL_75_Z: float = 1.15034938

@export var slime_art: SlimeArt
@export var ground_shadow: Node2D
@export var mucus_ground_shadow: Node2D
@export_range(0.1, 1.0, 0.01) var slime_art_scale: float = 0.36
@export var art_settings: ArtPresentationSettings = preload("res://resources/art_presentation.tres")

enum Species { SLIME, MUCUS, DRILL }

@export var species: Species = Species.SLIME:
	set(value):
		species = value
		queue_redraw()
@export var high_value: bool = false
@export_range(0.1, 2.0, 0.1) var peel_seconds: float = 2.0

var peel_progress: float = 0.0
var detached_remaining: float = 0.0
var reward: int = 1
@export_range(1, 200, 1) var population_units: int = 1
@export_range(1.0, 4.0, 0.1) var giant_body_multiplier: float = 2.3
@export_range(1.0, 10.0, 0.5) var giant_capture_multiplier: float = 5.0
var fused_value_units: int = 0
var on_mucus: bool = false

signal left_screen(slime: PrototypeSlime)
signal landed(slime: PrototypeSlime)
signal launch_landed(slime: PrototypeSlime)

@export_range(8.0, 30.0, 0.5) var body_size: float = 15.0:
	set(value):
		body_size = value
		queue_redraw()
@export_range(0.25, 2.0, 0.05) var presentation_scale: float = 1.0:
	set(value):
		presentation_scale = value
		queue_redraw()
@export var body_color: Color = Color("f1eedb"):
	set(value):
		body_color = value
		queue_redraw()
@export var outline_color: Color = Color("454944"):
	set(value):
		outline_color = value
		queue_redraw()
@export_range(5.0, 40.0, 1.0) var wander_speed: float = 16.0
@export_range(0.3, 0.5, 0.01) var launch_seconds: float = 0.38
@export_range(30.0, 50.0, 1.0) var launch_distance: float = 40.0
@export_range(8.0, 25.0, 1.0) var launch_height: float = 16.0
@export_range(-4.0, 4.0, 0.1) var flight_spin_speed: float = 1.5

var nest_id: int = -1
var capture_progress: float = 0.0
var consumed: bool = false
var simulation_speed: float = 1.0
var surface: PlanetSurface

var _home: Vector2 = Vector2(0.0, -225.0)
var _planet_radius: float = 240.0
var _wander_target: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _phase: float = 0.0
var _capture_hold: float = 0.0
var _suction_active: bool = false
var _detached_for_capture: bool = false
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


func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint():
		return
	if slime_art != null:
		slime_art.configure_species(species, high_value)
		_sync_slime_art()


func _get_art_transform() -> Transform2D:
	var normal_size: float = 18.0 if species == Species.MUCUS else 15.0
	var multiplier: float = slime_art_scale * body_size / normal_size * get_presentation_scale()
	var shrink: float = lerpf(1.0, 0.2, capture_progress)
	var suction_stretch: float = capture_progress if population_units == 1 else 0.0
	var stretch: Vector2 = Vector2(
		1.0 - peel_progress * 0.18 - suction_stretch * 0.37 - _attraction_strength * 0.05,
		1.0 + peel_progress * 0.40 + suction_stretch * 0.60 + _attraction_strength * 0.12
	)
	var launch_bob: float = 0.0
	if species == Species.MUCUS and _launch_elapsed < launch_seconds:
		launch_bob = -sin(_launch_elapsed / launch_seconds * PI) * launch_height
	var origin: Vector2 = _attraction_offset * get_presentation_scale()
	origin.y += get_presentation_sink() + launch_bob
	return (
		SurfaceProjection.get_visual_compensation(self)
		* Transform2D(_attraction_offset.x * 0.012, stretch * multiplier * shrink, 0.0, origin)
	)


func _sync_slime_art() -> void:
	if slime_art != null:
		slime_art.transform = _get_art_transform()
	_sync_ground_shadow()


func _sync_ground_shadow() -> void:
	if ground_shadow != null and species != Species.SLIME:
		ground_shadow.hide()
	if mucus_ground_shadow != null and species != Species.MUCUS:
		mucus_ground_shadow.hide()
	var active_shadow: Node2D = mucus_ground_shadow if species == Species.MUCUS else ground_shadow
	if active_shadow == null:
		return
	active_shadow.visible = (
		species != Species.DRILL
		and not _flying
		and not _suction_active
		and (population_units > 1 or capture_progress <= 0.0)
	)
	if not active_shadow.visible:
		return
	var lift: float = sin(clampf(_launch_elapsed / launch_seconds, 0.0, 1.0) * PI)
	var normal_size: float = 18.0 if species == Species.MUCUS else 15.0
	var multiplier: float = slime_art_scale * body_size / normal_size * get_presentation_scale()
	if population_units > 1:
		multiplier *= lerpf(1.0, 0.2, capture_progress)
	active_shadow.transform = (
		SurfaceProjection.get_visual_compensation(self)
		* Transform2D(
			0.0,
			Vector2.ONE * multiplier * lerpf(1.0, 0.8, lift),
			0.0,
			Vector2(0.0, get_presentation_sink())
		)
	)
	active_shadow.modulate.a = lerpf(1.0, 0.65, maxf(lift, peel_progress))


func get_source_texture() -> Texture2D:
	return slime_art.get_source_texture()


func get_presentation_scale() -> float:
	return presentation_scale * art_settings.get_monster_scale(species)


func get_presentation_sink() -> float:
	return art_settings.get_monster_sink(species)


func refresh_presentation() -> void:
	_sync_slime_art()
	queue_redraw()


func setup(
	owner_id: int, home: Vector2, planet_surface: PlanetSurface, screen_half_angle: float = 0.875
) -> void:
	assert(planet_surface != null, "Slime movement requires its planet surface dependency.")
	nest_id = owner_id
	_suction_active = false
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
	_detached_for_capture = false
	clear_attraction()
	consumed = false
	capture_progress = 0.0
	on_mucus = false
	detached_remaining = 0.0
	peel_progress = 0.0
	_launch_elapsed = launch_seconds
	if slime_art != null:
		slime_art.restore_idle()
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


func can_capture() -> bool:
	return not consumed


func can_net_capture() -> bool:
	return not consumed and population_units == 1


func configure_fusion(population: int, value_units: int, candy_reward: int) -> void:
	assert(population > 1 and value_units >= population)
	population_units = population
	fused_value_units = value_units
	reward = candy_reward
	body_size *= giant_body_multiplier
	wander_speed *= 0.55
	queue_redraw()


func get_visual_rect() -> Rect2:
	if slime_art != null:
		return (
			get_global_transform_with_canvas() * _get_art_transform() * slime_art.get_art_bounds()
		)

	var extent: Rect2 = Rect2(
		Vector2(-body_size - 5.0, -body_size * 1.9 - 14.0),
		Vector2(body_size * 2.0 + 10.0, body_size * 1.9 + 24.0)
	)
	return (
		get_global_transform_with_canvas()
		* SurfaceProjection.get_visual_compensation(self)
		* Transform2D(
			0.0, Vector2.ONE * get_presentation_scale(), 0.0, Vector2(0.0, get_presentation_sink())
		)
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
	if slime_art != null:
		slime_art.configure_species(species, high_value)
		_sync_slime_art()
	queue_redraw()


func is_anchored() -> bool:
	return detached_remaining <= 0.0 and not _detached_for_capture and not consumed and on_mucus


func pull_off_mucus(delta: float, target: Vector2, duration: float = -1.0) -> bool:
	if not is_anchored():
		peel_progress = 0.0
		return true
	apply_attraction(delta, target, 0.7)
	var seconds: float = peel_seconds if duration <= 0.0 else duration
	peel_progress = minf(1.0, peel_progress + delta / maxf(seconds, 0.05))
	if peel_progress < 1.0:
		return false
	detached_remaining = 6.0
	_detached_for_capture = true
	peel_progress = 0.0
	return true


func can_emit_ground_mucus() -> bool:
	return (
		species == Species.MUCUS
		and not consumed
		and detached_remaining <= 0.0
		and not _detached_for_capture
		and _launch_elapsed >= launch_seconds
	)


func launch(direction: Vector2) -> void:
	_suction_active = false
	_detached_for_capture = false
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
	if slime_art != null:
		slime_art.play_launch(launch_seconds)
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
	_suction_active = false
	_detached_for_capture = false
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
	_suction_active = false
	_detached_for_capture = false
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


func get_capture_distance_squared(target: Vector2) -> float:
	if population_units <= 1 or slime_art == null:
		return get_capture_point().distance_squared_to(target)
	var body_transform: Transform2D = transform * _get_art_transform()
	var bounds: Rect2 = slime_art.get_art_bounds()
	var local_target: Vector2 = body_transform.affine_inverse() * target
	var closest: Vector2 = local_target.clamp(bounds.position, bounds.end)
	return target.distance_squared_to(body_transform * closest)


func _get_body_center_offset() -> Vector2:
	if slime_art != null:
		return _get_art_transform() * slime_art.get_art_bounds().get_center()
	var height_scale: float = lerpf(1.0, 0.2, capture_progress) if population_units > 1 else 1.0
	return (
		SurfaceProjection.get_visual_compensation(self)
		* Vector2(
			0.0,
			-body_size * 0.65 * get_presentation_scale() * height_scale + get_presentation_sink()
		)
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


func set_simulation_speed(value: float) -> void:
	simulation_speed = value
	if slime_art != null:
		slime_art.set_simulation_speed(value)


func _process(delta: float) -> void:
	delta *= simulation_speed
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
	if population_units > 1 and _suction_active:
		_update_surface_rotation()
		queue_redraw()
		return
	if _capture_hold <= 0.0:
		peel_progress = maxf(0.0, peel_progress - delta * 2.0)
	_capture_hold = maxf(0.0, _capture_hold - delta)
	_attraction_hold = maxf(0.0, _attraction_hold - delta)
	if _attraction_hold <= 0.0:
		var recovery: float = 1.0 - exp(-delta * 12.0)
		_attraction_offset = _attraction_offset.lerp(Vector2.ZERO, recovery)
		_attraction_strength = lerpf(_attraction_strength, 0.0, recovery)
	if _capture_hold <= 0.0:
		_detached_for_capture = false
		_set_suction_expression(false)
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


func get_capture_seconds(base_seconds: float) -> float:
	return base_seconds * (giant_capture_multiplier if population_units > 1 else 1.0)


func can_finish_capture_on_release() -> bool:
	return (
		population_units > 1
		and can_capture()
		and capture_progress > 0.0
		and giant_body_multiplier * lerpf(1.0, 0.2, capture_progress) <= 1.0 + 0.00001
	)


func apply_capture(delta: float, capture_seconds: float, target: Vector2) -> bool:
	if consumed:
		return false
	_detached_for_capture = true
	clear_attraction()
	_launch_elapsed = launch_seconds
	_capture_hold = 0.12
	var body_center: Vector2 = get_capture_point()
	_set_suction_expression(true)
	capture_progress = minf(
		1.0, capture_progress + delta / maxf(get_capture_seconds(capture_seconds), 0.05)
	)
	if population_units == 1:
		body_center = body_center.move_toward(target, delta * (24.0 + capture_progress * 46.0))
		position = body_center - _get_body_center_offset().rotated(rotation)
	_update_surface_rotation()
	queue_redraw()
	if capture_progress >= 1.0:
		consumed = true
		return true
	return false


func release_capture(delta: float) -> void:
	_detached_for_capture = false
	_set_suction_expression(false)
	_capture_hold = 0.0
	peel_progress = 0.0
	if population_units == 1:
		capture_progress = maxf(0.0, capture_progress - delta * 0.75)
	queue_redraw()


func _set_suction_expression(active: bool) -> void:
	_suction_active = active
	if slime_art != null:
		slime_art.set_suction(active)


func _advance_launch(delta: float) -> void:
	_launch_elapsed = minf(launch_seconds, _launch_elapsed + delta)
	var progress: float = _launch_elapsed / launch_seconds
	var travel_progress: float = 1.0 - (1.0 - progress) * (1.0 - progress)
	position = _project_to_surface(_launch_start.lerp(_launch_end, travel_progress))
	if _launch_elapsed >= launch_seconds:
		launch_landed.emit(self)


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
	if Engine.is_editor_hint() or slime_art == null:
		return
	_sync_slime_art()
	var compensation: Transform2D = SurfaceProjection.get_visual_compensation(self)
	var shrink: float = lerpf(1.0, 0.2, capture_progress)
	if not _flying and species == Species.DRILL:
		draw_set_transform_matrix(
			(
				compensation
				* Transform2D(
					0.0, Vector2(1.0, 0.28) * get_presentation_scale(), 0.0, Vector2(0.0, 3.0)
				)
			)
		)
		draw_circle(Vector2.ZERO, body_size * 0.85 * shrink, Color(0.15, 0.18, 0.14, 0.12))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var center: Vector2 = _get_body_center_offset()
	var ring_radius: float = body_size * 1.28 * get_presentation_scale() * shrink
	if peel_progress > 0.0:
		draw_arc(
			center,
			ring_radius,
			-PI / 2.0,
			-PI / 2.0 + TAU * peel_progress,
			32,
			Color("c9a5ea"),
			1.8,
			true
		)
	if capture_progress > 0.02 and (population_units == 1 or _suction_active):
		draw_arc(
			center,
			ring_radius,
			-PI / 2.0,
			-PI / 2.0 + TAU * capture_progress,
			32,
			Color("809c69"),
			1.5,
			true
		)


const SAVE_FIELDS: PackedStringArray = [
	"nest_id",
	"species",
	"high_value",
	"population_units",
	"fused_value_units",
	"reward",
	"position",
	"_wander_target",
	"_wander_wait",
	"_phase",
	"_speed_variation",
	"detached_remaining",
	"_elapsed",
]
const SaveFields = preload("res://scripts/save_fields.gd")


func capture_save() -> Dictionary:
	var data: Dictionary = SaveFields.capture(self, SAVE_FIELDS)
	data["random_state"] = _rng.state
	# An airborne/held monster resumes safely on the ground without being paid twice.
	data.position = surface.project_to_surface(position)
	return data


func restore_save(data: Dictionary) -> void:
	configure_species(data.species as Species, data.high_value, data.reward)
	if data.population_units > 1:
		configure_fusion(data.population_units, data.fused_value_units, data.reward)
	restore_to_surface(data.position)
	SaveFields.restore(self, data, SAVE_FIELDS)
	_rng.state = data.random_state
	_update_surface_rotation()
