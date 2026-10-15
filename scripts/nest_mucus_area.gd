@tool
extends Node2D

const SharedCache = preload("res://scripts/art_resource_cache.gd")

const FRAMES: SpriteFrames = preload("res://assets/ecology/nest_mucus/frames.tres")
const ALPHA_THRESHOLD: float = 0.1
const SOURCE_ROTATION: float = -0.3
# Anchors lie on the upper edge of each final pool after levelling the artwork.
const SOURCE_ANCHORS: Array[Vector2] = [
	Vector2(437.30284, -84.69500),
	Vector2(423.54558, -87.17630),
	Vector2(447.39352, -88.90106),
]
const SOURCE_WIDTHS: Array[float] = [757.07030, 819.80657, 802.17208]

var _alpha_masks: Dictionary[Texture2D, BitMap] = SharedCache.alpha_masks()

@export_enum("1", "2", "3") var variant_index: int = 0:
	set(value):
		variant_index = value
		_frame_index = 0
		_elapsed = 0.0
		if is_node_ready():
			refresh_surface()
			set_process(not Engine.is_editor_hint())
@export_range(0.04, 1.0, 0.01) var frame_seconds: float = 0.16
@export_range(0.0, 0.2, 0.005) var shore_overlap_ratio: float = 0.08:
	set(value):
		shore_overlap_ratio = value
		if is_node_ready():
			refresh_surface()
@export_range(8.0, 240.0, 0.1) var coverage_radius: float = 44.8:
	set(value):
		coverage_radius = value
		if is_node_ready():
			refresh_surface()

var source_nest_id: int = -1
var surface: PlanetSurface
var home_position: Vector2 = Vector2.ZERO
var _patches: Array[PackedVector2Array] = []
var _frame_index: int = 0
var _elapsed: float = 0.0
var _source_to_ground: Transform2D = Transform2D.IDENTITY
var _ground_to_source: Transform2D = Transform2D.IDENTITY
var _mask: BitMap

@onready var _outline: Polygon2D = $Outline


func _ready() -> void:
	if Engine.is_editor_hint() or get_tree().current_scene == self:
		if not Engine.is_editor_hint():
			position = get_viewport_rect().size * 0.5
			scale = Vector2.ONE * 4.0
		refresh_surface()
	set_process(not Engine.is_editor_hint())


func configure(
	planet_surface: PlanetSurface,
	at: Vector2,
	nest_id: int,
	radius: float,
	variant_override: int = -1
) -> void:
	assert(planet_surface != null)
	surface = planet_surface
	home_position = at
	source_nest_id = nest_id
	variant_index = variant_override if variant_override >= 0 else randi_range(0, 2)
	coverage_radius = radius


func _process(delta: float) -> void:
	_elapsed += delta
	var last_frame: int = FRAMES.get_frame_count(_animation()) - 1
	var next_frame: int = mini(int(_elapsed / frame_seconds), last_frame)
	if next_frame != _frame_index:
		_frame_index = next_frame
		refresh_surface()
	if _frame_index == last_frame:
		set_process(false)


func contains_ground_point(point: Vector2) -> bool:
	if _mask == null:
		return false
	var source_point: Vector2 = _ground_to_source * point
	var pixel: Vector2i = Vector2i(source_point.floor())
	var size: Vector2i = _mask.get_size()
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= size.x or pixel.y >= size.y:
		return false
	if not _mask.get_bitv(pixel):
		return false
	for patch: PackedVector2Array in _patches:
		if Geometry2D.is_point_in_polygon(point, patch):
			return true
	return false


func refresh_surface() -> void:
	var texture: Texture2D = FRAMES.get_frame_texture(_animation(), _frame_index)
	if not _alpha_masks.has(texture):
		var mask: BitMap = BitMap.new()
		mask.create_from_image_alpha(texture.get_image(), ALPHA_THRESHOLD)
		_alpha_masks[texture] = mask
	_mask = _alpha_masks[texture]
	_outline.texture = texture
	var inward: Vector2 = -home_position.normalized() if surface != null else Vector2.DOWN
	var tangent: Vector2 = Vector2(inward.y, -inward.x)
	var unit: float = coverage_radius * 2.0 / SOURCE_WIDTHS[variant_index]
	var cosine: float = cos(SOURCE_ROTATION)
	var sine: float = sin(SOURCE_ROTATION)
	var anchor: Vector2 = SOURCE_ANCHORS[variant_index]
	# Seat the painted upper edge beneath the nest's curved foot, then clip excess to soil.
	var origin: Vector2 = home_position - inward * coverage_radius * shore_overlap_ratio
	_source_to_ground = Transform2D(
		(tangent * cosine + inward * sine) * unit,
		(-tangent * sine + inward * cosine) * unit,
		origin - (tangent * anchor.x + inward * anchor.y) * unit
	)
	_ground_to_source = _source_to_ground.affine_inverse()
	var size: Vector2 = texture.get_size()
	var contour: PackedVector2Array = PackedVector2Array(
		[
			_source_to_ground * Vector2.ZERO,
			_source_to_ground * Vector2(size.x, 0.0),
			_source_to_ground * size,
			_source_to_ground * Vector2(0.0, size.y),
		]
	)
	_patches = _clip_to_crust(contour)
	_write_layer(_outline, _patches)


func _animation() -> StringName:
	return StringName("variant_%d" % (variant_index + 1))


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
	var uvs: PackedVector2Array = PackedVector2Array()
	var triangles: Array[PackedInt32Array] = []
	for patch: PackedVector2Array in patches:
		var offset: int = vertices.size()
		vertices.append_array(patch)
		for point: Vector2 in patch:
			uvs.append(_ground_to_source * point)
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(patch)
		for index: int in range(0, indices.size(), 3):
			(
				triangles
				. append(
					PackedInt32Array(
						[
							indices[index] + offset,
							indices[index + 1] + offset,
							indices[index + 2] + offset,
						]
					)
				)
			)
	layer.polygon = vertices
	layer.uv = uvs
	layer.polygons = triangles
	layer.visible = not triangles.is_empty()
