extends Node2D

@export var surface: PlanetSurface


func _draw() -> void:
	draw_set_transform_matrix(surface.get_global_transform_with_canvas())
	var inner: float = surface.get_inner_radius(0.0)
	draw_arc(Vector2.ZERO, inner, 0.0, TAU, 256, Color(1.0, 0.74, 0.35, 0.85), 0.6, true)
	var outer: PackedVector2Array = surface.get_surface_polygon().duplicate()
	outer.append(outer[0])
	draw_polyline(outer, Color(0.45, 1.0, 0.73, 0.8), 0.5, true)
