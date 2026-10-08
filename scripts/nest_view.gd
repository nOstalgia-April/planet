@tool
class_name NestView
extends Node2D

const SurfaceProjection = preload("res://scripts/surface_projection.gd")
const AutomaticFacility = preload("res://scripts/automatic_facility.gd")

@export_group("场景显示")
@export var outline_color: Color = Color("454944")
@export var slime_color: Color = Color("e985b3")
@export var mucus_color: Color = Color("7398e5")
@export_range(48.0, 108.0, 1.0) var nest_height: float = 70.0:
	set(value):
		nest_height = value
		if is_node_ready():
			_refresh_art()
@export_range(0.4, 1.0, 0.02) var small_height_ratio: float = 0.68
@export_range(0.6, 1.2, 0.02) var flower_height_ratio: float = 0.94
@export_range(0.5, 1.0, 0.05) var tamed_scale: float = 0.92
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
var _selected: bool = false
var _art_rect: Rect2 = Rect2()
var _bloom_tween: Tween

@onready var _selection_shape: CollisionShape2D = $SelectionArea/CollisionShape2D
@onready var _facility: AutomaticFacility = $AutomaticFacility


func _ready() -> void:
	set_notify_transform(true)
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
		_refresh_art()


func update_state(level: int, tamed: bool, max_level: int) -> void:
	var art_changed: bool = level != _level or tamed != _tamed
	var became_tamed: bool = tamed and not _tamed
	var was_tamed: bool = _tamed
	_level = level
	_tamed = tamed
	_max_level = maxi(1, max_level)
	_facility.visible = level >= 2
	_facility.presentation_scale = presentation_scale
	if art_changed:
		_refresh_art()
	if became_tamed:
		if _bloom_tween != null:
			_bloom_tween.kill()
		modulate.a = 0.35
		_bloom_tween = create_tween().set_parallel(true)
		_bloom_tween.tween_property(self, "modulate:a", 1.0, 0.35)
		(
			_bloom_tween
			. tween_property(self, "scale", Vector2.ONE * tamed_scale, 0.35)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
	elif was_tamed and not tamed:
		if _bloom_tween != null:
			_bloom_tween.kill()
		modulate.a = 1.0
		scale = Vector2.ONE
	queue_redraw()


func pulse_automatic() -> void:
	_facility.pulse()


func get_collection_point() -> Vector2:
	var point: Vector2 = Vector2(0.0, _art_rect.position.y * 0.65)
	return (
		transform * SurfaceProjection.get_visual_compensation(self) * (point * presentation_scale)
	)


func set_selected(value: bool) -> void:
	_selected = value
	queue_redraw()


func _refresh_art() -> void:
	var height: float = nest_height
	if _tamed:
		height *= flower_height_ratio
	elif _level == 0:
		height *= small_height_ratio
	var display_size: Vector2 = Vector2(height * 1.6, height)
	_art_rect = Rect2(Vector2(-display_size.x * 0.5, -display_size.y), display_size)
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = _art_rect.size
	_selection_shape.shape = rectangle
	_update_presentation()
	queue_redraw()


func _update_presentation() -> void:
	var presentation: Transform2D = (
		SurfaceProjection.get_visual_compensation(self)
		* Transform2D(0.0, presentation_scale, 0.0, Vector2.ZERO)
	)
	var shape_transform: Transform2D = presentation * Transform2D(0.0, _art_rect.get_center())
	if _selection_shape.transform.is_equal_approx(shape_transform):
		return
	_selection_shape.transform = shape_transform
	_facility.presentation_scale = presentation_scale
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
	draw_set_transform_matrix(
		(
			SurfaceProjection.get_visual_compensation(self)
			* Transform2D(0.0, presentation_scale, 0.0, Vector2.ZERO)
		)
	)
	if _selected:
		var half_width: float = _art_rect.size.x * 0.5 + 5.0
		draw_set_transform_matrix(
			(
				SurfaceProjection.get_visual_compensation(self)
				* Transform2D(
					0.0,
					Vector2(1.0, 0.24) * presentation_scale,
					0.0,
					Vector2(0.0, 3.0) * presentation_scale
				)
			)
		)
		draw_arc(Vector2.ZERO, half_width, 0.0, TAU, 64, Color("729763"), 2.5, true)
		draw_set_transform_matrix(
			(
				SurfaceProjection.get_visual_compensation(self)
				* Transform2D(0.0, presentation_scale, 0.0, Vector2.ZERO)
			)
		)
	_draw_nest_shape()
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


func _draw_nest_shape() -> void:
	var color: Color = slime_color if species == 0 else mucus_color
	var body: PackedVector2Array = PackedVector2Array()
	var entrance: PackedVector2Array = PackedVector2Array()
	for index: int in range(25):
		var angle: float = PI * float(index) / 24.0
		body.append(Vector2(-cos(angle) * _art_rect.size.x * 0.5, -sin(angle) * _art_rect.size.y))
		entrance.append(
			Vector2(-cos(angle) * _art_rect.size.x * 0.19, -sin(angle) * _art_rect.size.y * 0.55)
		)
	draw_colored_polygon(body, color.lightened(0.20 if _tamed else 0.0))
	body.append(body[0])
	draw_polyline(body, outline_color, 2.0, true)
	draw_colored_polygon(entrance, color.darkened(0.48))
	if _tamed:
		var center: Vector2 = Vector2(0.0, -_art_rect.size.y * 0.72)
		draw_polyline(
			PackedVector2Array(
				[
					center + Vector2(-6.0, 0.0),
					center + Vector2(-1.0, 5.0),
					center + Vector2(8.0, -6.0)
				]
			),
			Color("f4f6e8"),
			3.0,
			true
		)
