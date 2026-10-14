extends Control

@export_file("*.tscn") var start_scene: String = "res://features/场景预览/近景游玩预览.tscn"

# Scene being loaded in the background after "开始"; empty when idle.
var _loading_scene: String = ""

@onready var _canvas: Control = $画布
@onready var _preview_panel: Control = $画布/预览选择


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	get_viewport().size_changed.connect(_fit_canvas)
	_fit_canvas()
	GameAudio.play_music("event:/Mx/Mx_MainMenu")
	set_process(false)


func _fit_canvas() -> void:
	var factor: float = minf(size.x / 1920.0, size.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (size - Vector2(1920.0, 1080.0) * factor) * 0.5


func _start() -> void:
	if not _loading_scene.is_empty():
		return
	# The gameplay music is prepared now and enters as the transition fades.
	GameAudio.play_transition("event:/GameStart_Transition", "event:/Mx/Mx_GamePlay")
	# Load in the background so the main thread keeps running and the music
	# handoff stays on time; the menu ignores input until the scene is ready.
	if ResourceLoader.load_threaded_request(start_scene) != OK:
		_open_scene(start_scene)
		return
	_loading_scene = start_scene
	get_viewport().gui_disable_input = true
	set_process(true)


func _process(_delta: float) -> void:
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
		_loading_scene
	)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var path: String = _loading_scene
	_loading_scene = ""
	set_process(false)
	get_viewport().gui_disable_input = false
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(path) as PackedScene)
	else:
		_open_scene(path)


func _open_scene(path: String) -> void:
	var result: Error = get_tree().change_scene_to_file(path)
	if result != OK:
		push_error("无法打开场景：%s (%d)" % [path, result])


func _toggle_previews() -> void:
	_preview_panel.visible = not _preview_panel.visible


func _quit() -> void:
	get_tree().quit()
