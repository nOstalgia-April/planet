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
	assert(
		newly_covered != Vector2.ZERO, "The spreading edge reaches beyond the original 2.8 width."
	)
	assert(trail._hit_vertices != fresh, "The footprint grows over time, not only at creation.")
	assert(not trail.contains_ground_point(newly_covered + Vector2.DOWN * 12.0))
	trail.advance(5.7)
	assert(not trail.contains_ground_point(newly_covered), "Faded spread releases its old edge.")
	assert(not trail.advance(0.2), "Spread expires with the existing seven-second lifetime.")
	_check_length_boundary(surface)
	print(
		"PASS: mucus grows into adjacent ground, clear ground remains free, faded edges release, and history expires."
	)
	get_tree().quit()


func _check_length_boundary(surface: PlanetSurface) -> void:
	var trail: Trail = TRAIL_SCENE.instantiate() as Trail
	add_child(trail)
	trail.configure(surface, Vector2(-40.0, -200.0), 1, 2.8, 7.0, 28.8)
	trail.append_ground_point(Vector2(0.0, -200.0))
	assert(is_equal_approx(trail.get_ground_points()[0].x, -28.8))
	var previous_tail: Vector2 = trail.get_ground_points()[0]
	for step: int in range(1, 13):
		trail.append_ground_point(Vector2(step * 0.25, -200.0))
		var tail: Vector2 = trail.get_ground_points()[0]
		assert(
			absf(tail.x - previous_tail.x - 0.25) < 0.001,
			"Length clipping moves smoothly within a sample."
		)
		assert(absf(trail.get_ground_points()[-1].distance_to(tail) - 28.8) < 0.001)
		previous_tail = tail
	assert(trail._hit_colors[0].a == 0.0, "The oldest tip has no hard visible cut.")
	assert(
		not trail.contains_ground_point(previous_tail), "The transparent tip cannot trap a slime."
	)
	trail.queue_free()
