extends Node2D

const FrameSet = preload("res://scripts/effects/jewelry_shine_frames.gd")
const SHADER: Shader = preload("res://shaders/jewelry_shine.gdshader")

@export var target: Sprite2D
@export var animation_player: AnimationPlayer
@export var frames: FrameSet
@export_range(0.1, 2.0, 0.01) var shine_seconds: float = 0.6
@export_range(0.0, 10.0, 0.1) var cooldown_seconds: float = 2.0
@export var random_wait_seconds: Vector2 = Vector2(0.5, 3.0)

var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _material: ShaderMaterial
var _wait_remaining: float = 0.0
var _shine_elapsed: float = -1.0
var _has_jewelry: bool = false


func _ready() -> void:
	assert(target != null and animation_player != null and frames != null)
	assert(target.material == null, "Jewelry shine needs ownership of its sprite material.")
	assert(random_wait_seconds.x >= 0.0 and random_wait_seconds.y >= random_wait_seconds.x)
	assert(frames.masks.size() == frames.regions.size())
	_random.randomize()
	_wait_remaining = _random_wait()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	target.material = _material
	target.texture_changed.connect(_sync_frame)
	target.visibility_changed.connect(_sync_activity)
	_sync_frame()


func _process(delta: float) -> void:
	# A local tutorial freeze also freezes this cosmetic clock. Clip playback speed
	# (for example a faster launch animation) does not shorten the shine or cooldown.
	if is_zero_approx(animation_player.speed_scale):
		return
	if _shine_elapsed < 0.0:
		_wait_remaining -= delta
		if _wait_remaining > 0.0:
			return
		_shine_elapsed = 0.0
	else:
		_shine_elapsed += delta
		if _shine_elapsed >= shine_seconds:
			_finish_shine()
			return
	_material.set_shader_parameter("phase", _shine_elapsed / shine_seconds)


func _random_wait() -> float:
	return _random.randf_range(random_wait_seconds.x, random_wait_seconds.y)


func _finish_shine() -> void:
	_shine_elapsed = -1.0
	_wait_remaining = cooldown_seconds + _random_wait()
	_material.set_shader_parameter("phase", -1.0)


func _sync_frame() -> void:
	var source: Texture2D = target.texture
	_has_jewelry = frames.masks.has(source)
	if _has_jewelry:
		var region: Rect2 = frames.regions[source]
		var bounds: Rect2 = region.grow(-1.0)
		_material.set_shader_parameter("jewelry_mask", frames.masks[source])
		_material.set_shader_parameter(
			"mask_region",
			Vector4(region.position.x, region.position.y, region.size.x, region.size.y)
		)
		_material.set_shader_parameter(
			"bounds", Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y)
		)
		_material.set_shader_parameter("texture_size", source.get_size())
	_sync_activity()


func _sync_activity() -> void:
	var active: bool = _has_jewelry and target.is_visible_in_tree()
	if not active:
		if _shine_elapsed >= 0.0:
			_finish_shine()
		_material.set_shader_parameter("phase", -1.0)
	# Hidden variants and underground dirt frames neither poll nor consume random draws.
	set_process(active)
