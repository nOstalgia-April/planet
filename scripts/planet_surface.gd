@tool
class_name PlanetSurface
extends Node2D

@export_range(120.0, 600.0, 1.0) var radius: float = 240.0:
	set(value):
		radius = value
		queue_redraw()
@export var outline_color: Color = Color("454944")
@export var restored_color: Color = Color("a6bf8b")

var _restored: float = 0.0


func set_restored(value: float) -> void:
	_restored = clampf(value, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var sea_color: Color = Color("d4d7ce").lerp(Color("d4dfcb"), _restored)
	var earth_color: Color = Color("e6e5d9").lerp(restored_color, _restored)
	var rim_color: Color = Color("bfc0b2").lerp(Color("8da673"), _restored)
	var path_color: Color = Color("eeeddf").lerp(Color("c0d4a6"), _restored)
	draw_circle(Vector2(0.0, 23.0), radius * 1.10, Color(0.12, 0.15, 0.12, 0.12))
	draw_circle(Vector2(0.0, 12.0), radius * 1.07, rim_color)
	draw_arc(Vector2(0.0, 12.0), radius * 1.07, 0.0, TAU, 128, outline_color, 2.4, true)
	draw_circle(Vector2.ZERO, radius * 1.07, earth_color)
	draw_circle(Vector2.ZERO, radius * 0.73, sea_color)
	draw_arc(Vector2.ZERO, radius * 0.925, 0.0, TAU, 128, path_color, radius * 0.285, true)
	draw_arc(Vector2.ZERO, radius * 1.07, 0.0, TAU, 128, outline_color, 2.4, true)
	draw_arc(Vector2.ZERO, radius * 0.78, 0.0, TAU, 128, Color(0.30, 0.34, 0.29, 0.18), 1.5, true)
	_draw_land(
		PackedVector2Array(
			[
				Vector2(-0.54, -0.33),
				Vector2(-0.39, -0.55),
				Vector2(-0.15, -0.56),
				Vector2(-0.08, -0.35),
				Vector2(0.08, -0.24),
				Vector2(-0.04, -0.08),
				Vector2(-0.19, -0.09),
				Vector2(-0.30, 0.04),
				Vector2(-0.44, -0.12),
				Vector2(-0.58, -0.13),
			]
		),
		earth_color
	)
	_draw_land(
		PackedVector2Array(
			[
				Vector2(0.21, -0.36),
				Vector2(0.45, -0.41),
				Vector2(0.61, -0.20),
				Vector2(0.54, 0.06),
				Vector2(0.36, 0.12),
				Vector2(0.31, 0.33),
				Vector2(0.11, 0.47),
				Vector2(0.04, 0.26),
				Vector2(0.15, 0.04),
				Vector2(0.06, -0.15),
			]
		),
		earth_color
	)
	_draw_land(
		PackedVector2Array(
			[
				Vector2(-0.48, 0.28),
				Vector2(-0.32, 0.22),
				Vector2(-0.15, 0.39),
				Vector2(-0.23, 0.58),
				Vector2(-0.42, 0.54),
				Vector2(-0.53, 0.43),
			]
		),
		earth_color
	)
	var marks_color: Color = Color(0.30, 0.34, 0.29, 0.17)
	for mark_index: int in range(25):
		var angle: float = float(mark_index) * 2.399963
		var mark_radius: float = radius * (0.83 + 0.16 * float(mark_index % 4) / 3.0)
		var mark_position: Vector2 = Vector2.from_angle(angle) * mark_radius
		var tangent: Vector2 = Vector2.from_angle(angle + PI / 2.0)
		draw_line(
			mark_position - tangent * 3.0, mark_position + tangent * 3.0, marks_color, 1.5, true
		)
	for mark_index: int in range(7):
		var angle: float = float(mark_index) * 1.9
		var mark_position: Vector2 = Vector2.from_angle(angle) * radius * 0.59
		draw_arc(mark_position, 5.0, 0.0, PI, 10, marks_color, 1.2, true)


func _draw_land(points: PackedVector2Array, fill_color: Color) -> void:
	var scaled_points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		scaled_points.append(point * radius)
	draw_colored_polygon(scaled_points, fill_color)
	scaled_points.append(scaled_points[0])
	draw_polyline(scaled_points, Color(0.30, 0.34, 0.29, 0.28), 1.7, true)
