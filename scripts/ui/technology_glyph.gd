extends Control

@export_range(0, 4) var symbol: int = 0
@export var ink: Color = Color("31594e")


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var unit: float = minf(size.x, size.y) / 48.0
	draw_set_transform(center, 0.0, Vector2.ONE * unit)
	match symbol:
		0:
			draw_polyline(
				PackedVector2Array([Vector2(-13, 12), Vector2(-13, -7), Vector2(10, -7)]),
				ink,
				11.0,
				true
			)
			draw_polyline(
				PackedVector2Array([Vector2(-13, 12), Vector2(-13, -7), Vector2(10, -7)]),
				Color("fbf7e9"),
				5.0,
				true
			)
			draw_line(Vector2(9, -14), Vector2(9, 0), ink, 4.0, true)
			draw_line(Vector2(-19, 12), Vector2(-7, 12), ink, 4.0, true)
			draw_line(Vector2(16, -11), Vector2(20, -13), ink, 2.0, true)
			draw_line(Vector2(16, -4), Vector2(21, -3), ink, 2.0, true)
		1:
			draw_arc(Vector2(3, -5), 13.0, 0, TAU, 32, ink, 3.0, true)
			draw_line(Vector2(-6, 5), Vector2(-17, 17), ink, 5.0, true)
			for offset: int in [-5, 1, 7]:
				draw_line(Vector2(-7, offset - 6), Vector2(13, offset - 6), ink, 1.0, true)
				draw_line(Vector2(offset, -16), Vector2(offset, 5), ink, 1.0, true)
		2:
			draw_line(Vector2(0, 15), Vector2(0, -7), ink, 3.0, true)
			draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(0, 3),
						Vector2(-13, -1),
						Vector2(-17, -13),
						Vector2(-5, -11),
						Vector2(0, -4)
					]
				),
				ink
			)
			draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(0, -2),
						Vector2(5, -12),
						Vector2(17, -16),
						Vector2(14, -3),
						Vector2(0, 5)
					]
				),
				ink
			)
			draw_line(Vector2(-12, 16), Vector2(12, 16), ink, 3.0, true)
		3:
			draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(2, -20),
						Vector2(-14, 3),
						Vector2(-2, 3),
						Vector2(-4, 20),
						Vector2(14, -4),
						Vector2(2, -4)
					]
				),
				ink
			)
		4:
			var gem: PackedVector2Array = PackedVector2Array(
				[
					Vector2(-9, -12),
					Vector2(9, -12),
					Vector2(17, -3),
					Vector2(0, 17),
					Vector2(-17, -3),
					Vector2(-9, -12)
				]
			)
			draw_polyline(gem, ink, 3.0, true)
			draw_line(Vector2(-16, -3), Vector2(16, -3), ink, 2.0, true)
			draw_polyline(
				PackedVector2Array([Vector2(-8, -12), Vector2(0, 16), Vector2(8, -12)]),
				ink,
				1.5,
				true
			)
