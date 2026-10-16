extends ColorRect

@export var target: Control
@export var padding: float = 9.0


func _ready() -> void:
	assert(target != null, "Spotlight follows the real vacuum button.")
	material = material.duplicate()


func _process(_delta: float) -> void:
	if not visible:
		return
	var rect: Rect2 = target.get_global_rect().grow(
		padding * target.get_global_transform().get_scale().x
	)
	var shader_material: ShaderMaterial = material as ShaderMaterial
	shader_material.set_shader_parameter("focus_center", rect.get_center())
	shader_material.set_shader_parameter("focus_half_size", rect.size * 0.5)
	shader_material.set_shader_parameter("viewport_size", size)
