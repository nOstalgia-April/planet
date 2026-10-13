extends Node2D

const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
static var _texture_bounds: Dictionary[Texture2D, Rect2] = {}

@export var pink: ItemArt
@export var mucus: ItemArt
@export var valuable_pink: ItemArt
@export var valuable_mucus: ItemArt

var _active: ItemArt
var _sprite: Sprite2D


func _ready() -> void:
	pink.clip_finished.connect(_finish_jump)
	valuable_pink.clip_finished.connect(_finish_jump)
	configure_species(0)


func configure_species(species: int, valuable: bool = false) -> void:
	for art: ItemArt in [pink, mucus, valuable_pink, valuable_mucus]:
		art.hide()
		art.animation_player.stop()
	if valuable:
		_active = valuable_mucus if species == 1 else valuable_pink
	else:
		_active = mucus if species == 1 else pink
	_sprite = _active.get_node("画面/贴图") as Sprite2D
	_active.show()
	_active.animation_player.speed_scale = 1.0
	_active.play_clip(&"待机")


func play_launch(seconds: float) -> void:
	if _active == pink or _active == valuable_pink:
		_active.animation_player.speed_scale = (
			_active.animation_player.get_animation(&"跳跃").length / seconds
		)
		_active.play_clip(&"跳跃")


func restore_idle() -> void:
	_active.animation_player.speed_scale = 1.0
	_active.play_clip(&"待机")


func set_suction(active: bool) -> void:
	_active.set_suction(active)


func get_source_texture() -> Texture2D:
	return _sprite.texture


func get_art_bounds() -> Rect2:
	var texture: Texture2D = _sprite.texture
	if not _texture_bounds.has(texture):
		_texture_bounds[texture] = Rect2(texture.get_image().get_used_rect())
	var picture: Node2D = _sprite.get_parent() as Node2D
	return _active.transform * picture.transform * _sprite.transform * _texture_bounds[texture]


func _finish_jump(clip: StringName) -> void:
	if clip == &"跳跃" and (_active == pink or _active == valuable_pink):
		restore_idle()
