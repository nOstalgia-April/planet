extends Node2D

signal released(amount: int)

@export_range(0.1, 1.0, 0.05) var sweep_fraction: float = 0.85
@export_range(0.2, 1.0, 0.05) var minimum_sweep_seconds: float = 0.4

var _source: Sprite2D
var _tween: Tween
var _amount: int = 0
var _progress: float = 0.0
var _bounds: Rect2
var _last_texture: Texture2D
var _active: bool = false

@onready var _light: Sprite2D = $LightSweep
@onready var _sparks: CPUParticles2D = $EnergySparks
@onready var _material: ShaderMaterial = _light.material as ShaderMaterial
@onready var _preview: Sprite2D = $PreviewFlower


func _ready() -> void:
	set_process(false)
	if get_tree().current_scene == self:
		_preview.show()
		_preview.position = get_viewport_rect().size * 0.5
		_preview.scale = Vector2.ONE * 3.0
		_run_preview.call_deferred()


func play(source: Sprite2D, amount: int, animation_seconds: float) -> void:
	_amount += amount
	if _active:
		return
	_source = source
	_active = true
	_light.show()
	_progress = 0.0
	_sync_frame()
	_sparks.restart()
	_sparks.emitting = true
	set_process(true)
	_tween = create_tween()
	var duration: float = maxf(minimum_sweep_seconds, animation_seconds * sweep_fraction)
	_tween.tween_method(_set_progress, 0.0, 1.0, duration)
	_tween.tween_callback(_release)


func _process(_delta: float) -> void:
	_sync_frame()


func _sync_frame() -> void:
	var frame_transform: Transform2D = global_transform.affine_inverse() * _source.global_transform
	_light.transform = frame_transform
	_light.centered = _source.centered
	_light.offset = _source.offset
	_light.texture = _source.texture
	if _last_texture != _source.texture:
		_last_texture = _source.texture
		var used: Rect2 = Rect2(_source.texture.get_image().get_used_rect())
		_material.set_shader_parameter(
			"vertical_bounds", Vector2(used.position.y, used.end.y) / _source.texture.get_height()
		)
		_bounds = Rect2(used.position + _source.get_rect().position, used.size)
	_sparks.transform = frame_transform
	_sparks.position = (
		frame_transform
		* Vector2(_bounds.get_center().x, lerpf(_bounds.end.y, _bounds.position.y, _progress))
	)
	_sparks.emission_rect_extents = Vector2(_bounds.size.x * lerpf(0.18, 0.48, _progress), 2.0)


func _set_progress(value: float) -> void:
	_progress = value
	_material.set_shader_parameter("progress", value)


func _release() -> void:
	_light.hide()
	_sparks.emitting = false
	_active = false
	set_process(false)
	var amount: int = _amount
	_amount = 0
	released.emit(amount)
	if get_tree().current_scene == self:
		_tween = create_tween()
		_tween.tween_interval(1.6)
		_tween.tween_callback(_run_preview)


func _run_preview() -> void:
	play(_preview, 5, 0.65)
