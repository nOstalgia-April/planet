class_name NestView
extends Node2D

signal flower_appeared(nest_id: int, species: int)
signal production_released(nest_id: int, amount: int)

const SurfaceProjection = preload("res://scripts/surface_projection.gd")
const NestArt = preload("res://scripts/nest_art.gd")
const FlowerProduction = preload("res://scripts/flower_production_effect.gd")

@export_group("场景显示")
@export var outline_color: Color = Color("454944")
@export var art_settings: ArtPresentationSettings = preload("res://resources/art_presentation.tres")
@export var surface: PlanetSurface
@export_range(-30.0, 30.0, 0.25) var ground_inset: float = 0.0
@export_range(0.0, 12.0, 0.25) var drill_ground_inset: float = 0.0
@export var presentation_scale: Vector2 = Vector2.ONE:
	set(value):
		presentation_scale = Vector2.ONE * value.x
		if is_node_ready():
			_update_presentation()

var nest_id: int = -1
var species: int = 0
var emergence_progress: float = 1.0

var _level: int = 0
var _max_level: int = 3
var _tamed: bool = false
var _art_rect: Rect2 = Rect2()
var _selection_rect: Rect2 = Rect2()
var _state_initialized: bool = false
var _ground_projection: Transform2D
var _ground_rect: Rect2

@onready var _selection_shape: CollisionShape2D = $SelectionArea/CollisionShape2D
@onready var _art: NestArt = $NestArt
@onready var _production: FlowerProduction = $ProductionEffect
@onready var _emergence_dust: CPUParticles2D = $EmergenceDust


func _ready() -> void:
	set_notify_transform(true)
	_selection_shape.shape = _selection_shape.shape.duplicate()
	_art.bounds_changed.connect(_refresh_art)
	_art.flower_appeared.connect(_on_flower_appeared)
	_art.production_started.connect(_production.play)
	_production.released.connect(_on_production_released)
	_refresh_art()


func _on_flower_appeared() -> void:
	flower_appeared.emit(nest_id, species)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_update_presentation()


func setup(owner_id: int) -> void:
	nest_id = owner_id
	rotation = position.angle() + PI / 2.0
	if is_node_ready():
		_update_presentation()


func configure_species(value: int) -> void:
	assert(value >= 0 and value <= 2, "NestView requires a supported species.")
	species = value
	if is_node_ready():
		_art.configure_species(species)
		_refresh_art()


func update_state(level: int, tamed: bool, max_level: int, animate: bool = true) -> void:
	var level_changed: bool = level != _level
	_level = level
	_tamed = tamed
	_max_level = maxi(1, max_level)
	if level_changed or not _state_initialized:
		_art.set_stage(level, _state_initialized and animate)
	_state_initialized = true
	_refresh_art()


func pulse_automatic(amount: int = 0) -> void:
	_art.play_production(amount)


func _on_production_released(amount: int) -> void:
	production_released.emit(nest_id, amount)


func get_production_point() -> Vector2:
	var tip: Vector2 = Vector2(_art_rect.get_center().x, _art_rect.position.y)
	return transform * _art.transform * tip


func pulse_spawn() -> void:
	_art.play_spawn()


func begin_emergence() -> void:
	set_emergence_progress(0.0)
	_emergence_dust.restart()
	_emergence_dust.emitting = true


func set_emergence_progress(progress: float) -> void:
	emergence_progress = clampf(progress, 0.0, 1.0)
	_art.set_emergence_progress(emergence_progress)


func get_collection_point() -> Vector2:
	var point: Vector2 = Vector2(0.0, _art_rect.position.y * 0.65)
	return transform * _get_presentation_transform() * point


func get_maximum_footprint_width() -> float:
	# Site layout reads this before the view enters the tree and runs _ready.
	var art: NestArt = $NestArt
	return art.maximum_footprint_width * art_settings.get_maximum_nest_scale()


func _refresh_art() -> void:
	_art_rect = _art.get_art_bounds()
	_update_presentation()
	queue_redraw()


func _get_presentation_transform() -> Transform2D:
	var presentation: Transform2D = (
		SurfaceProjection.get_visual_compensation(self)
		* Transform2D(
			0.0,
			presentation_scale * art_settings.get_nest_scale(species, _level),
			0.0,
			Vector2.ZERO
		)
	)
	var ground_radius: float = position.length()
	var sink: float = drill_ground_inset if species == NestState.Species.DRILL else ground_inset
	sink += art_settings.get_nest_sink(species, _level)
	var inward: Vector2 = Vector2.DOWN
	if ground_radius > 0.0:
		inward = (-position.normalized()).rotated(-rotation)
	# Transparent padding and changing frame bounds must not lift the contact edge.
	presentation.origin = inward * sink - presentation.basis_xform(Vector2(0.0, _art_rect.end.y))
	return presentation


func refresh_presentation() -> void:
	_update_presentation()


func get_source_texture() -> Texture2D:
	return _art.get_source_texture()


func _update_presentation() -> void:
	var presentation: Transform2D = _get_presentation_transform()
	_art.transform = presentation
	var curve: Vector3 = Vector3(-1000.0, 0.0, 0.0)
	var bend_enabled: bool = art_settings.curved_seating and _art.uses_ground_bend()
	if bend_enabled and position.length() > 0.0:
		# Use the local surface tangent and retain the camera's nonuniform projection.
		var vertical_squared: float = presentation.y.length_squared()
		curve = Vector3(
			-position.length() * presentation.y.y / vertical_squared,
			presentation.x.dot(presentation.y) / vertical_squared,
			presentation.x.length_squared() / vertical_squared
		)
	_selection_rect = _art.set_ground_curve(curve, art_settings.nest_bend_height_ratio)
	if surface != null and bend_enabled:
		var projection: Transform2D = (
			_art.global_transform.affine_inverse() * surface.global_transform
		)
		# Keep the existing adjustable burial depth on top of the contour fit.
		projection.origin.y += presentation.basis_xform_inv(presentation.origin).y + _art_rect.end.y
		if (
			not projection.is_equal_approx(_ground_projection)
			or not _art_rect.is_equal_approx(_ground_rect)
		):
			_ground_projection = projection
			_ground_rect = _art_rect
			_art.set_ground_contour(projection * surface.get_surface_polygon())
		_selection_rect = _art.get_grounded_bounds()
	else:
		_ground_rect = Rect2()
		_art.clear_ground_contour()
	var rectangle: RectangleShape2D = _selection_shape.shape as RectangleShape2D
	rectangle.size = _selection_rect.size
	var shape_transform: Transform2D = presentation * Transform2D(0.0, _selection_rect.get_center())
	if _selection_shape.transform.is_equal_approx(shape_transform):
		return
	_selection_shape.transform = shape_transform
	queue_redraw()


func contains_viewport_point(viewport_position: Vector2) -> bool:
	# Transform notifications and presentation setters maintain this shape.
	# Hit queries must not rebuild the nest drawing every pointer frame.
	var local_point: Vector2 = (
		_selection_shape.get_global_transform_with_canvas().affine_inverse() * viewport_position
	)
	return Rect2(-_selection_rect.size * 0.5, _selection_rect.size).has_point(local_point)


func get_hover_rect() -> Rect2:
	return (
		_selection_shape.get_global_transform_with_canvas()
		* Rect2(-_selection_rect.size * 0.5, _selection_rect.size)
	)
