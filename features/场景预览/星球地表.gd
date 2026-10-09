@tool
extends PlanetSurface

@export var planet_art: Node2D


func set_near_blend(value: float) -> void:
	super.set_near_blend(value)
	# The same high-resolution sprite and animation phase serve both views.
	planet_art.scale = Vector2.ONE * radius / 240.0


func _draw() -> void:
	pass
