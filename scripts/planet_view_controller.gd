extends Node

signal view_changed
signal view_rotated
signal projection_changed

@export var world: Node2D
@export var projection_root: Node2D
@export_range(0.55, 1.2, 0.01) var near_radius_ratio: float = 0.60
@export_range(0.1, 0.75, 0.001) var near_horizon_ratio: float = 0.55
@export_range(-0.1, 0.1, 0.001) var near_horizontal_offset_ratio: float = 0.0
@export_range(1.0, 1.3, 0.01) var near_surface_radius_ratio: float = 1.07
@export_range(0.2, 1.5, 0.01) var near_slime_scale: float = 0.90
@export var near_nest_scale: Vector2 = Vector2.ONE
@export_range(0.2, 0.48, 0.01) var overview_radius_ratio: float = 0.42
@export_range(1.0, 1.4, 0.01) var overview_outer_radius_ratio: float = 1.10
@export_range(0.0, 80.0, 1.0) var overview_shadow_offset: float = 24.0
@export_range(-0.3, 0.3, 0.005) var overview_rotation_speed: float = 0.035
@export_range(0.0, 1.0, 0.05) var transition_seconds: float = 0.8
@export_range(0.0, 0.05, 0.005) var transition_pull: float = 0.02

var zoom_amount: float = 1.0
var target_zoom: float = 1.0
var near_blend: float = 1.0

var _play_rect: Rect2 = Rect2()
var _planet_radius: float = 240.0
var _view_rotation: float = 0.0
var _configured: bool = false
var _dragging: bool = false
var _last_pointer: Vector2 = Vector2.ZERO
var _transition_elapsed: float = 0.0
var _transition_duration: float = 0.0
var _transition_start_zoom: float = 1.0
var _transition_start_blend: float = 1.0
var _transition_start_rotation: float = 0.0
var _transition_target_rotation: float = 0.0
var _lens_pull: float = 0.0
var _transition_start_pull: float = 0.0


func _ready() -> void:
	assert(world != null, "Planet view requires its World Node2D dependency.")
	assert(projection_root != null, "Planet view requires its projection root dependency.")
	_view_rotation = world.rotation


func _process(delta: float) -> void:
	if not _configured:
		return
	if is_transitioning():
		_transition_elapsed = minf(_transition_elapsed + maxf(delta, 0.0), _transition_duration)
		var progress: float = _transition_elapsed / _transition_duration
		_view_rotation = lerp_angle(
			_transition_start_rotation, _transition_target_rotation, smoothstep(0.0, 1.0, progress)
		)
		zoom_amount = lerpf(_transition_start_zoom, target_zoom, smoothstep(0.0, 1.0, progress))
		# Detail layers and backgrounds can fade; the planet keeps one artwork.
		near_blend = lerpf(_transition_start_blend, target_zoom, smoothstep(0.45, 0.85, progress))
		# A small lens pull accompanies the zoom without a permanent flattening
		# or a rubbery rebound. Reversal keeps the currently displayed transform.
		var direction: float = 1.0 if is_overview() else -1.0
		_lens_pull = (
			_transition_start_pull * (1.0 - smoothstep(0.0, 0.4, progress))
			+ (
				direction
				* transition_pull
				* absf(target_zoom - _transition_start_zoom)
				* sin(progress * PI)
				* sin(progress * PI)
			)
		)
		if not is_transitioning():
			_lens_pull = 0.0
		_apply_view()
		if not is_transitioning():
			view_changed.emit()
		return
	if not is_overview() or _dragging or is_zero_approx(overview_rotation_speed):
		return
	_view_rotation = wrapf(_view_rotation + overview_rotation_speed * maxf(delta, 0.0), -PI, PI)
	# Overview markers already follow the world transform each frame. Do not
	# rerun the mode-change presentation work for this small rotation step.
	world.rotation = _view_rotation


func configure(play_rect: Rect2, planet_radius: float) -> void:
	assert(world != null, "Planet view requires its World Node2D dependency.")
	assert(play_rect.size.x > 0.0 and play_rect.size.y > 0.0)
	assert(planet_radius > 0.0)
	_play_rect = play_rect
	_planet_radius = planet_radius
	_view_rotation = world.rotation
	_configured = true
	_apply_view()
	view_changed.emit()


func reset_view() -> void:
	assert(world != null, "Planet view requires its World Node2D dependency.")
	zoom_amount = 1.0
	target_zoom = 1.0
	near_blend = 1.0
	_transition_duration = 0.0
	_lens_pull = 0.0
	_view_rotation = 0.0
	_dragging = false
	if _configured:
		_apply_view()
	else:
		world.rotation = _view_rotation
	view_changed.emit()


func zoom_steps(steps: float, animated: bool = true) -> void:
	if is_zero_approx(steps):
		return
	var next_view: float = 1.0 if steps > 0.0 else 0.0
	if is_equal_approx(target_zoom, next_view):
		return
	var next_rotation: float = world.rotation
	if is_overview() and next_view == 1.0:
		# The currently displayed overview decides the near-view heading. Its
		# screen-top surface direction becomes the horizontal center of the
		# existing near horizon, even if a cached angle is no longer current.
		var top_direction: Vector2 = (
			(world.get_global_transform_with_canvas().affine_inverse().basis_xform(Vector2.UP))
			. normalized()
		)
		next_rotation = wrapf(Vector2.UP.angle() - top_direction.angle(), -PI, PI)
	_start_transition(next_view, next_rotation, animated)


func focus_surface(surface_angle: float, animated: bool = true) -> void:
	assert(_configured, "Configure the planet view before focusing a surface region.")
	if not is_overview() or is_transitioning():
		return
	# Use the cluster's world-space heading, independent of bubble avoidance
	# offsets and overview spin. The selected ground becomes the near horizon center.
	_start_transition(1.0, wrapf(Vector2.UP.angle() - surface_angle, -PI, PI), animated)


func _start_transition(next_view: float, next_rotation: float, animated: bool) -> void:
	end_drag()
	target_zoom = next_view
	_transition_start_rotation = world.rotation
	_transition_target_rotation = next_rotation
	_transition_start_zoom = zoom_amount
	_transition_start_blend = near_blend
	_transition_start_pull = _lens_pull
	_transition_elapsed = 0.0
	_transition_duration = transition_seconds * absf(target_zoom - zoom_amount) if animated else 0.0
	if is_zero_approx(_transition_duration):
		_transition_duration = 0.0
		_view_rotation = _transition_target_rotation
		zoom_amount = target_zoom
		near_blend = target_zoom
		_lens_pull = 0.0
		_apply_view()
	view_changed.emit()


func begin_drag(pointer: Vector2) -> void:
	assert(_configured, "Configure the planet view before starting a drag.")
	if is_transitioning():
		return
	_dragging = true
	_last_pointer = pointer


func drag_to(pointer: Vector2) -> void:
	if not _dragging:
		return
	var horizontal_distance: float = pointer.x - _last_pointer.x
	_last_pointer = pointer
	if is_zero_approx(horizontal_distance):
		return
	var screen_radius: float = _planet_radius * world.scale.x * projection_root.scale.x
	_view_rotation += horizontal_distance / screen_radius
	# Rotation leaves projection size and ecology geometry unchanged. Avoid
	# rerunning mode/layout work for every mouse-motion event while dragging.
	world.rotation = _view_rotation
	view_rotated.emit()


func end_drag() -> void:
	_dragging = false


func is_dragging() -> bool:
	return _dragging


func is_overview() -> bool:
	return is_zero_approx(target_zoom)


func is_transitioning() -> bool:
	return _transition_elapsed < _transition_duration


func contains_planet_body(viewport_position: Vector2) -> bool:
	assert(_configured, "Configure the planet view before testing its displayed body.")
	var local_point: Vector2 = (
		world.get_global_transform_with_canvas().affine_inverse() * viewport_position
	)
	# Include the solid center, irregular edge, and shifted lower rim in both
	# projections; the walkable crust is deliberately a separate hit region.
	var radius: float = (
		_planet_radius * maxf(near_surface_radius_ratio, overview_outer_radius_ratio)
	)
	local_point.y -= clampf(local_point.y, 0.0, overview_shadow_offset)
	return local_point.length_squared() <= radius * radius


func get_near_screen_half_angle(activity_radius: float) -> float:
	assert(_configured and activity_radius > 0.0)
	return PI * 0.5


func _apply_view() -> void:
	var viewport_size: Vector2 = _play_rect.get_center() * 2.0
	var radius: float = _planet_radius * near_surface_radius_ratio
	# Near view crops the top of a larger circle. Both endpoints keep identical
	# proportions, so every texture landmark is related by uniform magnification.
	var near_screen_radius: float = viewport_size.x * near_radius_ratio
	var near_scale: float = near_screen_radius / radius
	var near_center: Vector2 = Vector2(
		_play_rect.get_center().x + viewport_size.x * near_horizontal_offset_ratio,
		viewport_size.y * near_horizon_ratio + near_screen_radius
	)
	var overview_extent: float = (
		_planet_radius * overview_outer_radius_ratio + overview_shadow_offset
	)
	var overview_scale: float = (
		minf(_play_rect.size.x, _play_rect.size.y) * overview_radius_ratio / overview_extent
	)
	var display_scale: float = exp(lerpf(log(overview_scale), log(near_scale), zoom_amount))
	# Interpolate the top surface anchor, not the offscreen center: this keeps
	# the same piece of ground in sight while the whole globe is revealed.
	var surface_anchor: Vector2 = (
		(_play_rect.get_center() - Vector2(0.0, radius * overview_scale))
		. lerp(near_center - Vector2(0.0, near_screen_radius), zoom_amount)
	)
	projection_root.scale = Vector2(1.0 + _lens_pull, 1.0 - _lens_pull * 0.7)
	var vertical_radius: float = radius * display_scale * projection_root.scale.y
	world.position = (surface_anchor + Vector2(0.0, vertical_radius)) / projection_root.scale
	world.scale = Vector2.ONE * display_scale
	world.rotation = _view_rotation
	projection_changed.emit()
