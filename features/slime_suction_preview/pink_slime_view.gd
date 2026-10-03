@tool
extends Node2D

@export var monster_texture: Texture2D:
	set(value):
		monster_texture = value
		if is_node_ready():
			_configure_artwork()
@export_range(12.0, 100.0, 1.0) var display_height: float = 44.0
@export_range(0.0, 0.8, 0.01) var width_compression: float = 0.37
@export_range(0.0, 1.2, 0.01) var height_stretch: float = 0.60
@export_range(0.0, 1.0, 0.01) var preview_capture_progress: float = 0.0
@export_range(0.0, 1.0, 0.01) var preview_attraction_strength: float = 0.0

var _texture_height: float = 1.0
var _editor_elapsed: float = 0.0

@onready var _shadow: Polygon2D = $Shadow
@onready var _deformation: Node2D = $Deformation
@onready var _artwork: Sprite2D = $Deformation/Artwork


func _ready() -> void:
	assert(monster_texture != null, "Pink slime preview requires a texture.")
	_configure_artwork()
	var shadow_points: PackedVector2Array = PackedVector2Array()
	for index in range(40):
		shadow_points.append(Vector2.from_angle(float(index) * TAU / 40.0))
	_shadow.polygon = shadow_points
	show_pose(preview_capture_progress, preview_attraction_strength, Vector2.ZERO, 0.0)
	set_process(Engine.is_editor_hint())


func _process(delta: float) -> void:
	_editor_elapsed += delta
	show_pose(
		preview_capture_progress,
		preview_attraction_strength,
		Vector2(7.0, 0.0) * preview_attraction_strength,
		_editor_elapsed
	)


func _configure_artwork() -> void:
	assert(monster_texture != null, "Pink slime preview requires a texture.")
	var source_image: Image = monster_texture.get_image()
	var alpha_mask: BitMap = BitMap.new()
	alpha_mask.create_from_image_alpha(source_image, 0.16)
	var used_rect: Rect2i = _content_rect(alpha_mask, source_image.get_used_rect())
	assert(used_rect.has_area(), "Pink slime texture must contain visible pixels.")
	_artwork.texture = monster_texture
	_artwork.region_enabled = true
	_artwork.region_rect = Rect2(used_rect)
	_texture_height = float(used_rect.size.y)
	_artwork.offset = Vector2(0.0, -_texture_height * 0.5)


func _content_rect(alpha_mask: BitMap, initial_rect: Rect2i) -> Rect2i:
	var top: int = initial_rect.position.y
	var bottom: int = initial_rect.end.y - 1
	var left: int = initial_rect.position.x
	var right: int = initial_rect.end.x - 1
	while top <= bottom and not _row_has_alpha(alpha_mask, top, left, right):
		top += 1
	while bottom >= top and not _row_has_alpha(alpha_mask, bottom, left, right):
		bottom -= 1
	while left <= right and not _column_has_alpha(alpha_mask, left, top, bottom):
		left += 1
	while right >= left and not _column_has_alpha(alpha_mask, right, top, bottom):
		right -= 1
	return Rect2i(left, top, maxi(0, right - left + 1), maxi(0, bottom - top + 1))


func _row_has_alpha(alpha_mask: BitMap, row: int, left: int, right: int) -> bool:
	for column in range(left, right + 1):
		if alpha_mask.get_bitv(Vector2i(column, row)):
			return true
	return false


func _column_has_alpha(alpha_mask: BitMap, column: int, top: int, bottom: int) -> bool:
	for row in range(top, bottom + 1):
		if alpha_mask.get_bitv(Vector2i(column, row)):
			return true
	return false


func show_pose(
	capture_progress: float, attraction_strength: float, pull_offset: Vector2, elapsed: float
) -> void:
	var progress: float = clampf(capture_progress, 0.0, 1.0)
	var strength: float = clampf(attraction_strength, 0.0, 1.0)
	var bounce: float = sin(elapsed * 4.5)
	var squash: float = bounce * 0.045
	var body_scale: Vector2 = Vector2(
		1.0 + squash - progress * width_compression, 1.0 - squash + progress * height_stretch
	)
	var attraction_scale: Vector2 = Vector2(1.0 - strength * 0.05, 1.0 + strength * 0.12)
	_artwork.scale = body_scale * attraction_scale * display_height / _texture_height
	_deformation.position = pull_offset + Vector2(0.0, -maxf(0.0, bounce) * 2.0)
	_deformation.rotation = pull_offset.x * 0.012
	_shadow.position = pull_offset * 0.15 + Vector2(0.0, 1.0)
	_shadow.scale = Vector2(display_height * 0.43, display_height * 0.065)
	_shadow.color = Color(0.20, 0.22, 0.19, 0.12 * (1.0 - progress * 0.6))


func get_capture_point() -> Vector2:
	return position + Vector2(0.0, -display_height * 0.45)
