extends Node

signal view_changed
signal view_rotated

@export var world: Node2D
@export var projection_root: Node2D
@export var planet_surface: PlanetSurface
@export var bottom_toolbar: Control
@export_range(1.0, 2.4, 0.05) var near_horizontal_stretch: float = 1.65
@export_range(1.0, 3.0, 0.01) var near_core_toolbar_height_ratio: float = 5.0 / 3.0
@export_range(0.1, 0.75, 0.001) var near_horizon_ratio: float = 0.55
@export_range(1.0, 1.3, 0.01) var near_surface_radius_ratio: float = 1.07
@export_range(0.2, 1.5, 0.01) var near_slime_scale: float = 0.90
@export var near_nest_scale: Vector2 = Vector2.ONE
@export_range(0.2, 0.48, 0.01) var overview_radius_ratio: float = 0.42
@export_range(1.0, 1.4, 0.01) var overview_outer_radius_ratio: float = 1.10
@export_range(0.0, 80.0, 1.0) var overview_shadow_offset: float = 24.0
@export_range(-0.3, 0.3, 0.005) var overview_rotation_speed: float = 0.035

var zoom_amount: float = 1.0
var target_zoom: float:
	get:
		return zoom_amount

var _play_rect: Rect2 = Rect2()
var _planet_radius: float = 240.0
var _view_rotation: float = 0.0
var _configured: bool = false
var _dragging: bool = false
var _last_pointer: Vector2 = Vector2.ZERO


func _ready() -> void:
	assert(world != null, "Planet view requires its World Node2D dependency.")
	assert(projection_root != null, "Planet view requires its projection root dependency.")
	assert(planet_surface != null, "Planet view requires its surface geometry dependency.")
	assert(bottom_toolbar != null, "Planet view requires its bottom toolbar dependency.")
	_view_rotation = world.rotation


func _process(delta: float) -> void:
	if not _configured or not is_overview() or _dragging or is_zero_approx(overview_rotation_speed):
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


func reset_view() -> void:
	assert(world != null, "Planet view requires its World Node2D dependency.")
	zoom_amount = 1.0
	_view_rotation = 0.0
	_dragging = false
	if _configured:
		_apply_view()
	else:
		world.rotation = _view_rotation
		view_changed.emit()


func zoom_steps(steps: float) -> void:
	if is_zero_approx(steps):
		return
	var next_view: float = 1.0 if steps > 0.0 else 0.0
	if is_equal_approx(zoom_amount, next_view):
		return
	if is_overview() and next_view == 1.0:
		# The currently displayed overview decides the near-view heading. Its
		# screen-top surface direction becomes the horizontal center of the
		# existing near horizon, even if a cached angle is no longer current.
		var top_direction: Vector2 = (
			(world.get_global_transform_with_canvas().affine_inverse().basis_xform(Vector2.UP))
			. normalized()
		)
		_view_rotation = wrapf(Vector2.UP.angle() - top_direction.angle(), -PI, PI)
	end_drag()
	zoom_amount = next_view
	_apply_view()


func begin_drag(pointer: Vector2) -> void:
	assert(_configured, "Configure the planet view before starting a drag.")
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
	return is_zero_approx(zoom_amount)


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
	var core_height: float = (
		bottom_toolbar.get_global_rect().size.y * near_core_toolbar_height_ratio
	)
	var band_height: float = viewport_size.y * (1.0 - near_horizon_ratio) - core_height
	var band_depth: float = (
		_planet_radius * near_surface_radius_ratio - planet_surface.get_inner_radius(0.0)
	)
	var near_scale: float = band_height / band_depth
	var near_screen_radius: float = _planet_radius * near_surface_radius_ratio * near_scale
	var near_center: Vector2 = Vector2(
		_play_rect.get_center().x, viewport_size.y * near_horizon_ratio + near_screen_radius
	)
	var overview_extent: float = (
		_planet_radius * overview_outer_radius_ratio + overview_shadow_offset
	)
	var overview_scale: float = (
		minf(_play_rect.size.x, _play_rect.size.y) * overview_radius_ratio / overview_extent
	)
	projection_root.scale = Vector2.ONE if is_overview() else Vector2(near_horizontal_stretch, 1.0)
	world.position = (
		(_play_rect.get_center() if is_overview() else near_center) / projection_root.scale
	)
	world.scale = Vector2.ONE * (overview_scale if is_overview() else near_scale)
	world.rotation = _view_rotation
	view_changed.emit()
