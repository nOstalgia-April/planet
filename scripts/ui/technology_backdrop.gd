extends ColorRect

@export_range(0.0, 4.0, 0.1) var pointer_response: float = 1.2
@export_range(0.1, 4.0, 0.1) var ripple_fade_speed: float = 1.4

var _activity: float = 0.0

@onready var _waves: ShaderMaterial = material as ShaderMaterial


func _ready() -> void:
	visibility_changed.connect(_reset_pointer)
	_reset_pointer()


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	if not is_visible_in_tree() or size.x <= 0.0 or size.y <= 0.0:
		return
	var motion: InputEventMouseMotion = make_input_local(event) as InputEventMouseMotion
	if not Rect2(Vector2.ZERO, size).has_point(motion.position):
		return
	_waves.set_shader_parameter("cursor_uv", motion.position / size)
	var impulse: float = motion.relative.length() / size.y * pointer_response * 8.0
	_activity = minf(_activity + impulse, 1.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_activity = move_toward(_activity, 0.0, delta * ripple_fade_speed)
	_waves.set_shader_parameter("cursor_activity", _activity)


func _reset_pointer() -> void:
	_activity = 0.0
	_waves.set_shader_parameter("cursor_activity", 0.0)
