@tool
extends Node2D

const SharedCache = preload("res://scripts/art_resource_cache.gd")

@export_range(1.0, 16.0, 0.1) var half_width: float = 2.8
@export_range(1.0, 20.0, 0.5) var lifetime: float = 7.0
@export_range(8.0, 140.0, 0.1) var maximum_length: float = 28.8
@export_range(0.5, 8.0, 0.1) var sample_spacing: float = 1.0
@export_range(4.0, 100.0, 0.1) var texture_length: float = 32.0
@export_range(1.0, 4.0, 0.1) var spread_multiplier: float = 2.7
@export_range(0.1, 4.0, 0.1) var spread_seconds: float = 1.2
# Sample the continuous middle of each source, keeping its irregular painted edges.
@export var source_region: Rect2i = Rect2i(80, 144, 319, 48)
@export var source_white_background: bool = false
@export var tail_texture: Texture2D
@export var tail_source_region: Rect2i
@export_range(1.0, 20.0, 0.1) var tail_length: float = 12.0
var _source_edges: PackedVector2Array = PackedVector2Array()
var _tail_edges: PackedVector2Array = PackedVector2Array()
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
	if _edge.texture != null:
		_source_edges = _read_source_edges(_edge.texture, source_region, source_white_background)
	if tail_texture != null:
		_tail_edges = _read_source_edges(tail_texture, tail_source_region, false)
		_edge.set_instance_shader_parameter(
			"body_region", _normalized_region(source_region, _edge.texture)
		)
		_edge.set_instance_shader_parameter(
			"tail_region", _normalized_region(tail_source_region, tail_texture)
		)
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
	for index: int in range(97):
		var progress: float = float(index) / 96.0
		_ground_points.append(Vector2(lerpf(-36.0, 36.0, progress), sin(progress * TAU) * 8.0))
		_sample_times.append(progress * 2.0)
	_build_ribbon()


func _read_source_edges(
	texture: Texture2D, region: Rect2i, white_background: bool
) -> PackedVector2Array:
	var cache: Dictionary = SharedCache.get_cache(&"planet_mucus_edges")
	var source_key: String = "%s:%s:%s" % [texture.resource_path, region, white_background]
	var edges: PackedVector2Array = cache.get(source_key, PackedVector2Array())
	if edges.is_empty():
		var source: Image = texture.get_image()
		for x: int in range(region.position.x, region.end.x):
			var top: int = region.end.y - 1
			var bottom: int = region.position.y
			for y: int in range(region.position.y, region.end.y):
				var pixel: Color = source.get_pixel(x, y)
				var opacity: float = pixel.a
				if white_background:
					opacity *= smoothstep(0.025, 0.10, pixel.b - pixel.r)
				if opacity >= 0.18:
					top = mini(top, y)
					bottom = maxi(bottom, y)
			if top > bottom:
				top = region.position.y + region.size.y / 2
				bottom = top
			edges.append(Vector2(top + 0.5, bottom + 0.5))
		cache[source_key] = edges
	return edges


func _normalized_region(region: Rect2i, texture: Texture2D) -> Vector4:
	var size: Vector2 = texture.get_size()
	return Vector4(
		(region.position.x + 0.5) / size.x,
		(region.position.y + 0.5) / size.y,
		(region.size.x - 1.0) / size.x,
		(region.size.y - 1.0) / size.y
	)


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
	_render_detail = true
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


func reset_for_pool() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	surface = null
	source_nest_id = -1
	source_actor_id = 0
	remaining = 0.0
	anchors.clear()
	_ground_points.clear()
	_sample_times.clear()
	_hit_bounds = Rect2()
	_hit_vertices.clear()
	_hit_colors.clear()
	_hit_triangles.clear()
	_hit_triangle_bounds.clear()
	_clear_geometry_cache()
	for polygon: Polygon2D in [_edge, _ground, _highlight]:
		polygon.hide()
		polygon.polygons = []
		polygon.polygon = PackedVector2Array()
		polygon.uv = PackedVector2Array()
		polygon.vertex_colors = PackedColorArray()


func get_contact_bounds() -> Rect2:
	return _hit_bounds


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
	if returning_to_view:
		_clear_geometry_cache()
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
		var segment: float = _ground_points[index].distance_to(_ground_points[index - 1])
		length += segment
		if length > maximum_length:
			# Keep an interpolated boundary, so the tail moves continuously between samples.
			var cut: float = (length - maximum_length) / segment
			var boundary: Vector2 = _ground_points[index - 1].lerp(_ground_points[index], cut)
			var boundary_time: float = lerpf(_sample_times[index - 1], _sample_times[index], cut)
			for old_index: int in range(index - 1):
				_distance_offset += _ground_points[old_index].distance_to(
					_ground_points[old_index + 1]
				)
			_distance_offset += _ground_points[index - 1].distance_to(boundary)
			for _old: int in range(index - 1):
				anchors.remove_at(0)
				_sample_times.remove_at(0)
				_ground_points.remove_at(0)
			anchors[0] = _anchor_for_point(boundary)
			_ground_points[0] = _point_for_anchor(anchors[0])
			_sample_times[0] = boundary_time
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
		var age: float = _clock - _sample_times[index]
		var fade: float = smoothstep(0.0, 1.5, lifetime - age)
		var spread: float = lerpf(1.0, spread_multiplier, smoothstep(0.0, spread_seconds, age))
		var taper: float = lerpf(0.18, 1.0, smoothstep(0.0, half_width * 1.6, length))
		if tail_texture != null:
			taper = 1.0
		var painted_distance: float = length + _distance_offset
		var painted_edge: float = (
			1.0 + sin(painted_distance * 0.36) * 0.18 + sin(painted_distance * 0.79) * 0.09
		)
		if tail_texture != null:
			painted_edge = lerpf(1.0, painted_edge, smoothstep(0.0, tail_length, length))
		normals.append(Vector2(-tangent.y, tangent.x))
		widths.append(half_width * spread * taper * painted_edge * sqrt(fade))
		ages.append(fade)
		distances.append(painted_distance)
	_write_strip(_edge, 0, normals, widths, ages, distances, -1.0, 1.0, edge_color)
	# Offscreen trails retain contact geometry and lifetime without renderer uploads.
	if not _render_detail:
		return
	if _edge.texture != null:
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
	var uvs: PackedVector2Array = PackedVector2Array()
	var contact_vertices: PackedVector2Array = PackedVector2Array()
	contact_vertices.resize(vertices.size())
	var textured: bool = polygon.texture != null
	var has_tail: bool = tail_texture != null
	var texture_size: Vector2 = polygon.texture.get_size() if textured else Vector2.ZERO
	var source_half_height: float = float(source_region.size.y - 1) * 0.5
	var source_center_y: float = float(source_region.position.y) + source_half_height
	var tail_half_height: float = float(tail_source_region.size.y - 1) * 0.5
	if textured and _render_detail:
		uvs.resize(vertices.size())
	var triangles: Array[PackedInt32Array] = []
	for index: int in range(_ground_points.size()):
		var color: Color = tint
		if polygon.texture != null:
			color = Color.WHITE
		color.a = ages[index] * 0.86
		if polygon == _ground:
			color = tint.lerp(Color("b9cff8"), 0.3 + sin(distances[index] * 0.16) * 0.18)
			color.a = ages[index] * 0.94
		elif polygon == _highlight:
			color.a *= smoothstep(-0.3, 0.7, sin(distances[index] * 0.19)) * 0.85
		# Both sides use the same texture column, fade and tail blend. Compute
		# those once per sample rather than repeating them for every vertex.
		var source_x: float = 0.0
		var painted_sides: Vector2 = Vector2(left, right)
		var source_ys: Vector2 = Vector2.ZERO
		var edge_wave: float = sin(distances[index] * 0.27) * 0.16
		var distance_from_tail: float = distances[index] - distances[0]
		if textured:
			var along: float = 1.0 - absf(1.0 - fposmod(distances[index] / texture_length, 2.0))
			source_x = lerpf(float(source_region.position.x), float(source_region.end.x - 1), along)
			var column: int = clampi(
				roundi(source_x) - source_region.position.x, 0, _source_edges.size() - 1
			)
			source_ys = _source_edges[column]
			painted_sides = (source_ys - Vector2.ONE * source_center_y) / source_half_height
			if has_tail:
				var tail_progress: float = clampf(distance_from_tail / tail_length, 0.0, 1.0)
				var blend: float = smoothstep(0.55, 1.0, tail_progress)
				var tail_x: float = (
					tail_source_region.position.x
					+ tail_progress * float(tail_source_region.size.x - 1) * 0.5
				)
				var tail_column: int = clampi(
					roundi(tail_x) - tail_source_region.position.x, 0, _tail_edges.size() - 1
				)
				var tail_sides: Vector2 = (
					(
						_tail_edges[tail_column]
						- Vector2.ONE * tail_source_region.position.y
						- Vector2.ONE * tail_half_height
					)
					/ tail_half_height
				)
				painted_sides = Vector2(
					lerpf(tail_sides.x, painted_sides.x, blend),
					lerpf(tail_sides.y, painted_sides.y, blend)
				)
				color.a *= smoothstep(0.0, 0.08, tail_progress)
			painted_sides += Vector2.ONE * edge_wave
		for side_index: int in range(2):
			var vertex_index: int = index * 2 + side_index
			var point: Vector2 = (
				_ground_points[index] + normals[index] * widths[index] * painted_sides[side_index]
			)
			contact_vertices[vertex_index] = point if _preview else _clip_to_ground(point)
			colors[vertex_index] = color
			if not _render_detail:
				continue
			if has_tail:
				# Render the complete alpha silhouette; contact uses the painted edges.
				var full_side: float = (-1.0 if side_index == 0 else 1.0) + edge_wave
				point = _ground_points[index] + normals[index] * widths[index] * full_side
			if vertex_index >= previous_size or sources[vertex_index] != point:
				sources[vertex_index] = point
				vertices[vertex_index] = point if _preview else _clip_to_ground(point)
			if textured:
				uvs[vertex_index] = (
					Vector2(distance_from_tail * texture_size.x, side_index * texture_size.y)
					if has_tail
					else Vector2(source_x + 0.5, source_ys[side_index])
				)
		if index == 0:
			continue
		var start: int = (index - 1) * 2
		for triangle_index: int in range(start, start + 2):
			var indices: PackedInt32Array = _triangle_indices[triangle_index]
			var a: Vector2 = contact_vertices[indices[0]]
			var b: Vector2 = contact_vertices[indices[1]]
			var c: Vector2 = contact_vertices[indices[2]]
			if absf((b - a).cross(c - a)) > 0.0001:
				triangles.append(indices)
	if _render_detail:
		if tail_texture != null:
			polygon.set_instance_shader_parameter("path_offset", _distance_offset)
			polygon.set_instance_shader_parameter(
				"sample_lengths", Vector2(texture_length, tail_length)
			)
		polygon.visible = not triangles.is_empty()
		polygon.polygon = vertices
		polygon.vertex_colors = colors
		polygon.polygons = triangles
		if polygon.texture != null:
			polygon.uv = uvs
	_strip_sources[layer] = sources
	_strip_vertices[layer] = vertices
	if polygon == _edge and not vertices.is_empty():
		_hit_vertices = contact_vertices
		_hit_colors = colors
		_hit_triangles = triangles
		_cache_hit_geometry()
		_hit_bounds = Rect2(contact_vertices[0], Vector2.ZERO)
		for vertex: Vector2 in contact_vertices:
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


const SAVE_FIELDS: PackedStringArray = [
	"source_nest_id",
	"remaining",
	"anchors",
	"_sample_times",
	"_clock",
	"_distance_offset",
	"half_width",
	"lifetime",
	"maximum_length",
	"sample_spacing",
]
const SaveFields = preload("res://scripts/save_fields.gd")


func capture_save() -> Dictionary:
	return SaveFields.capture(self, SAVE_FIELDS)


func restore_save(data: Dictionary, planet_surface: PlanetSurface) -> void:
	surface = planet_surface
	_preview = false
	SaveFields.restore(self, data, SAVE_FIELDS)
	refresh_surface()
