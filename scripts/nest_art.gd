extends Node2D

signal bounds_changed

const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const TRANSITIONS: Array[StringName] = [&"1-2", &"2-3", &"3-4"]
const SPAWN_CLIPS: Array[StringName] = [&"阶段1产怪", &"阶段2产怪", &"阶段3产怪"]

@export var slime_growth: ItemArt
@export var mucus_growth: ItemArt
@export var slime_flower: ItemArt
@export var mucus_flower: ItemArt
@export var slime_spawn: ItemArt
@export var mucus_spawn: ItemArt

static var _texture_bounds: Dictionary[Texture2D, Rect2] = {}

var _species: int = 0
var _display_level: int = 0
var _target_level: int = 0
var _transitioning: bool = false
var _spawning: bool = false
var _pending_spawn: bool = false
var _growth: ItemArt
var _flower: ItemArt
var _spawn: ItemArt
var _active_art: ItemArt
var _sprite: Sprite2D
var _bounds: Rect2


func _ready() -> void:
	for art: ItemArt in _get_art_items():
		art.animation_player.mixer_applied.connect(_refresh_bounds)
		art.clip_finished.connect(_on_clip_finished.bind(art))
	configure_species(0)


func configure_species(species: int) -> void:
	_species = species
	for art: ItemArt in _get_art_items():
		art.animation_player.stop()
		art.hide()
	_growth = slime_growth if species == 0 else mucus_growth
	_flower = slime_flower if species == 0 else mucus_flower
	_spawn = slime_spawn if species == 0 else mucus_spawn
	_transitioning = false
	_pending_spawn = false
	_display_level = _target_level
	_show_settled_stage()


func set_stage(level: int, animate: bool) -> void:
	_target_level = clampi(level, 0, 3)
	if not animate or _target_level < _display_level:
		_growth.animation_player.stop()
		_flower.animation_player.stop()
		_transitioning = false
		_pending_spawn = false
		_display_level = _target_level
		_show_settled_stage()
	elif not _transitioning and _display_level < _target_level:
		_play_next_upgrade()


func play_spawn() -> void:
	if _target_level == 3:
		return
	if _transitioning:
		_pending_spawn = true
		return
	# One population burst emits several requests; play its gesture only once.
	if _spawning:
		return
	_spawning = true
	_growth.hide()
	_flower.hide()
	_spawn.show()
	_active_art = _spawn
	_sprite = _spawn.get_node("画面/贴图") as Sprite2D
	_spawn.play_clip(SPAWN_CLIPS[_display_level])
	_refresh_bounds()


func play_production() -> void:
	if _transitioning or _display_level != 3:
		return
	# Faster automatic collections must not repeatedly restart the same first frame.
	if _flower.animation_player.current_animation != &"产出":
		_flower.play_clip(&"产出")


func get_art_bounds() -> Rect2:
	return _bounds


func get_maximum_footprint_width() -> float:
	var half_width: float = 0.0
	for art: ItemArt in _get_art_items():
		var sprite: Sprite2D = art.get_node("画面/贴图") as Sprite2D
		for clip: StringName in art.animation_player.get_animation_list():
			for frame: int in range(art.get_frame_count(clip)):
				art.show_frame(clip, frame)
				var bounds: Rect2 = _get_frame_bounds(art, sprite)
				half_width = maxf(half_width, maxf(absf(bounds.position.x), absf(bounds.end.x)))
	_show_settled_stage()
	return ceilf(half_width * 2.0)


func _get_art_items() -> Array[ItemArt]:
	return [slime_growth, mucus_growth, slime_flower, mucus_flower, slime_spawn, mucus_spawn]


func _play_next_upgrade() -> void:
	_transitioning = true
	_spawning = false
	_spawn.animation_player.stop()
	_spawn.hide()
	_flower.hide()
	_growth.show()
	_active_art = _growth
	_sprite = _growth.get_node("画面/贴图") as Sprite2D
	_growth.play_clip(TRANSITIONS[_display_level])
	if _species == 1 and _display_level == 2:
		# The first five source frames repeat the previous upgrade.
		_growth.animation_player.seek(5.0 / _growth.frames_per_second, true)
	_refresh_bounds()


func _show_settled_stage() -> void:
	_spawning = false
	_spawn.animation_player.stop()
	_spawn.hide()
	_growth.visible = _display_level < 3
	_flower.visible = _display_level == 3
	if _display_level == 3:
		_active_art = _flower
		_sprite = _flower.get_node("画面/贴图") as Sprite2D
		_flower.play_clip(&"待机")
	else:
		_active_art = _growth
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
			if _pending_spawn:
				_pending_spawn = false
				play_spawn()
	elif art == _spawn and _spawning:
		_show_settled_stage()
	elif art == _flower and clip == &"产出":
		_flower.play_clip(&"待机")


func _refresh_bounds() -> void:
	if _sprite == null:
		return
	var next_bounds: Rect2 = _get_frame_bounds(_active_art, _sprite)
	if not _bounds.is_equal_approx(next_bounds):
		_bounds = next_bounds
		bounds_changed.emit()


func _get_frame_bounds(art: ItemArt, sprite: Sprite2D) -> Rect2:
	var texture: Texture2D = sprite.texture
	if not _texture_bounds.has(texture):
		_texture_bounds[texture] = Rect2(texture.get_image().get_used_rect())
	var picture: Node2D = sprite.get_parent() as Node2D
	return art.transform * picture.transform * sprite.transform * _texture_bounds[texture]
