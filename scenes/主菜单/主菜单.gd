extends Control

@export_file("*.tscn") var start_scene: String = "res://features/场景预览/近景游玩预览.tscn"

@onready var _canvas: Control = $画布
@onready var _preview_panel: Control = $画布/预览选择


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	get_viewport().size_changed.connect(_fit_canvas)
	_fit_canvas()


func _fit_canvas() -> void:
	var factor: float = minf(size.x / 1920.0, size.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (size - Vector2(1920.0, 1080.0) * factor) * 0.5


func _start() -> void:
	_open_scene(start_scene)


func _open_scene(path: String) -> void:
	var result: Error = get_tree().change_scene_to_file(path)
	if result != OK:
		push_error("无法打开场景：%s (%d)" % [path, result])


func _toggle_previews() -> void:
	_preview_panel.visible = not _preview_panel.visible


func _quit() -> void:
	get_tree().quit()
