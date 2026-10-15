extends Node2D

@export_range(0.5, 2.0, 0.05) var visual_scale: float = 1.0
@export_range(0.2, 2.0, 0.05) var preview_hold_seconds: float = 0.5
@export var idle_button_color: Color = Color("17141d")
@export var held_button_color: Color = Color("ff9454")

var _progress: float = 0.0
var _active: bool = false
var _holding: bool = false
var _preview: bool = false

@onready var _visual: Node2D = $Visual
@onready var _button: Sprite2D = $Visual/Mouse/LeftButton
@onready var _bar: ProgressBar = $Visual/Progress


func _ready() -> void:
	_visual.scale = Vector2.ONE * visual_scale
	_preview = get_tree().current_scene == self
	if _preview:
		position = get_viewport_rect().size * 0.5 + Vector2(0.0, 30.0)
	set_progress(_progress)
	set_holding(false)
	set_active(_preview)


func _process(delta: float) -> void:
	if _preview:
		set_holding(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
		set_progress(_progress + delta / preview_hold_seconds if _holding else 0.0)


func set_progress(progress: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	if is_node_ready():
		_bar.value = _progress


func set_holding(holding: bool) -> void:
	_holding = holding
	if not is_node_ready():
		return
	_button.modulate = held_button_color if holding else idle_button_color


func set_active(active: bool) -> void:
	_active = active
	visible = active
	set_process(active and _preview)
	if not active:
		set_holding(false)
