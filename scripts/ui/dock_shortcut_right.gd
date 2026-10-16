extends Button

@export var appear_seconds: float = 0.28
@export var disappear_seconds: float = 0.12

var _reveal: float = 0.0

@onready var _backing: TextureRect = $Backing


func _process(delta: float) -> void:
	var surface: ShaderMaterial = _backing.material as ShaderMaterial
	var target: float = surface.get_shader_parameter("selected")
	var duration: float = appear_seconds if target > _reveal else disappear_seconds
	_reveal = move_toward(_reveal, target, delta / duration)
	surface.set_shader_parameter("reveal", _reveal)
