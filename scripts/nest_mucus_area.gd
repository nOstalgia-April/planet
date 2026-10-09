@tool
extends Node2D

@export_range(8.0, 240.0, 0.1) var coverage_radius: float = 44.8:
	set(value):
		coverage_radius = value
		if is_node_ready():
			refresh_surface()

var source_nest_id: int = -1
var surface: PlanetSurface
var home_position: Vector2 = Vector2.ZERO
var _patches: Array[PackedVector2Array] = []

@onready var _outline: Polygon2D = $Outline
@onready var _ground: Polygon2D = $Ground
@onready var _sheen: Polygon2D = $Sheen


func _ready() -> void:
	if Engine.is_editor_hint() or get_tree().current_scene == self:
		if not Engine.is_editor_hint():
			position = get_viewport_rect().size * 0.5
			scale = Vector2.ONE * 2.5
		refresh_surface()


func configure(planet_surface: PlanetSurface, at: Vector2, nest_id: int, radius: float) -> void:
	assert(planet_surface != null)
	surface = planet_surface
	home_position = at
	source_nest_id = nest_id
	coverage_radius = radius


func contains_ground_point(point: Vector2) -> bool:
	if point.distance_squared_to(home_position) > coverage_radius * coverage_radius:
		return false
	var bounds: Vector2 = surface.get_activity_radius_bounds(point.angle())
	if point.length() < bounds.x or point.length() > bounds.y:
		return false
	for patch: PackedVector2Array in _patches:
		if Geometry2D.is_point_in_polygon(point, patch):
			return true
	return false


func refresh_surface() -> void:
	_patches = _clip_to_crust(_make_pool(1.0))
	_write_layer(_outline, _patches)
	_write_layer(_ground, _clip_to_crust(_make_pool(0.98)))
	var highlights: Array[PackedVector2Array] = []
	var inward_angle: float = (-home_position).angle() if surface != null else PI / 2.0
	for band: int in range(2):
		var sheen: PackedVector2Array = PackedVector2Array()
		var distance: float = coverage_radius * (0.58 + float(band) * 0.24)
		var angle_start: float = inward_angle - 1.1 + float(band) * 0.25
		for side: int in range(2):
			for index: int in range(25):
				var fraction: float = float(index if side == 0 else 24 - index) / 24.0
				var width: float = sin(fraction * PI) * coverage_radius * 0.025
				var angle: float = angle_start + fraction * 1.55
				sheen.append(
					(
						home_position
						+ (
							Vector2.from_angle(angle)
							* (distance + width * (-1.0 if side == 0 else 1.0))
						)
					)
				)
		highlights.append_array(_clip_to_crust(sheen))
	_write_layer(_sheen, highlights)


func _make_pool(size_ratio: float) -> PackedVector2Array:
	var contour: PackedVector2Array = PackedVector2Array()
	var phase: float = float(maxi(0, source_nest_id)) * 0.7
	for index: int in range(96):
		var angle: float = float(index) * TAU / 96.0
		var edge: float = 0.975 + sin(angle * 5.0 + phase) * 0.015 + sin(angle * 9.0) * 0.01
		contour.append(
			home_position + Vector2.from_angle(angle) * coverage_radius * size_ratio * edge
		)
	return contour


func _clip_to_crust(contour: PackedVector2Array) -> Array[PackedVector2Array]:
	var patches: Array[PackedVector2Array] = []
	if surface == null:
		patches.append(contour)
		return patches
	var intersections: Array[PackedVector2Array] = Geometry2D.intersect_polygons(
		contour, surface.get_surface_polygon()
	)
	for patch: PackedVector2Array in intersections:
		patches.append_array(Geometry2D.clip_polygons(patch, surface.get_inner_polygon()))
	return patches


func _write_layer(layer: Polygon2D, patches: Array[PackedVector2Array]) -> void:
	var vertices: PackedVector2Array = PackedVector2Array()
	var triangles: Array[PackedInt32Array] = []
	for patch: PackedVector2Array in patches:
		var offset: int = vertices.size()
		vertices.append_array(patch)
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(patch)
		for index: int in range(0, indices.size(), 3):
			triangles.append(
				PackedInt32Array(
					[
						indices[index] + offset,
						indices[index + 1] + offset,
						indices[index + 2] + offset
					]
				)
			)
	layer.polygon = vertices
	layer.polygons = triangles
	layer.visible = not triangles.is_empty()
