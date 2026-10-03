@tool
class_name CaptureNet
extends Node2D

enum Presentation { PREVIEW, CAST, OPEN, CARRIED, RESULT, COOLDOWN }

@export_range(0.05, 0.6, 0.01) var cast_seconds: float = 0.18
@export_range(0.1, 1.5, 0.01) var close_seconds: float = 0.35
@export_range(20.0, 160.0, 1.0) var preview_radius: float = 84.0
@export_range(0.1, 0.6, 0.01) var result_flash_seconds: float = 0.30
@export var ink: Color = Color("454944")
@export var accent: Color = Color("7b9c83")

var _presentation: Presentation = Presentation.PREVIEW
var _radius: float = 84.0
var _progress: float = 0.0
var _cooldown_progress: float = 0.0
var _result_age: float = 0.0
var _result_count: int = 0

@onready var _rim: Line2D = $Rim
@onready var _sack: Polygon2D = $Sack
@onready var _sack_outline: Line2D = $SackOutline
@onready var _handle: Line2D = $Handle
@onready var _collected_label: Label = $CollectedLabel
@onready var _result_ring: Line2D = $ResultRing
@onready var _result_label: Label = $ResultCount
@onready var _cooldown_label: Label = $CooldownLabel


func _ready() -> void:
	show_preview(position, preview_radius)


func _process(delta: float) -> void:
	if _presentation == Presentation.RESULT:
		_result_age += delta
		_update_result_ring()
		queue_redraw()


func show_preview(pointer: Vector2, radius: float) -> void:
	_present(Presentation.PREVIEW, pointer, radius, 0.0)


func show_cast(cast_position: Vector2, radius: float, progress: float) -> void:
	_present(Presentation.CAST, cast_position, radius, progress)


func show_open(anchor: Vector2, radius: float, close_progress: float) -> void:
	_present(Presentation.OPEN, anchor, radius, close_progress)


func show_carried(pointer: Vector2, collected_count: int) -> void:
	_present(Presentation.CARRIED, pointer, _radius, 1.0)
	_collected_label.text = str(collected_count)
	_collected_label.visible = collected_count > 0


func show_result(anchor: Vector2, caught_count: int) -> void:
	if _presentation != Presentation.RESULT or position != anchor or _result_count != caught_count:
		_result_age = 0.0
	_result_count = caught_count
	_present(Presentation.RESULT, anchor, _radius, 1.0)
	_result_label.text = str(maxi(0, caught_count))
	_result_label.visible = true
	_update_result_ring()


func show_cooldown(pointer: Vector2, radius: float, remaining: float, total: float) -> void:
	_present(Presentation.COOLDOWN, pointer, radius, 0.0)
	_cooldown_progress = clampf(1.0 - remaining / maxf(total, 0.01), 0.0, 1.0)
	_cooldown_label.text = "%.1f" % maxf(0.0, remaining)
	_cooldown_label.visible = true
	queue_redraw()


func _present(mode: Presentation, pointer: Vector2, radius: float, progress: float) -> void:
	position = pointer
	_presentation = mode
	_radius = radius
	_progress = clampf(progress, 0.0, 1.0)
	visible = true
	var bag_visible: bool = mode == Presentation.CARRIED
	_sack.visible = bag_visible
	_sack_outline.visible = bag_visible
	_handle.visible = bag_visible or mode in [Presentation.PREVIEW, Presentation.COOLDOWN]
	_collected_label.visible = false
	_result_ring.visible = mode == Presentation.RESULT
	_result_label.visible = false
	_cooldown_label.visible = false
	_rim.visible = not bag_visible and mode != Presentation.RESULT
	var display_radius: float = _display_radius()
	var rim_points: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(65):
		rim_points.append(Vector2.from_angle(TAU * float(point_index) / 64.0) * display_radius)
	_rim.points = rim_points
	_rim.default_color = Color(
		ink, 0.25 if mode in [Presentation.PREVIEW, Presentation.COOLDOWN] else 0.85
	)
	_handle.points = (
		PackedVector2Array([Vector2(-21.0, 25.0), Vector2(-5.0, 6.0)])
		if mode in [Presentation.PREVIEW, Presentation.COOLDOWN]
		else PackedVector2Array([Vector2(0.0, -42.0), Vector2(0.0, -4.0)])
	)
	queue_redraw()


func _display_radius() -> float:
	match _presentation:
		Presentation.PREVIEW, Presentation.COOLDOWN:
			return _radius
		Presentation.CAST:
			return lerpf(9.0, _radius, ease(_progress, 0.55))
		Presentation.OPEN:
			return lerpf(_radius, 12.0, _progress)
		_:
			return 12.0


func _draw() -> void:
	if _presentation == Presentation.CARRIED:
		_draw_bag_mesh()
		return
	if _presentation == Presentation.RESULT:
		_draw_result_sparks()
		return
	var display_radius: float = _display_radius()
	var cooling: bool = _presentation == Presentation.COOLDOWN
	var preview: bool = _presentation in [Presentation.PREVIEW, Presentation.COOLDOWN]
	var mesh_color: Color = (
		Color(ink, 0.08) if cooling else Color(accent, 0.12 if preview else 0.65)
	)
	if not preview:
		draw_circle(Vector2.ZERO, display_radius, Color(accent, 0.12))
	for line_index: int in range(-4, 5):
		var cross: float = display_radius * float(line_index) / 5.0
		var half_length: float = sqrt(maxf(0.0, display_radius * display_radius - cross * cross))
		draw_line(Vector2(cross, -half_length), Vector2(cross, half_length), mesh_color, 1.1, true)
		draw_line(Vector2(-half_length, cross), Vector2(half_length, cross), mesh_color, 1.1, true)
	if cooling:
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 48, Color(ink, 0.2), 2.5, true)
		draw_arc(
			Vector2.ZERO,
			13.0,
			-PI / 2.0,
			-PI / 2.0 + TAU * _cooldown_progress,
			48,
			Color(ink, 0.65),
			2.5,
			true
		)
	elif preview:
		draw_circle(Vector2.ZERO, 10.0, Color("ecebd6"))
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 32, ink, 2.0, true)
		draw_line(Vector2(-7.0, -3.0), Vector2(7.0, -3.0), accent, 1.0, true)
		draw_line(Vector2(-7.0, 3.0), Vector2(7.0, 3.0), accent, 1.0, true)
		draw_line(Vector2(-3.0, -7.0), Vector2(-3.0, 7.0), accent, 1.0, true)
		draw_line(Vector2(3.0, -7.0), Vector2(3.0, 7.0), accent, 1.0, true)


func _update_result_ring() -> void:
	var progress: float = clampf(_result_age / result_flash_seconds, 0.0, 1.0)
	var flash_radius: float = lerpf(_radius * 0.35, _radius, ease(progress, 0.55))
	var ring_points: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(65):
		ring_points.append(Vector2.from_angle(TAU * float(point_index) / 64.0) * flash_radius)
	_result_ring.points = ring_points
	_result_ring.modulate.a = 1.0 - progress * 0.8
	_result_label.position = Vector2(-30.0, -16.0 - progress * 8.0)


func _draw_result_sparks() -> void:
	var progress: float = clampf(_result_age / result_flash_seconds, 0.0, 1.0)
	var distance: float = lerpf(_radius * 0.45, _radius * 1.15, progress)
	for spark_index: int in range(8):
		var direction: Vector2 = Vector2.from_angle(TAU * float(spark_index) / 8.0)
		draw_line(
			direction * distance,
			direction * (distance + 9.0),
			Color(accent, 1.0 - progress),
			2.4,
			true
		)


func _draw_bag_mesh() -> void:
	for line_index: int in range(4):
		var cross: float = -15.0 + float(line_index) * 10.0
		draw_line(Vector2(cross, 0.0), Vector2(cross * 0.6, 36.0), Color(accent, 0.8), 1.0, true)
	for line_index: int in range(4):
		var height: float = 4.0 + float(line_index) * 9.0
		var half_width: float = 23.0 - float(line_index) * 2.5
		draw_line(
			Vector2(-half_width, height), Vector2(half_width, height), Color(accent, 0.8), 1.0, true
		)
