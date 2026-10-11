extends Node

const POINTER: Texture2D = preload("res://assets/ui/technology/pointer.tres")
const HOTSPOT: Vector2 = Vector2(8.0, 1.0)

var _vacuum: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Every requested pointer shape uses the supplied artwork.
	for shape: int in range(Input.CURSOR_ARROW, Input.CURSOR_HELP + 1):
		Input.set_custom_mouse_cursor(POINTER, shape, HOTSPOT)


func register_vacuum(vacuum: Node2D) -> void:
	_vacuum = vacuum


func _process(_delta: float) -> void:
	var using_vacuum: bool = (
		is_instance_valid(_vacuum)
		and _vacuum.is_visible_in_tree()
		and not get_tree().paused
		and get_viewport().gui_get_hovered_control() == null
	)
	var mode: Input.MouseMode = Input.MOUSE_MODE_HIDDEN if using_vacuum else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode
