extends Node2D

const SharedCache = preload("res://scripts/art_resource_cache.gd")

const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
var _texture_bounds: Dictionary[Texture2D, Rect2] = SharedCache.texture_bounds(
	&"planet_slime_art_bounds"
)

@export var pink: ItemArt
@export var mucus: ItemArt
@export var valuable_pink: ItemArt
@export var valuable_mucus: ItemArt

var _active: ItemArt
var _sprite: Sprite2D
var _simulation_speed: float = 1.0
var _clip_speed: float = 1.0


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
	_clip_speed = 1.0
	_active.animation_player.speed_scale = _simulation_speed
	_active.play_clip(&"待机")


func play_launch(seconds: float) -> void:
	if _active == pink or _active == valuable_pink:
		_clip_speed = (_active.animation_player.get_animation(&"跳跃").length / seconds)
		_active.animation_player.speed_scale = _clip_speed * _simulation_speed
		_active.play_clip(&"跳跃")


func restore_idle() -> void:
	_clip_speed = 1.0
	_active.animation_player.speed_scale = _simulation_speed
	_active.play_clip(&"待机")


func set_simulation_speed(value: float) -> void:
	_simulation_speed = value
	_active.animation_player.speed_scale = _clip_speed * value


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
