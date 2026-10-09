extends Node2D

@export_range(8.0, 100.0, 0.1) var region_radius: float = 22.4

var surface: PlanetSurface
var home_position: Vector2 = Vector2.ZERO
var stage: int = 0:
	set(value):
		stage = value
		queue_redraw()
var species: int = 0:
	set(value):
		species = value
		queue_redraw()

var _patches: Array[PackedVector2Array] = []


func configure(planet_surface: PlanetSurface, at: Vector2) -> void:
	assert(planet_surface != null)
	surface = planet_surface
	home_position = at
	refresh_surface()


func refresh_surface() -> void:
	var circle: PackedVector2Array = PackedVector2Array()
	for index: int in range(48):
		circle.append(home_position + Vector2.from_angle(float(index) * TAU / 48.0) * region_radius)
	_patches.clear()
	for patch: PackedVector2Array in Geometry2D.intersect_polygons(circle, surface.get_surface_polygon()):
		_patches.append_array(Geometry2D.clip_polygons(patch, surface.get_inner_polygon()))
	queue_redraw()


func _draw() -> void:
	if surface == null:
		return
	var color: Color = Color("7398e5") if species == 1 else Color("e985b3")
	color = color.darkened(float(clampi(stage, 0, 3)) * 0.07)
	var opacity: float = 0.16 if surface._near_view else 0.65
	for patch: PackedVector2Array in _patches:
		draw_colored_polygon(patch, Color(color, opacity))
		var border: PackedVector2Array = patch.duplicate()
		border.append(border[0])
		draw_polyline(border, Color(color, opacity + 0.15), 1.2, true)
