@tool
extends Node2D

@export_range(8.0, 40.0, 1.0) var radius: float = 24.0
@export_range(40.0, 120.0, 1.0) var attraction_radius: float = 70.0
@export_range(30.0, 100.0, 1.0) var pipe_length: float = 58.0
@export_range(0.0, 30.0, 1.0) var pipe_bend: float = 14.0
@export var ink: Color = Color("454944")
@export var accent: Color = Color("4c837c")
@export var active: bool = false

var _time: float = 0.0
var _mouth_local: Vector2 = Vector2.ZERO
var _collected_count: int = 0

@onready var _pipe_outline: Line2D = $PipeOutline
@onready var _pipe_fill: Line2D = $PipeFill
@onready var _mouth: Node2D = $Mouth
@onready var _collected_label: Label = $Count


func _ready() -> void:
	_update_parts()


func set_tool_state(
	tool_position: Vector2, mouth_position: Vector2, is_active: bool, collected_count: int
) -> void:
	position = tool_position
	if not tool_position.is_zero_approx():
		rotation = tool_position.angle() + PI
	_mouth_local = (mouth_position - tool_position).rotated(-rotation)
	active = is_active
	_collected_count = maxi(0, collected_count)
	_update_parts()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if Engine.is_editor_hint():
		_update_parts()
	queue_redraw()


func _update_parts() -> void:
	var pipe_points: PackedVector2Array = PackedVector2Array()
	var start: Vector2 = _mouth_local + Vector2(-pipe_length, pipe_bend)
	var bend: Vector2 = _mouth_local + Vector2(-pipe_length * 0.55, pipe_bend)
	var end: Vector2 = _mouth_local + Vector2(-10.0, 0.0)
	for point_index: int in range(17):
		var progress: float = float(point_index) / 16.0
		pipe_points.append(start.bezier_interpolate(bend, end, end, progress))
	_pipe_outline.points = pipe_points
	_pipe_fill.points = pipe_points
	_mouth.position = _mouth_local
	_collected_label.position = _mouth_local + Vector2(-pipe_length - 2.0, 22.0)
	_collected_label.rotation = -rotation
	_collected_label.text = str(_collected_count)
	_collected_label.visible = _collected_count > 0


func _draw() -> void:
	var range_color: Color = Color(accent, 0.65) if active else Color(ink, 0.18)
	if active:
		draw_circle(_mouth_local, radius, Color(accent, 0.10))
		draw_arc(_mouth_local, radius, 0.0, TAU, 64, range_color, 1.6, true)
		for arc_index: int in range(20):
			var angle: float = float(arc_index) * TAU / 20.0
			draw_arc(
				_mouth_local,
				attraction_radius,
				angle,
				angle + 0.14,
				8,
				Color(accent, 0.23),
				1.0,
				true
			)
		for particle_index: int in range(10):
			var angle: float = float(particle_index) * TAU / 10.0 + _time * 0.35
			var progress: float = fmod(_time * 1.4 + float(particle_index) / 10.0, 1.0)
			var distance: float = lerpf(attraction_radius, 5.0, progress)
			var direction: Vector2 = Vector2.from_angle(angle)
			var particle_point: Vector2 = _mouth_local + direction * distance
			draw_line(
				particle_point,
				particle_point + direction * 5.0,
				Color(accent, 0.35 + progress * 0.3),
				1.4,
				true
			)
	else:
		for arc_index: int in range(12):
			var angle: float = float(arc_index) * TAU / 12.0
			draw_arc(_mouth_local, radius, angle, angle + 0.25, 8, range_color, 1.1, true)
	for rib_index: int in range(1, 7):
		var progress: float = float(rib_index) / 7.0
		var start: Vector2 = _mouth_local + Vector2(-pipe_length, pipe_bend)
		var bend: Vector2 = _mouth_local + Vector2(-pipe_length * 0.55, pipe_bend)
		var end: Vector2 = _mouth_local + Vector2(-10.0, 0.0)
		var point: Vector2 = start.bezier_interpolate(bend, end, end, progress)
		draw_line(
			point + Vector2(0.0, -3.5), point + Vector2(0.0, 3.5), Color(ink, 0.40), 1.0, true
		)
