class_name NestView
extends Node2D

const SurfaceProjection = preload("res://scripts/surface_projection.gd")
const NestArt = preload("res://scripts/nest_art.gd")

@export_group("场景显示")
@export var outline_color: Color = Color("454944")
@export_range(0.0, 12.0, 0.25) var ground_inset: float = 8.0
@export var presentation_scale: Vector2 = Vector2.ONE:
	set(value):
		presentation_scale = Vector2.ONE * value.x
		if is_node_ready():
			_update_presentation()

var nest_id: int = -1
var species: int = 0

var _level: int = 0
var _max_level: int = 3
var _tamed: bool = false
var _art_rect: Rect2 = Rect2()
var _state_initialized: bool = false

@onready var _selection_shape: CollisionShape2D = $SelectionArea/CollisionShape2D
@onready var _art: NestArt = $NestArt


func _ready() -> void:
	set_notify_transform(true)
	_art.bounds_changed.connect(_refresh_art)
	_refresh_art()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_update_presentation()


func setup(owner_id: int) -> void:
	nest_id = owner_id
	rotation = position.angle() + PI / 2.0
	if is_node_ready():
		_update_presentation()


func configure_species(value: int) -> void:
	assert(value == 0 or value == 1, "NestView supports slime and mucus species.")
	species = value
	if is_node_ready():
		_art.configure_species(species)
		_refresh_art()


func update_state(level: int, tamed: bool, max_level: int) -> void:
	var level_changed: bool = level != _level
	_level = level
	_tamed = tamed
	_max_level = maxi(1, max_level)
	if level_changed or not _state_initialized:
		_art.set_stage(level, _state_initialized)
	_state_initialized = true
	_refresh_art()


func pulse_automatic() -> void:
	_art.play_production()


func pulse_spawn() -> void:
	_art.play_spawn()


func get_collection_point() -> Vector2:
	var point: Vector2 = Vector2(0.0, _art_rect.position.y * 0.65)
	return transform * _get_presentation_transform() * point


func get_maximum_footprint_width() -> float:
	return _art.get_maximum_footprint_width()


func _refresh_art() -> void:
	_art_rect = _art.get_art_bounds()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = _art_rect.size
	_selection_shape.shape = rectangle
	_update_presentation()
	queue_redraw()


func _get_presentation_transform() -> Transform2D:
	var presentation: Transform2D = (
		SurfaceProjection.get_visual_compensation(self)
		* Transform2D(0.0, presentation_scale, 0.0, Vector2.ZERO)
	)
	var ground_radius: float = position.length()
	var half_width: float = presentation.basis_xform(Vector2(_art_rect.size.x * 0.5, 0.0)).length()
	var sink: float = ground_inset
	var inward: Vector2 = Vector2.DOWN
	if ground_radius > 0.0:
		# Seat the flat footprint into the curved surface instead of balancing it at its center.
		sink += (
			ground_radius - sqrt(maxf(0.0, ground_radius * ground_radius - half_width * half_width))
		)
		inward = (-position.normalized()).rotated(-rotation)
	# Transparent padding and changing frame bounds must not lift the contact edge.
	presentation.origin = inward * sink - presentation.basis_xform(Vector2(0.0, _art_rect.end.y))
	return presentation


func _update_presentation() -> void:
	var presentation: Transform2D = _get_presentation_transform()
	_art.transform = presentation
	var shape_transform: Transform2D = presentation * Transform2D(0.0, _art_rect.get_center())
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
	return Rect2(-_art_rect.size * 0.5, _art_rect.size).has_point(local_point)


func get_hover_rect() -> Rect2:
	return (
		_selection_shape.get_global_transform_with_canvas()
		* Rect2(-_art_rect.size * 0.5, _art_rect.size)
	)


func _draw() -> void:
	if not is_node_ready():
		return
	draw_set_transform_matrix(_get_presentation_transform())
	if not _tamed:
		var total_width: float = float(_max_level - 1) * 9.0
		for pip_index: int in range(_max_level):
			var pip_position: Vector2 = Vector2(
				-total_width * 0.5 + float(pip_index) * 9.0, _art_rect.position.y - 8.0
			)
			draw_circle(
				pip_position, 2.6, Color("809c69") if pip_index < _level else Color("d2d2c3")
			)
			draw_arc(pip_position, 2.6, 0.0, TAU, 12, outline_color, 1.0, true)
