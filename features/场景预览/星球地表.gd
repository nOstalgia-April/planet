@tool
extends PlanetSurface

@export var near_art: Node2D
@export var overview_art: Node2D


func set_near_view(value: bool) -> bool:
	var changed: bool = super.set_near_view(value)
	near_art.visible = value
	overview_art.visible = not value
	near_art.scale = Vector2.ONE * radius / 240.0
	overview_art.scale = Vector2.ONE * radius / 240.0
	return changed


func _draw() -> void:
	pass
