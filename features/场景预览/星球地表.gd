@tool
extends PlanetSurface

@export var planet_art: Node2D


func _ready() -> void:
	radius_changed.connect(_sync_art_scale)
	_sync_art_scale()


func get_outer_radius(_angle: float) -> float:
	# The formal artwork has a circular rim. Nests and their ground-bend profile
	# must follow that rim rather than the prototype's irregular relief.
	return radius * SURFACE_RADIUS_RATIO


func _sync_art_scale() -> void:
	planet_art.scale = Vector2.ONE * radius / 240.0
