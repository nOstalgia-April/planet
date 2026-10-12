extends Node

const Trail = preload("res://scripts/mucus_field.gd")
const TRAIL_SCENE: PackedScene = preload("res://scenes/effects/mucus_field.tscn")


func _ready() -> void:
	var surface: PlanetSurface = PlanetSurface.new()
	add_child(surface)
	var trail: Trail = TRAIL_SCENE.instantiate() as Trail
	add_child(trail)
	trail.configure(surface, Vector2(-14.0, -200.0), 1, 2.8, 7.0)
	trail.append_ground_point(Vector2(14.0, -200.0))
	var fresh: PackedVector2Array = trail._hit_vertices.duplicate()
	trail.advance(trail.spread_seconds)
	var newly_covered: Vector2 = Vector2.ZERO
	for x: int in range(-6, 8):
		for y: int in range(3, 7):
			var point: Vector2 = Vector2(x, -200.0 + y)
			if trail.contains_ground_point(point):
				newly_covered = point
	assert(newly_covered != Vector2.ZERO, "The spreading edge reaches beyond the original 2.8 width.")
	assert(trail._hit_vertices != fresh, "The footprint grows over time, not only at creation.")
	assert(not trail.contains_ground_point(newly_covered + Vector2.DOWN * 12.0))
	trail.advance(5.7)
	assert(not trail.contains_ground_point(newly_covered), "Faded spread releases its old edge.")
	assert(not trail.advance(0.2), "Spread expires with the existing seven-second lifetime.")
	print("PASS: mucus grows into adjacent ground, clear ground remains free, faded edges release, and history expires.")
	get_tree().quit()
