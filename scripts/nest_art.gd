extends Node2D

signal bounds_changed

const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const TRANSITIONS: Array[StringName] = [&"1-2", &"2-3", &"3-4"]

@export var slime_growth: ItemArt
@export var mucus_growth: ItemArt
@export var slime_flower: ItemArt
@export var mucus_flower: ItemArt

static var _texture_bounds: Dictionary[Texture2D, Rect2] = {}

var _species: int = 0
var _display_level: int = 0
var _target_level: int = 0
var _transitioning: bool = false
var _growth: ItemArt
var _flower: ItemArt
var _sprite: Sprite2D
var _bounds: Rect2


func _ready() -> void:
	for art: ItemArt in [slime_growth, mucus_growth, slime_flower, mucus_flower]:
		art.animation_player.mixer_applied.connect(_refresh_bounds)
		art.clip_finished.connect(_on_clip_finished.bind(art))
	configure_species(0)


func configure_species(species: int) -> void:
	_species = species
	for art: ItemArt in [slime_growth, mucus_growth, slime_flower, mucus_flower]:
		art.animation_player.stop()
		art.hide()
	_growth = slime_growth if species == 0 else mucus_growth
	_flower = slime_flower if species == 0 else mucus_flower
	_transitioning = false
	_display_level = _target_level
	_show_settled_stage()


func set_stage(level: int, animate: bool) -> void:
	_target_level = clampi(level, 0, 3)
	if not animate or _target_level < _display_level:
		_growth.animation_player.stop()
		_flower.animation_player.stop()
		_transitioning = false
		_display_level = _target_level
		_show_settled_stage()
	elif not _transitioning and _display_level < _target_level:
		_play_next_upgrade()


func play_production() -> void:
	if _transitioning or _display_level != 3:
		return
	# Faster automatic collections must not repeatedly restart the same first frame.
	if _flower.animation_player.current_animation != &"产出":
		_flower.play_clip(&"产出")


func get_art_bounds() -> Rect2:
	return _bounds


func _play_next_upgrade() -> void:
	_transitioning = true
	_flower.hide()
	_growth.show()
	_sprite = _growth.get_node("画面/贴图") as Sprite2D
	_growth.play_clip(TRANSITIONS[_display_level])
	if _species == 1 and _display_level == 2:
		# The first five source frames repeat the previous upgrade.
		_growth.animation_player.seek(5.0 / 8.0, true)
	_refresh_bounds()


func _show_settled_stage() -> void:
	_growth.visible = _display_level < 3
	_flower.visible = _display_level == 3
	if _display_level == 3:
		_sprite = _flower.get_node("画面/贴图") as Sprite2D
		_flower.play_clip(&"待机")
	else:
		_sprite = _growth.get_node("画面/贴图") as Sprite2D
		var clip: StringName = TRANSITIONS[maxi(0, _display_level - 1)]
		var frame: int = 0 if _display_level == 0 else _growth.get_frame_count(clip) - 1
		_growth.show_frame(clip, frame)
	_refresh_bounds()


func _on_clip_finished(clip: StringName, art: ItemArt) -> void:
	if art == _growth and _transitioning:
		_display_level += 1
		_transitioning = false
		if _display_level < _target_level:
			_play_next_upgrade()
		else:
			_show_settled_stage()
	elif art == _flower and clip == &"产出":
		_flower.play_clip(&"待机")


func _refresh_bounds() -> void:
	if _sprite == null:
		return
	var texture: Texture2D = _sprite.texture
	if not _texture_bounds.has(texture):
		_texture_bounds[texture] = Rect2(texture.get_image().get_used_rect())
	var art: ItemArt = _flower if _display_level == 3 and not _transitioning else _growth
	var picture: Node2D = _sprite.get_parent() as Node2D
	var next_bounds: Rect2 = (
		art.transform * picture.transform * _sprite.transform * _texture_bounds[texture]
	)
	if not _bounds.is_equal_approx(next_bounds):
		_bounds = next_bounds
		bounds_changed.emit()
