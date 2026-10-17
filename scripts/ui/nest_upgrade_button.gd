extends Button

@export var species_colors: PackedColorArray = PackedColorArray(
	[Color("e00064"), Color("586bdf"), Color("e7a322")]
)
@export_range(0.0, 2.0, 0.05) var flow_speed: float = 0.65
@export_range(1.0, 1.3, 0.01) var hover_scale: float = 1.14
@export_range(1.0, 30.0, 0.5) var response_speed: float = 16.0
@export_range(0.0, 1.5, 0.05) var entrance_seconds: float = 0.45
@export_range(0.0, 100.0, 1.0) var entrance_distance: float = 52.0
@export_range(0.05, 1.0, 0.05) var hold_start_scale: float = 0.25
@export_range(0.1, 1.0, 0.05) var hold_opacity: float = 0.45

var _flow_time: float = 0.0
var _hover_amount: float = 0.0
var _entrance_elapsed: float = 0.0
var _entrance_offset: float = 0.0
var _entering: bool = false
var _anchor: PackedVector2Array = PackedVector2Array()
var _holding: bool = false

@onready var _backing: TextureRect = $Backing
@onready var _icon: TextureRect = $Icon
@onready var _price: Label = $Price
@onready var _action: Label = $Action
@onready var _material: ShaderMaterial = _backing.material as ShaderMaterial
@onready var _price_material: ShaderMaterial = _price.material as ShaderMaterial


func _ready() -> void:
	mouse_entered.connect(_finish_entrance)


func set_hold_progress(progress: float) -> void:
	_holding = progress >= 0.0
	pivot_offset = size * 0.5
	if _holding:
		_finish_entrance()
		_set_details_visible(true)
		scale = Vector2.ONE * lerpf(hold_start_scale, 1.0, clampf(progress, 0.0, 1.0))
		modulate.a = hold_opacity
		_hover_amount = 0.0
		_backing.scale = Vector2.ONE
		_icon.scale = Vector2.ONE
	else:
		scale = Vector2.ONE
		modulate.a = 1.0


func _finish_entrance() -> void:
	if not _entering:
		return
	_entering = false
	_entrance_offset = 0.0
	_place_at_anchor()
	_set_details_visible(true)


func begin_entrance() -> void:
	_entrance_elapsed = 0.0
	_entrance_offset = entrance_distance if entrance_seconds > 0.0 else 0.0
	_entering = entrance_seconds > 0.0
	_set_details_visible(not _entering)
	_place_at_anchor()


func set_nest_anchor(anchor: PackedVector2Array) -> void:
	_anchor = anchor
	_place_at_anchor()


func contains_pointer(pointer: Vector2) -> bool:
	return (
		is_visible_in_tree()
		and Rect2(Vector2.ZERO, size).has_point(
			get_global_transform_with_canvas().affine_inverse() * pointer
		)
	)


func contains_hover_path(pointer: Vector2) -> bool:
	if not is_visible_in_tree() or _anchor.is_empty():
		return false
	var points: PackedVector2Array = _anchor.duplicate()
	var padded: Rect2 = Rect2(Vector2.ZERO, size).grow(10.0)
	points.append_array(
		(
			get_global_transform_with_canvas()
			* PackedVector2Array(
				[
					padded.position,
					Vector2(padded.end.x, padded.position.y),
					padded.end,
					Vector2(padded.position.x, padded.end.y)
				]
			)
		)
	)
	return Geometry2D.is_point_in_polygon(pointer, Geometry2D.convex_hull(points))


func _place_at_anchor() -> void:
	if _anchor.is_empty():
		return
	var parent: CanvasItem = get_parent() as CanvasItem
	var local_anchor: PackedVector2Array = (
		parent.get_global_transform_with_canvas().affine_inverse() * _anchor
	)
	var tangent: Vector2 = (local_anchor[1] - local_anchor[0]).normalized()
	var outward: Vector2 = Vector2(tangent.y, -tangent.x)
	var top: Vector2 = (local_anchor[0] + local_anchor[1]) * 0.5
	rotation = tangent.angle()
	position = top + outward * (size.y + 2.0 - _entrance_offset) - tangent * size.x * 0.5


func _set_details_visible(value: bool) -> void:
	_price.visible = value
	_action.visible = value


func refresh(nest: NestState, cost: int, requirement: String, candy: int) -> void:
	tooltip_text = ""
	visible = nest != null and cost >= 0 and requirement.is_empty()
	if not visible:
		disabled = true
		return
	disabled = candy < cost
	_material.set_shader_parameter("tint", species_colors[nest.species])
	_price_material.set_shader_parameter("tint", species_colors[nest.species])
	_price_material.set_shader_parameter("availability", 0.0 if disabled else 1.0)
	_price.text = str(cost)
	_icon.modulate.a = 0.55 if disabled else 1.0
	_backing.modulate.a = 0.65 if disabled else 1.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_hover_amount = 0.0
		return
	if get_tree().paused:
		return
	if _entering:
		if contains_pointer(get_viewport().get_mouse_position()):
			_finish_entrance()
		else:
			_entrance_elapsed = minf(_entrance_elapsed + delta, entrance_seconds)
			var progress: float = _entrance_elapsed / entrance_seconds
			_entrance_offset = entrance_distance * pow(1.0 - progress, 3.0)
			_entering = _entrance_elapsed < entrance_seconds
			_place_at_anchor()
		_set_details_visible(not _entering)
	_flow_time = fmod(_flow_time + delta * flow_speed, TAU * 100.0)
	var highlighted: bool = not _holding and not disabled and is_hovered()
	var response: float = 1.0 - exp(-response_speed * delta)
	_hover_amount = lerpf(_hover_amount, 1.0 if highlighted else 0.0, response)
	var target_scale: float = lerpf(1.0, hover_scale, _hover_amount)
	if not _holding and not disabled and is_pressed():
		target_scale = 0.94
	_backing.scale = _backing.scale.lerp(Vector2.ONE * target_scale, response)
	_icon.scale = _backing.scale
	_material.set_shader_parameter("flow_time", _flow_time)
	_material.set_shader_parameter("hover_amount", _hover_amount)
	_price_material.set_shader_parameter("flow_time", _flow_time)
	_price_material.set_shader_parameter("hover_amount", _hover_amount)
	var text_color: Color = Color.WHITE.lerp(Color("fff0a8"), _hover_amount)
	_action.modulate = Color("d9bec9") if disabled else text_color
