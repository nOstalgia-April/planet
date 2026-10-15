extends Node2D

@export_range(0.4, 2.0, 0.05) var duration: float = 1.05

var _tween: Tween
var _progress: float = 0.0

@onready var _light: ColorRect = $Light
@onready var _material: ShaderMaterial = _light.material as ShaderMaterial


func _ready() -> void:
	stop()
	if get_tree().current_scene == self:
		position = get_viewport_rect().size * 0.5
		play.call_deferred()


func play() -> void:
	stop()
	show()
	_set_progress(0.0)
	_tween = create_tween()
	_tween.tween_method(_set_progress, 0.0, 1.0, duration)
	_tween.tween_callback(hide)


func stop() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	hide()


func _set_progress(value: float) -> void:
	_progress = value
	_material.set_shader_parameter("progress", value)
