@tool
extends Node2D

const SurfaceProjection = preload("res://scripts/surface_projection.gd")

@export var color: Color = Color("81b5a1")
@export var running: bool = true
var _phase: float = 0.0
var _pulse: float = 0.0
var presentation_scale: Vector2 = Vector2.ONE


func pulse() -> void:
	_pulse = 1.0


func _process(delta: float) -> void:
	_phase += delta
	_pulse = maxf(0.0, _pulse - delta * 2.5)
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	draw_set_transform_matrix(
		(
			SurfaceProjection.get_visual_compensation(self)
			* Transform2D(0.0, presentation_scale, 0.0, Vector2.ZERO)
		)
	)
	for side: float in [-1.0, 1.0]:
		var at: Vector2 = Vector2(side * 39.0, -25.0)
		draw_line(Vector2(side * 10.0, 8.0), at, Color("567d70"), 4.0, true)
		draw_circle(at, 11.0 + _pulse * 3.0, Color("eeeade"))
		draw_arc(at, 11.0, 0.0, TAU, 24, Color("456355"), 1.7, true)
		draw_circle(at, 7.0, color)
		for blade: int in range(3):
			var angle: float = _phase * 2.0 + TAU * float(blade) / 3.0
			draw_line(at, at + Vector2.from_angle(angle) * 6.0, Color("ecf7d9"), 2.0, true)
		if _pulse > 0.0:
			draw_arc(
				at,
				12.0 + (1.0 - _pulse) * 10.0,
				0.0,
				TAU,
				24,
				Color(color, _pulse * 0.6),
				1.0,
				true
			)
