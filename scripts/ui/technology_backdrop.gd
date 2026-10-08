extends Control


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101e26"))
	for x: int in range(18, int(size.x), 28):
		for y: int in range(18, int(size.y), 28):
			draw_circle(Vector2(x, y), 0.7, Color("25363e"))
