@tool
extends Node2D

const SurfaceProjection = preload("res://scripts/surface_projection.gd")

@export_range(8.0, 40.0, 1.0) var radius: float = 24.0
@export_range(0.2, 1.0, 0.05) var feedback_scale: float = 0.55
@export_range(1.0, 2.0, 0.05) var particle_spread: float = 1.5
@export_range(30.0, 100.0, 1.0) var pipe_length: float = 58.0
@export_range(0.0, 30.0, 1.0) var pipe_bend: float = 14.0
@export var ink: Color = Color("454944")
@export var accent: Color = Color("4c837c")
@export var active: bool = false

var _time: float = 0.0
var _mouth_local: Vector2 = Vector2.ZERO

@onready var _pipe_outline: Line2D = $PipeOutline
@onready var _pipe_fill: Line2D = $PipeFill
@onready var _mouth: Node2D = $Mouth


func _ready() -> void:
	_update_parts()


func set_tool_state(tool_position: Vector2, mouth_position: Vector2, is_active: bool) -> void:
	position = tool_position
	if not tool_position.is_zero_approx():
		rotation = tool_position.angle() + PI
	_mouth_local = (mouth_position - tool_position).rotated(-rotation)
	active = is_active
	_update_parts()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if Engine.is_editor_hint():
		_update_parts()
	else:
		_update_visual_compensation()
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
	_update_visual_compensation()


func _update_visual_compensation() -> void:
	var compensation: Transform2D = SurfaceProjection.get_visual_compensation(self)
	var pipe_transform: Transform2D = compensation
	pipe_transform.origin = _mouth_local - compensation.basis_xform(_mouth_local)
	_pipe_outline.transform = pipe_transform
	_pipe_fill.transform = pipe_transform
	compensation.origin = _mouth_local
	_mouth.transform = compensation


func _draw() -> void:
	if active:
		var feedback_radius: float = radius * feedback_scale
		draw_circle(_mouth_local, feedback_radius, Color(accent, 0.10))
		draw_arc(_mouth_local, feedback_radius, 0.0, TAU, 48, Color(accent, 0.65), 1.3, true)
		for particle_index: int in range(6):
			var angle: float = float(particle_index) * TAU / 6.0 + _time * 0.35
			var progress: float = fmod(_time * 1.4 + float(particle_index) / 6.0, 1.0)
			var distance: float = lerpf(feedback_radius * particle_spread, 3.0, progress)
			var direction: Vector2 = Vector2.from_angle(angle)
			var particle_point: Vector2 = _mouth_local + direction * distance
			draw_line(
				particle_point,
				particle_point + direction * 2.0,
				Color(accent, 0.35 + progress * 0.3),
				1.0,
				true
			)
	var compensation: Transform2D = SurfaceProjection.get_visual_compensation(self)
	compensation.origin = _mouth_local - compensation.basis_xform(_mouth_local)
	draw_set_transform_matrix(compensation)
	for rib_index: int in range(1, 7):
		var progress: float = float(rib_index) / 7.0
		var start: Vector2 = _mouth_local + Vector2(-pipe_length, pipe_bend)
		var bend: Vector2 = _mouth_local + Vector2(-pipe_length * 0.55, pipe_bend)
		var end: Vector2 = _mouth_local + Vector2(-10.0, 0.0)
		var point: Vector2 = start.bezier_interpolate(bend, end, end, progress)
		draw_line(
			point + Vector2(0.0, -3.5), point + Vector2(0.0, 3.5), Color(ink, 0.40), 1.0, true
		)
