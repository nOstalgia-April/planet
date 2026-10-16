extends Button

@export var species_colors: PackedColorArray = PackedColorArray(
	[Color("e00064"), Color("586bdf"), Color("e7a322")]
)
@export_range(0.0, 2.0, 0.05) var flow_speed: float = 0.65
@export_range(1.0, 1.3, 0.01) var hover_scale: float = 1.14
@export_range(1.0, 30.0, 0.5) var response_speed: float = 16.0

var _flow_time: float = 0.0
var _hover_amount: float = 0.0

@onready var _backing: TextureRect = $Backing
@onready var _icon: TextureRect = $Icon
@onready var _price: Label = $Price
@onready var _action: Label = $Action
@onready var _material: ShaderMaterial = _backing.material as ShaderMaterial


func refresh(nest: NestState, cost: int, requirement: String, candy: int) -> void:
	tooltip_text = ""
	visible = nest != null and cost >= 0 and requirement.is_empty()
	if not visible:
		disabled = true
		return
	disabled = candy < cost
	_material.set_shader_parameter("tint", species_colors[nest.species])
	_price.text = str(cost)
	_icon.modulate.a = 0.55 if disabled else 1.0
	_backing.modulate.a = 0.65 if disabled else 1.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_hover_amount = 0.0
		return
	if get_tree().paused:
		return
	_flow_time = fmod(_flow_time + delta * flow_speed, TAU * 100.0)
	var highlighted: bool = not disabled and is_hovered()
	var response: float = 1.0 - exp(-response_speed * delta)
	_hover_amount = lerpf(_hover_amount, 1.0 if highlighted else 0.0, response)
	var target_scale: float = lerpf(1.0, hover_scale, _hover_amount)
	if not disabled and is_pressed():
		target_scale = 0.94
	_backing.scale = _backing.scale.lerp(Vector2.ONE * target_scale, response)
	_icon.scale = _backing.scale
	_material.set_shader_parameter("flow_time", _flow_time)
	_material.set_shader_parameter("hover_amount", _hover_amount)
	var text_color: Color = Color.WHITE.lerp(Color("fff0a8"), _hover_amount)
	_price.modulate = Color("d9bec9") if disabled else text_color
	_action.modulate = _price.modulate
