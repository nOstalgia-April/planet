@tool
class_name NestView
extends Node2D

signal selected(nest_id: int)

@export var outline_color: Color = Color("454944")
@export var nest_color: Color = Color("bab9a6")
@export var flower_color: Color = Color("d7e8bb")
@export_range(48.0, 88.0, 1.0) var nest_height: float = 70.0:
	set(value):
		nest_height = value
		if is_node_ready():
			_update_selection_shape()
		queue_redraw()
@export_range(0.5, 1.0, 0.05) var tamed_scale: float = 0.82

var nest_id: int = -1

var _level: int = 0
var _max_level: int = 3
var _tamed: bool = false
var _selected: bool = false
var _hovered: bool = false
var _bloom_progress: float = 0.0:
	set(value):
		_bloom_progress = value
		queue_redraw()
var _bloom_tween: Tween

@onready var _selection_area: Area2D = $SelectionArea
@onready var _selection_shape: CollisionShape2D = $SelectionArea/CollisionShape2D


func _ready() -> void:
	_update_selection_shape()
	if Engine.is_editor_hint():
		return
	_selection_area.input_event.connect(_on_selection_input)
	_selection_area.mouse_entered.connect(_on_mouse_entered)
	_selection_area.mouse_exited.connect(_on_mouse_exited)


func setup(owner_id: int) -> void:
	nest_id = owner_id
	rotation = position.angle() + PI / 2.0
	queue_redraw()


func update_state(level: int, tamed: bool, max_level: int) -> void:
	_level = level
	_max_level = maxi(1, max_level)
	if tamed and not _tamed:
		_tamed = true
		_update_selection_shape()
		if _bloom_tween != null:
			_bloom_tween.kill()
		_bloom_tween = create_tween().set_parallel(true)
		(
			_bloom_tween
			. tween_property(self, "_bloom_progress", 1.0, 0.42)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)
		(
			_bloom_tween
			. tween_property(self, "scale", Vector2.ONE * tamed_scale, 0.42)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
	elif not tamed:
		var was_tamed: bool = _tamed
		_tamed = false
		if was_tamed:
			_update_selection_shape()
		_bloom_progress = 0.0
		scale = Vector2.ONE
	queue_redraw()


func set_selected(value: bool) -> void:
	_selected = value
	queue_redraw()


func _update_selection_shape() -> void:
	if _tamed:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = 34.0
		_selection_shape.shape = circle
		_selection_shape.position = Vector2.ZERO
	else:
		var capsule: CapsuleShape2D = CapsuleShape2D.new()
		capsule.radius = 28.0
		capsule.height = nest_height + 28.0
		_selection_shape.shape = capsule
		_selection_shape.position = Vector2(0.0, -nest_height * 0.38)


func _on_selection_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			selected.emit(nest_id)
			get_viewport().set_input_as_handled()


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0.0, 7.0), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 26.0, Color(0.15, 0.18, 0.14, 0.18))
	draw_set_transform(Vector2.ZERO)
	if _bloom_progress < 1.0:
		_draw_nest(1.0 - _bloom_progress)
	if _bloom_progress > 0.0:
		_draw_flower(_bloom_progress)
	if _selected or _hovered:
		var ring_color: Color = Color("809c69") if _selected else Color(0.28, 0.32, 0.25, 0.38)
		draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 64, ring_color, 3.0 if _selected else 1.6, true)
		if _selected:
			var marker_y: float = -35.0 if _tamed else -nest_height - 18.0
			draw_circle(Vector2(0.0, marker_y), 3.0, ring_color)
	if not _tamed:
		var total_width: float = float(_max_level - 1) * 9.0
		for pip_index: int in range(_max_level):
			var pip_position: Vector2 = Vector2(
				-total_width / 2.0 + float(pip_index) * 9.0, -nest_height - 8.0
			)
			draw_circle(
				pip_position, 2.6, Color("809c69") if pip_index < _level else Color("d2d2c3")
			)
			draw_arc(pip_position, 2.6, 0.0, TAU, 12, outline_color, 1.0, true)


func _draw_nest(opacity: float) -> void:
	var local_outline: Color = outline_color
	local_outline.a *= opacity
	var local_nest: Color = nest_color
	local_nest.a *= opacity
	var silhouette: PackedVector2Array = PackedVector2Array(
		[
			Vector2(-24.0, 12.0),
			Vector2(-26.0, -12.0),
			Vector2(-24.0, -nest_height * 0.55),
			Vector2(-20.0, -nest_height * 0.80),
			Vector2(-11.0, -nest_height * 0.98),
			Vector2(4.0, -nest_height),
			Vector2(16.0, -nest_height * 0.91),
			Vector2(23.0, -nest_height * 0.65),
			Vector2(25.0, -nest_height * 0.25),
			Vector2(24.0, 12.0),
		]
	)
	draw_colored_polygon(silhouette, local_nest)
	silhouette.append(silhouette[0])
	draw_polyline(silhouette, local_outline, 2.0, true)
	var entrance: PackedVector2Array = PackedVector2Array(
		[
			Vector2(-13.0, 7.0),
			Vector2(-14.0, -20.0),
			Vector2(-12.0, -nest_height * 0.50),
			Vector2(-7.0, -nest_height * 0.59),
			Vector2(0.0, -nest_height * 0.63),
			Vector2(8.0, -nest_height * 0.58),
			Vector2(13.0, -nest_height * 0.48),
			Vector2(14.0, -18.0),
			Vector2(13.0, 7.0),
		]
	)
	draw_colored_polygon(entrance, Color(0.30, 0.31, 0.27, opacity))
	entrance.append(entrance[0])
	draw_polyline(entrance, local_outline, 1.8, true)
	draw_line(
		Vector2(-17.0, -nest_height * 0.77),
		Vector2(-5.0, -nest_height * 0.81),
		local_outline,
		1.3,
		true
	)
	draw_line(
		Vector2(4.0, -nest_height * 0.78),
		Vector2(16.0, -nest_height * 0.73),
		local_outline,
		1.3,
		true
	)
	draw_line(Vector2(-24.0, -19.0), Vector2(-15.0, -23.0), local_outline, 1.3, true)
	draw_line(Vector2(15.0, -13.0), Vector2(24.0, -10.0), local_outline, 1.3, true)


func _draw_flower(opacity: float) -> void:
	var stem_color: Color = Color(0.42, 0.53, 0.32, opacity)
	var petal_color: Color = flower_color
	petal_color.a *= opacity
	var local_outline: Color = outline_color
	local_outline.a *= opacity
	var flower_positions: Array[Vector2] = [
		Vector2(-13.0, -14.0), Vector2(1.0, -24.0), Vector2(14.0, -9.0)
	]
	for flower_position: Vector2 in flower_positions:
		draw_line(Vector2(0.0, 17.0), flower_position, stem_color, 3.0, true)
		for petal_index: int in range(5):
			var petal_position: Vector2 = (
				flower_position + Vector2.from_angle(float(petal_index) * TAU / 5.0) * 6.2
			)
			draw_circle(petal_position, 4.8, petal_color)
			draw_arc(petal_position, 4.8, 0.0, TAU, 16, local_outline, 1.1, true)
		draw_circle(flower_position, 3.5, Color(0.73, 0.77, 0.49, opacity))
	draw_colored_polygon(
		PackedVector2Array([Vector2(0.0, 7.0), Vector2(-17.0, 0.0), Vector2(-13.0, 11.0)]),
		stem_color
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(2.0, 12.0), Vector2(19.0, 1.0), Vector2(16.0, 13.0)]),
		stem_color
	)
	draw_arc(Vector2(0.0, 17.0), 5.0, 0.0, PI, 12, local_outline, 1.5, true)
