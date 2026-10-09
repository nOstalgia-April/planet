@tool
extends Node2D

@export_range(1.0, 16.0, 0.1) var half_width: float = 2.8
@export_range(1.0, 20.0, 0.5) var lifetime: float = 7.0
@export_range(8.0, 140.0, 0.1) var maximum_length: float = 28.8
@export_range(0.5, 8.0, 0.1) var sample_spacing: float = 1.0
@export var edge_color: Color = Color("344991")
@export var body_color: Color = Color("92b3ef")
@export var highlight_color: Color = Color("e6f1ff")

var source_nest_id: int = -1
var source_actor_id: int = 0
var surface: PlanetSurface
var remaining: float = 7.0
var anchors: PackedVector2Array = PackedVector2Array()

var _sample_times: PackedFloat32Array = PackedFloat32Array()
var _clock: float = 0.0
var _mesh_elapsed: float = 0.0
var _distance_offset: float = 0.0
var _ground_points: PackedVector2Array = PackedVector2Array()
var _hit_bounds: Rect2 = Rect2()
var _hit_vertices: PackedVector2Array = PackedVector2Array()
var _hit_colors: PackedColorArray = PackedColorArray()
var _hit_triangles: Array[PackedInt32Array] = []
var _hit_triangle_bounds: Array[Rect2] = []
var _triangle_indices: Array[PackedInt32Array] = []
var _strip_sources: Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array()
]
var _strip_vertices: Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array()
]
var _preview: bool = false
var _render_detail: bool = true

@onready var _edge: Polygon2D = $Outline
@onready var _ground: Polygon2D = $Ground
@onready var _highlight: Polygon2D = $Highlight


func _ready() -> void:
	# The ribbons already have soft vertex opacity; per-triangle antialiasing adds
	# overlapping feather geometry along every internal strip edge.
	_edge.antialiased = false
	_ground.antialiased = false
	_highlight.antialiased = false
	_preview = Engine.is_editor_hint() or get_tree().current_scene == self
	if not _preview:
		return
	if not Engine.is_editor_hint():
		position = get_viewport_rect().size * 0.5
		scale = Vector2.ONE * 5.0
	_clock = 2.0
	for index: int in range(25):
		var progress: float = float(index) / 24.0
		_ground_points.append(Vector2(lerpf(-36.0, 36.0, progress), sin(progress * TAU) * 8.0))
		_sample_times.append(progress * 2.0)
	_build_ribbon()


func configure(
	planet_surface: PlanetSurface,
	at: Vector2,
	nest_id: int,
	trail_half_width: float,
	seconds: float,
	length_limit: float = 28.8,
	spacing: float = 1.0
) -> void:
	assert(planet_surface != null)
	_preview = false
	surface = planet_surface
	source_nest_id = nest_id
	half_width = trail_half_width
	lifetime = seconds
	maximum_length = length_limit
	sample_spacing = spacing
	remaining = seconds
	_clock = 0.0
	_mesh_elapsed = float(source_actor_id % 13) / 13.0 * 0.05
	_distance_offset = 0.0
	anchors.clear()
	_ground_points.clear()
	_sample_times.clear()
	_clear_geometry_cache()
	append_ground_point(at)


func append_ground_point(at: Vector2, rebuild: bool = true) -> void:
	var anchor: Vector2 = _anchor_for_point(at)
	if anchors.is_empty():
		anchors.append(anchor)
		_ground_points.append(_point_for_anchor(anchor))
		_sample_times.append(_clock)
	elif anchors.size() == 1 and _ground_points[0].distance_to(at) < 0.2:
		_sample_times[0] = _clock
		return
	elif anchors.size() > 1 and _ground_points[-2].distance_to(at) < sample_spacing:
		anchors[anchors.size() - 1] = anchor
		_ground_points[_ground_points.size() - 1] = _point_for_anchor(anchor)
		_sample_times[_sample_times.size() - 1] = _clock
	else:
		_append_path_samples(at)
	remaining = lifetime
	_trim_length()
	if rebuild:
		_rebuild_surface()


func _append_path_samples(at: Vector2) -> void:
	var start: Vector2 = _ground_points[-1]
	var distance: float = start.distance_to(at)
	var inner: float = surface.get_activity_radius_bounds(start.angle()).x
	var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2.ZERO, start, at)
	var around_core: bool = nearest.length_squared() < inner * inner
	if around_core:
		distance = (
			absf(angle_difference(start.angle(), at.angle())) * maxf(start.length(), at.length())
			+ absf(start.length() - at.length())
		)
	var steps: int = maxi(1, int(ceil(distance / sample_spacing)))
	var start_time: float = _sample_times[_sample_times.size() - 1]
	for step: int in range(1, steps + 1):
		var fraction: float = float(step) / float(steps)
		var point: Vector2 = start.lerp(at, fraction)
		if around_core:
			point = (
				Vector2.from_angle(lerp_angle(start.angle(), at.angle(), fraction))
				* lerpf(start.length(), at.length(), fraction)
			)
		anchors.append(_anchor_for_point(point))
		_ground_points.append(_point_for_anchor(anchors[-1]))
		_sample_times.append(lerpf(start_time, _clock, fraction))


func advance(delta: float, rebuild: bool = true) -> bool:
	_clock += delta
	_mesh_elapsed += delta
	while not anchors.is_empty() and _clock - _sample_times[0] >= lifetime:
		if anchors.size() > 1:
			_distance_offset += _ground_points[0].distance_to(_ground_points[1])
		anchors.remove_at(0)
		_ground_points.remove_at(0)
		_sample_times.remove_at(0)
	if anchors.is_empty():
		remaining = 0.0
		return false
	remaining = maxf(0.0, lifetime - (_clock - _sample_times[_sample_times.size() - 1]))
	if rebuild:
		_rebuild_surface()
	return true


func get_ground_points() -> PackedVector2Array:
	return _ground_points


func contains_ground_point(point: Vector2) -> bool:
	if remaining <= 0.0 or _ground_points.size() < 2 or not _hit_bounds.has_point(point):
		return false
	var bounds: Vector2 = surface.get_activity_radius_bounds(point.angle())
	if point.length() < bounds.x or point.length() > bounds.y:
		return false
	for index: int in range(_hit_triangles.size()):
		if not _hit_triangle_bounds[index].has_point(point):
			continue
		var triangle: PackedInt32Array = _hit_triangles[index]
		var a: Vector2 = _hit_vertices[triangle[0]]
		var b: Vector2 = _hit_vertices[triangle[1]]
		var c: Vector2 = _hit_vertices[triangle[2]]
		var area: float = (b - a).cross(c - a)
		var weight_b: float = (point - a).cross(c - a) / area
		var weight_c: float = (b - a).cross(point - a) / area
		var weight_a: float = 1.0 - weight_b - weight_c
		if minf(weight_a, minf(weight_b, weight_c)) < -0.0001:
			continue
		var opacity: float = (
			_hit_colors[triangle[0]].a * weight_a
			+ _hit_colors[triangle[1]].a * weight_b
			+ _hit_colors[triangle[2]].a * weight_c
		)
		if opacity >= 0.18:
			return true
	return false


func is_detail_on_screen() -> bool:
	if not is_visible_in_tree():
		return false
	if _hit_bounds.size == Vector2.ZERO:
		return true
	# The margin covers movement between the 20 Hz contact-geometry updates.
	var viewport_bounds: Rect2 = (
		get_global_transform_with_canvas() * _hit_bounds.grow(half_width * 2.0)
	)
	return get_viewport_rect().intersects(viewport_bounds)


func refresh_surface(force: bool = true, render_detail: bool = true) -> void:
	var returning_to_view: bool = render_detail and not _render_detail
	if not force and _mesh_elapsed < 0.05 and not returning_to_view:
		return
	_render_detail = render_detail
	if force:
		# Only a surface geometry change invalidates historical projected anchors.
		_project_points()
		_clear_geometry_cache()
	_rebuild_surface()


func _rebuild_surface() -> void:
	_mesh_elapsed = fmod(_mesh_elapsed, 0.05)
	_build_ribbon()


func _clear_geometry_cache() -> void:
	for index: int in range(3):
		_strip_sources[index] = PackedVector2Array()
		_strip_vertices[index] = PackedVector2Array()


func _project_points() -> void:
	_ground_points.clear()
	for anchor: Vector2 in anchors:
		_ground_points.append(_point_for_anchor(anchor))


func _anchor_for_point(point: Vector2) -> Vector2:
	var bounds: Vector2 = surface.get_activity_radius_bounds(point.angle())
	return Vector2(
		point.angle(), clampf(inverse_lerp(bounds.x, bounds.y, point.length()), 0.0, 1.0)
	)


func _point_for_anchor(anchor: Vector2) -> Vector2:
	var bounds: Vector2 = surface.get_activity_radius_bounds(anchor.x)
	return Vector2.from_angle(anchor.x) * lerpf(bounds.x, bounds.y, anchor.y)


func _trim_length() -> void:
	var length: float = 0.0
	for index: int in range(_ground_points.size() - 1, 0, -1):
		length += _ground_points[index].distance_to(_ground_points[index - 1])
		if length > maximum_length:
			for old_index: int in range(index):
				_distance_offset += _ground_points[old_index].distance_to(
					_ground_points[old_index + 1]
				)
			for _old: int in range(index):
				anchors.remove_at(0)
				_sample_times.remove_at(0)
				_ground_points.remove_at(0)
			return


func _build_ribbon() -> void:
	# Strip connectivity depends on sample count, so share it between all three layers.
	var triangle_count: int = maxi(0, _ground_points.size() - 1) * 2
	while _triangle_indices.size() < triangle_count:
		var start: int = _triangle_indices.size()
		_triangle_indices.append(PackedInt32Array([start, start + 1, start + 2]))
		_triangle_indices.append(PackedInt32Array([start + 1, start + 3, start + 2]))
	var normals: PackedVector2Array = PackedVector2Array()
	var widths: PackedFloat32Array = PackedFloat32Array()
	var ages: PackedFloat32Array = PackedFloat32Array()
	var distances: PackedFloat32Array = PackedFloat32Array()
	var length: float = 0.0
	for index: int in range(_ground_points.size()):
		var previous: Vector2 = _ground_points[maxi(0, index - 1)]
		var next: Vector2 = _ground_points[mini(_ground_points.size() - 1, index + 1)]
		var tangent: Vector2 = (next - previous).normalized()
		if tangent.is_zero_approx():
			tangent = (_ground_points[index] - previous).normalized()
			if tangent.is_zero_approx():
				tangent = Vector2.RIGHT
		if index > 0:
			length += _ground_points[index].distance_to(previous)
		var fade: float = smoothstep(0.0, 1.5, lifetime - (_clock - _sample_times[index]))
		var taper: float = lerpf(0.12, 1.0, smoothstep(0.0, half_width * 3.0, length))
		var painted_distance: float = length + _distance_offset
		var painted_edge: float = (
			1.0 + sin(painted_distance * 0.38) * 0.07 + sin(painted_distance * 0.91) * 0.025
		)
		normals.append(Vector2(-tangent.y, tangent.x))
		widths.append(half_width * taper * painted_edge * sqrt(fade))
		ages.append(fade)
		distances.append(painted_distance)
	_write_strip(_edge, 0, normals, widths, ages, distances, -1.0, 1.0, edge_color)
	# Offscreen trails retain identical outline/contact geometry and lifetime.
	# Their two decorative layers and renderer uploads resume upon re-entry.
	if not _render_detail:
		return
	_write_strip(_ground, 1, normals, widths, ages, distances, -0.77, 0.77, body_color)
	_write_strip(_highlight, 2, normals, widths, ages, distances, -0.42, -0.22, highlight_color)


func _write_strip(
	polygon: Polygon2D,
	layer: int,
	normals: PackedVector2Array,
	widths: PackedFloat32Array,
	ages: PackedFloat32Array,
	distances: PackedFloat32Array,
	left: float,
	right: float,
	tint: Color
) -> void:
	var sources: PackedVector2Array = _strip_sources[layer]
	var vertices: PackedVector2Array = _strip_vertices[layer]
	var previous_size: int = sources.size()
	sources.resize(_ground_points.size() * 2)
	vertices.resize(_ground_points.size() * 2)
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(vertices.size())
	var triangles: Array[PackedInt32Array] = []
	for index: int in range(_ground_points.size()):
		var color: Color = tint
		color.a = ages[index] * 0.86
		if polygon == _ground:
			color = tint.lerp(Color("b9cff8"), 0.3 + sin(distances[index] * 0.16) * 0.18)
			color.a = ages[index] * 0.94
		elif polygon == _highlight:
			color.a *= smoothstep(-0.3, 0.7, sin(distances[index] * 0.19)) * 0.85
		for side_index: int in range(2):
			var side: float = left if side_index == 0 else right
			var vertex_index: int = index * 2 + side_index
			var point: Vector2 = _ground_points[index] + normals[index] * widths[index] * side
			if vertex_index >= previous_size or sources[vertex_index] != point:
				sources[vertex_index] = point
				vertices[vertex_index] = point if _preview else _clip_to_ground(point)
			colors[vertex_index] = color
		if index == 0:
			continue
		var start: int = (index - 1) * 2
		for triangle_index: int in range(start, start + 2):
			var indices: PackedInt32Array = _triangle_indices[triangle_index]
			var a: Vector2 = vertices[indices[0]]
			var b: Vector2 = vertices[indices[1]]
			var c: Vector2 = vertices[indices[2]]
			if absf((b - a).cross(c - a)) > 0.0001:
				triangles.append(indices)
	if _render_detail:
		polygon.visible = not triangles.is_empty()
		polygon.polygon = vertices
		polygon.vertex_colors = colors
		polygon.polygons = triangles
	_strip_sources[layer] = sources
	_strip_vertices[layer] = vertices
	if polygon == _edge and not vertices.is_empty():
		_hit_vertices = vertices
		_hit_colors = colors
		_hit_triangles = triangles
		_cache_hit_geometry()
		_hit_bounds = Rect2(vertices[0], Vector2.ZERO)
		for vertex: Vector2 in vertices:
			_hit_bounds = _hit_bounds.expand(vertex)
		_hit_bounds = _hit_bounds.grow(0.01)


func _cache_hit_geometry() -> void:
	_hit_triangle_bounds.resize(_hit_triangles.size())
	for index: int in range(_hit_triangles.size()):
		var triangle: PackedInt32Array = _hit_triangles[index]
		var a: Vector2 = _hit_vertices[triangle[0]]
		var b: Vector2 = _hit_vertices[triangle[1]]
		var c: Vector2 = _hit_vertices[triangle[2]]
		_hit_triangle_bounds[index] = Rect2(a, Vector2.ZERO).expand(b).expand(c).grow(0.01)


func _clip_to_ground(point: Vector2) -> Vector2:
	return surface.project_to_surface(point)
