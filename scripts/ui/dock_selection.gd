extends TextureRect

@export var selected: bool = true
@export var appear_seconds: float = 0.28
@export var disappear_seconds: float = 0.12

var _transition: Tween
var _reveal: float = 0.0


func _ready() -> void:
	material = material.duplicate()
	resized.connect(_sync_size)
	_sync_size()
	_set_reveal(0.0)
	if selected:
		_animate()


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	_animate()


func _animate() -> void:
	if _transition != null:
		_transition.kill()
	var duration: float = appear_seconds if selected else disappear_seconds
	_transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_transition.tween_method(_set_reveal, _reveal, 1.0 if selected else 0.0, duration)


func _set_reveal(value: float) -> void:
	_reveal = value
	(material as ShaderMaterial).set_shader_parameter("reveal", value)
	visible = value > 0.0


func _sync_size() -> void:
	(material as ShaderMaterial).set_shader_parameter("rect_size", size)
