extends Node2D


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.19))
	for layer: int in range(8, 0, -1):
		draw_circle(Vector2.ZERO, 155.0 + float(layer) * 10.0, Color(0.015, 0.028, 0.022, 0.055))
	draw_set_transform(Vector2.ZERO)
