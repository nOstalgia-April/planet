extends TextureRect

@export_range(0.1, 1.0, 0.01) var flash_seconds: float = 0.28
@export_range(1, 4, 1) var flash_count: int = 2

var _cooling: bool = false
var _flash_tween: Tween


func _ready() -> void:
	material = material.duplicate()
	resized.connect(_sync_size)
	_sync_size()
	reset()


func reset() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_cooling = false
	_set_flash(0.0)
	hide()


func sync(remaining: float, total: float, unlocked: bool) -> void:
	if not unlocked:
		reset()
		return
	if remaining > 0.0:
		if not _cooling:
			reset()
		_cooling = true
		show()
		(material as ShaderMaterial).set_shader_parameter(
			"progress", clampf(1.0 - remaining / maxf(total, 0.01), 0.0, 1.0)
		)
	elif _cooling:
		_cooling = false
		(material as ShaderMaterial).set_shader_parameter("progress", 1.0)
		_flash_tween = create_tween()
		for pulse: int in range(flash_count):
			_flash_tween.tween_method(_set_flash, 0.0, 1.0, flash_seconds * 0.4)
			_flash_tween.tween_method(_set_flash, 1.0, 0.0, flash_seconds * 0.6)
		_flash_tween.tween_callback(hide)


func set_accent(color: Color) -> void:
	(material as ShaderMaterial).set_shader_parameter("accent", color)


func _set_flash(value: float) -> void:
	(material as ShaderMaterial).set_shader_parameter("flash", value)


func _sync_size() -> void:
	(material as ShaderMaterial).set_shader_parameter("rect_size", size)
