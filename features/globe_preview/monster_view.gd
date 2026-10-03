extends Node2D

const REFERENCE_DISPLAY_HEIGHT: float = 76.0

var geographic_position: Vector3 = Vector3.FORWARD
var view_depth: float = 1.0
var monster_number: int = 0

var _alpha_mask: BitMap
var _base_scale: float = 1.0
var _projection_scale: float = 1.0
var _footprint_scale: float = 1.0
var _hovered: bool = false
var _selected: bool = false

@onready var _sprite: Sprite2D = $Artwork


func configure(texture: Texture2D, alpha_mask: BitMap, display_height: float) -> void:
	_alpha_mask = alpha_mask
	_footprint_scale = display_height / REFERENCE_DISPLAY_HEIGHT
	_sprite.texture = texture
	if texture != null:
		_base_scale = display_height / float(texture.get_height())
		_sprite.offset = Vector2(0.0, -float(texture.get_height()) * 0.5)
	_update_sprite_scale()
	queue_redraw()


func set_projected_position(
	screen_position: Vector2, depth: float, projection_scale: float = 1.0
) -> void:
	position = screen_position
	view_depth = depth
	_projection_scale = projection_scale
	visible = depth > 0.015
	modulate.a = smoothstep(0.015, 0.20, depth)
	z_index = int(screen_position.y)
	_update_sprite_scale()
	queue_redraw()


func set_feedback(hovered: bool, selected: bool) -> void:
	if hovered == _hovered and selected == _selected:
		return
	_hovered = hovered
	_selected = selected
	_update_sprite_scale()
	queue_redraw()


func contains_screen_point(screen_position: Vector2) -> bool:
	if not visible or modulate.a < 0.25 or _sprite.texture == null or _alpha_mask == null:
		return false
	var local_position: Vector2 = _sprite.to_local(screen_position)
	var artwork_rect: Rect2 = _sprite.get_rect()
	if not artwork_rect.has_point(local_position):
		return false
	var texture_position: Vector2i = Vector2i(local_position - artwork_rect.position)
	return _alpha_mask.get_bitv(texture_position)


func _update_sprite_scale() -> void:
	var depth_scale: float = lerpf(0.74, 1.0, maxf(0.0, view_depth))
	var feedback_scale: float = 1.08 if _hovered or _selected else 1.0
	_sprite.scale = Vector2.ONE * _base_scale * _projection_scale * depth_scale * feedback_scale


func _draw() -> void:
	var depth_scale: float = (
		lerpf(0.74, 1.0, maxf(0.0, view_depth)) * _projection_scale * _footprint_scale
	)
	draw_set_transform(Vector2(0.0, 2.0), 0.0, Vector2(1.0, 0.30))
	draw_circle(Vector2.ZERO, 17.0 * depth_scale, Color(0.13, 0.21, 0.18, 0.18))
	draw_circle(Vector2.ZERO, 10.0 * depth_scale, Color(0.10, 0.18, 0.15, 0.15))
	if _selected or _hovered:
		var ring_color: Color = Color("e9bc69") if _selected else Color("faf3d8")
		draw_arc(Vector2.ZERO, 22.0 * depth_scale, 0.0, TAU, 48, ring_color, 3.0, true)
	draw_set_transform(Vector2.ZERO)
