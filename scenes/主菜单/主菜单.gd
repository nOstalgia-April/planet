extends Control

const SharedCache = preload("res://scripts/art_resource_cache.gd")

const DEFAULT_START_SCENE: String = "res://features/场景预览/近景游玩预览.tscn"
const OPENING_SCENE: String = "res://scenes/开头动画/开头动画.tscn"
const START_TRANSITION: String = "event:/AnimationSystem/GameStart_Transition"
const GAMEPLAY_MUSIC: String = "event:/Mx/Mx_GamePlay"

# A custom entry is a direct preview/check target; the normal game always plays its opening.
@export_file("*.tscn") var start_scene: String = DEFAULT_START_SCENE

# Each scene owns one request reference; ResourceLoader shares the actual IO.
var _loading_scene: String = ""
var _start_requested: bool = false
var _prepared_scene: PackedScene

@onready var _canvas: Control = $画布
@onready var _preview_panel: Control = $画布/预览选择
@onready var _start_button: Button = $画布/开始
@onready var _preview_button: Button = $画布/预览


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	get_viewport().size_changed.connect(_fit_canvas)
	_fit_canvas()
	GameAudio.play_music("event:/Mx/Mx_MainMenu")
	_prepare_game()


func _fit_canvas() -> void:
	var factor: float = minf(size.x / 1920.0, size.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (size - Vector2(1920.0, 1080.0) * factor) * 0.5


func _start() -> void:
	if _start_requested:
		return
	_start_requested = true
	_start_button.disabled = true
	_start_button.text = "准备中…"
	_preview_button.disabled = true
	_preview_panel.hide()
	# The start sound answers the click. A direct entry skips the opening, so
	# its music follows the transition; the opening brings its own sound.
	GameAudio.play_transition(
		START_TRANSITION, "" if start_scene == DEFAULT_START_SCENE else GAMEPLAY_MUSIC
	)
	if _prepared_scene != null:
		_enter_game.call_deferred()
		return
	if _loading_scene.is_empty():
		_prepare_game()


func _prepare_game() -> void:
	var entry_scene: String = _entry_scene_path()
	if prepare_scene(entry_scene) != OK:
		_loading_failed()
		return
	_loading_scene = entry_scene
	set_process(true)


func _entry_scene_path() -> String:
	return OPENING_SCENE if start_scene == DEFAULT_START_SCENE else start_scene


static func prepare_scene(path: String = DEFAULT_START_SCENE) -> Error:
	# Godot 4.7.2 leaks analyzer temporaries when compiling this dependency
	# graph on loader workers. Prepare scripts/shaders here; texture IO stays async.
	_warm_resources(path, {})
	# Keep the request asynchronous, but avoid parallel subresource compilation.
	return ResourceLoader.load_threaded_request(path, "PackedScene")


static func _warm_resources(path: String, visited: Dictionary) -> void:
	if visited.has(path):
		return
	visited[path] = true
	var resources: Dictionary = SharedCache.get_cache(&"planet_prepared_resources")
	if path.get_extension() in ["gd", "gdshader", "gdshaderinc"] and not resources.has(path):
		resources[path] = load(path)
	for dependency: String in ResourceLoader.get_dependencies(path):
		var target: String = dependency.get_slice("::", dependency.get_slice_count("::") - 1)
		if target.get_extension() in ["gd", "tscn", "tres", "gdshader", "gdshaderinc"]:
			_warm_resources(target, visited)


static func release_scene(tree: SceneTree, path: String) -> void:
	# Preview handoffs keep running without waiting for the gameplay preload.
	# Application shutdown must retrieve it before loaders/rendering disappear.
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if GameLifecycle.quitting:
			break
		await tree.process_frame
	var resource: Resource = ResourceLoader.load_threaded_get(path)
	if not GameLifecycle.quitting:
		await tree.process_frame
	resource = null


func _exit_tree() -> void:
	if not _loading_scene.is_empty():
		release_scene(get_tree(), _loading_scene)


func _process(_delta: float) -> void:
	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
		_loading_scene, progress
	)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if _start_requested and not progress.is_empty():
			_start_button.text = "准备中 %d%%" % mini(99, int(float(progress[0]) * 100.0))
		return
	var path: String = _loading_scene
	_loading_scene = ""
	set_process(false)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_prepared_scene = ResourceLoader.load_threaded_get(path) as PackedScene
		if _start_requested:
			_enter_game.call_deferred()
	else:
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			ResourceLoader.load_threaded_get(path)
		_loading_failed()


func _enter_game() -> void:
	# The opening starts where music would follow the start sound.
	if start_scene == DEFAULT_START_SCENE:
		while GameAudio.is_transition_playing():
			await get_tree().process_frame
		if not is_inside_tree():
			return
	var result: Error = get_tree().change_scene_to_packed(_prepared_scene)
	if result != OK:
		_loading_failed()


func _loading_failed() -> void:
	_loading_scene = ""
	_start_requested = false
	_prepared_scene = null
	set_process(false)
	_start_button.disabled = false
	_start_button.text = "重试"
	_preview_button.disabled = false
	GameAudio.play_music("event:/Mx/Mx_MainMenu")
	push_error("无法准备开始场景：" + _entry_scene_path())


func _open_scene(path: String) -> void:
	var result: Error = get_tree().change_scene_to_file(path)
	if result != OK:
		push_error("无法打开场景：%s (%d)" % [path, result])


func _toggle_previews() -> void:
	_preview_panel.visible = not _preview_panel.visible


func _quit() -> void:
	GameLifecycle.request_quit()
