extends Node2D

signal bounds_changed
signal flower_appeared

const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const GroundBend: ShaderMaterial = preload("res://resources/nest_ground_bend.tres")
const GROUND_SAMPLES: int = 256
const TRANSITIONS: Array[StringName] = [&"1-2", &"2-3", &"3-4"]
const SPAWN_CLIPS: Array[StringName] = [&"阶段1产怪", &"阶段2产怪", &"阶段3产怪"]

@export var slime_growth: ItemArt
@export var mucus_growth: ItemArt
@export var slime_flower: ItemArt
@export var mucus_flower: ItemArt
@export var slime_spawn: ItemArt
@export var mucus_spawn: ItemArt
@export var drill_growth: ItemArt
@export var drill_flower: ItemArt
@export var drill_spawn: ItemArt

static var _texture_bounds: Dictionary[Texture2D, Rect2] = {}
static var _texture_feet: Dictionary[Texture2D, ImageTexture] = {}

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
var _bend_material: ShaderMaterial = GroundBend.duplicate() as ShaderMaterial
var _ground_curve: Vector3 = Vector3(-1000.0, 0.0, 0.0)
var _bend_height_ratio: float = 0.35
var _bottom_padding: float = 0.0
var _ground_profile: ImageTexture
var _ground_heights: PackedFloat32Array = PackedFloat32Array()
var _ground_max_y: float = 0.0
var _flower_announced: bool = false
var _emergence_progress: float = 1.0


func _ready() -> void:
	for art: ItemArt in _get_art_items():
		var sprite: Sprite2D = art.get_node("画面/贴图") as Sprite2D
		if art not in [slime_flower, mucus_flower, drill_flower]:
			sprite.material = _bend_material
		art.animation_player.mixer_applied.connect(_refresh_bounds)
		art.clip_finished.connect(_on_clip_finished.bind(art))
	configure_species(0)


func configure_species(species: int) -> void:
	_species = species
	for art: ItemArt in _get_art_items():
		art.animation_player.stop()
		art.hide()
	_growth = [slime_growth, mucus_growth, drill_growth][species]
	_flower = [slime_flower, mucus_flower, drill_flower][species]
	_spawn = [slime_spawn, mucus_spawn, drill_spawn][species]
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


func set_emergence_progress(progress: float) -> void:
	_emergence_progress = clampf(progress, 0.0, 1.0)
	_bend_material.set_shader_parameter("emergence_progress", _emergence_progress)


func uses_ground_bend() -> bool:
	return _active_art != _flower


func set_ground_curve(curve: Vector3, height_ratio: float) -> Rect2:
	_ground_curve = curve
	_bend_height_ratio = height_ratio
	_bottom_padding = maxf(_get_ground_bend(_bounds.position.x), _get_ground_bend(_bounds.end.x))
	_refresh_bend_material()
	return Rect2(_bounds.position, _bounds.size + Vector2(0.0, _bottom_padding))


func set_ground_contour(contour: PackedVector2Array) -> void:
	_ground_heights.resize(GROUND_SAMPLES)
	_ground_heights.fill(INF)
	var step: float = _bounds.size.x / float(GROUND_SAMPLES - 1)
	# Rasterize the actual polygon's upper edge into a one-dimensional height map.
	for index: int in range(contour.size()):
		var start: Vector2 = contour[index]
		var finish: Vector2 = contour[(index + 1) % contour.size()]
		if is_equal_approx(start.x, finish.x):
			continue
		var first: int = maxi(0, ceili((minf(start.x, finish.x) - _bounds.position.x) / step))
		var last: int = mini(GROUND_SAMPLES - 1, floori((maxf(start.x, finish.x) - _bounds.position.x) / step))
		for sample: int in range(first, last + 1):
			var x: float = _bounds.position.x + float(sample) * step
			var y: float = lerpf(start.y, finish.y, (x - start.x) / (finish.x - start.x))
			_ground_heights[sample] = minf(_ground_heights[sample], y)
	var profile: Image = Image.create(GROUND_SAMPLES, 1, false, Image.FORMAT_RF)
	_ground_max_y = _bounds.end.y
	for sample: int in range(GROUND_SAMPLES):
		if not is_finite(_ground_heights[sample]):
			_ground_heights[sample] = _bounds.end.y + _get_ground_bend(_bounds.position.x + float(sample) * step)
		_ground_max_y = maxf(_ground_max_y, _ground_heights[sample])
		profile.set_pixel(sample, 0, Color(_ground_heights[sample], 0.0, 0.0))
	if _ground_profile == null:
		_ground_profile = ImageTexture.create_from_image(profile)
	else:
		_ground_profile.update(profile)
	_bend_material.set_shader_parameter("ground_profile", _ground_profile)
	_bend_material.set_shader_parameter("ground_span", Vector2(_bounds.position.x, _bounds.size.x))


func clear_ground_contour() -> void:
	_ground_heights.clear()
	_bend_material.set_shader_parameter("follow_contour", false)


func get_grounded_bounds() -> Rect2:
	# Slight overlap covers antialiasing at the ground's edge without a visible seam.
	var overlap: float = 1.25 / get_global_transform_with_canvas().y.length()
	_bottom_padding = maxf(0.0, _ground_max_y + overlap - _bounds.end.y)
	_bend_material.set_shader_parameter("follow_contour", true)
	_bend_material.set_shader_parameter("ground_overlap", overlap)
	_bend_material.set_shader_parameter("bottom_padding", _bottom_padding)
	return Rect2(_bounds.position, _bounds.size + Vector2(0.0, _bottom_padding))


func get_ground_contact_y(x: float) -> float:
	if _ground_heights.is_empty():
		return _bounds.end.y + _get_ground_bend(x)
	var sample: float = clampf((x - _bounds.position.x) / _bounds.size.x, 0.0, 1.0) * float(GROUND_SAMPLES - 1)
	var index: int = mini(floori(sample), GROUND_SAMPLES - 2)
	return lerpf(_ground_heights[index], _ground_heights[index + 1], sample - float(index))


func _get_ground_bend(x: float) -> float:
	var b: float = _ground_curve.x + _ground_curve.y * x
	var c: float = _ground_curve.z * x * x
	return c / maxf(-b + sqrt(maxf(b * b - c, 0.0)), 0.0001)


func _refresh_bend_material() -> void:
	if _sprite == null or not uses_ground_bend():
		return
	var picture: Node2D = _sprite.get_parent() as Node2D
	var frame_transform: Transform2D = _active_art.transform * picture.transform * _sprite.transform
	_bend_material.set_shader_parameter("sprite_to_art", _shader_matrix(frame_transform))
	_bend_material.set_shader_parameter("art_to_sprite", _shader_matrix(frame_transform.affine_inverse()))
	_bend_material.set_shader_parameter("sprite_rect_origin", _sprite.get_rect().position)
	_bend_material.set_shader_parameter("ground_curve", _ground_curve)
	_bend_material.set_shader_parameter("contact_y", _bounds.end.y)
	_bend_material.set_shader_parameter("emergence_height", _bounds.size.y)
	_bend_material.set_shader_parameter("emergence_width", _bounds.size.x)
	_bend_material.set_shader_parameter("emergence_center_x", _bounds.get_center().x)
	_bend_material.set_shader_parameter("bend_height", maxf(1.0, _bounds.size.y * _bend_height_ratio))
	_bend_material.set_shader_parameter("bottom_padding", _bottom_padding)
	_bend_material.set_shader_parameter("foot_profile", _get_foot_profile(_sprite.texture))


func _get_foot_profile(texture: Texture2D) -> ImageTexture:
	if _texture_feet.has(texture):
		return _texture_feet[texture]
	var source: Image = texture.get_image()
	var used: Rect2i = source.get_used_rect()
	var profile: Image = Image.create(source.get_width(), 1, false, Image.FORMAT_RGF)
	var feet: PackedFloat32Array = PackedFloat32Array()
	feet.resize(source.get_width())
	feet.fill(-1.0)
	for x: int in range(used.position.x, used.end.x):
		for y: int in range(used.end.y - 1, used.position.y - 1, -1):
			if source.get_pixel(x, y).a >= 0.75:
				feet[x] = float(y) + 0.5
				break
	var radius: int = clampi(roundi(float(used.size.x) * 0.025), 4, 16)
	var inset_feet: PackedFloat32Array = feet.duplicate()
	# First inset the footprint, then smooth it. The wider minimum window ensures
	# the smoothed anchor stays inside the opaque base so ground clipping leaves no gap.
	for x: int in range(used.position.x, used.end.x):
		if feet[x] < 0.0:
			continue
		for neighbor: int in range(maxi(used.position.x, x - radius * 2), mini(used.end.x, x + radius * 2 + 1)):
			if feet[neighbor] >= 0.0:
				inset_feet[x] = minf(inset_feet[x], feet[neighbor])
	for x: int in range(used.position.x, used.end.x):
		if feet[x] < 0.0:
			continue
		var weighted_height: float = 0.0
		var total_weight: float = 0.0
		for neighbor: int in range(maxi(used.position.x, x - radius), mini(used.end.x, x + radius + 1)):
			if inset_feet[neighbor] < 0.0:
				continue
			var weight: float = float(radius + 1 - absi(neighbor - x))
			weighted_height += inset_feet[neighbor] * weight
			total_weight += weight
		profile.set_pixel(x, 0, Color(weighted_height / total_weight, 1.0, 0.0))
	_texture_feet[texture] = ImageTexture.create_from_image(profile)
	return _texture_feet[texture]


func _shader_matrix(value: Transform2D) -> Basis:
	# Shader mat3 uniforms accept Basis, including the explicit 2D translation column.
	return Basis(
		Vector3(value.x.x, value.x.y, 0.0),
		Vector3(value.y.x, value.y.y, 0.0),
		Vector3(value.origin.x, value.origin.y, 1.0)
	)


func get_source_texture() -> Texture2D:
	return _sprite.texture


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
	return [
		slime_growth,
		mucus_growth,
		slime_flower,
		mucus_flower,
		slime_spawn,
		mucus_spawn,
		drill_growth,
		drill_flower,
		drill_spawn
	]


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
	if _display_level == 3 and not _flower_announced:
		_flower_announced = true
		flower_appeared.emit()


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
	# Animation frames can change texture/anchor while keeping identical visible bounds.
	_refresh_bend_material()


func _get_frame_bounds(art: ItemArt, sprite: Sprite2D) -> Rect2:
	var texture: Texture2D = sprite.texture
	if not _texture_bounds.has(texture):
		_texture_bounds[texture] = Rect2(texture.get_image().get_used_rect())
	var picture: Node2D = sprite.get_parent() as Node2D
	return art.transform * picture.transform * sprite.transform * _texture_bounds[texture]
