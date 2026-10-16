extends Node

# Deliberately do not preload gameplay: measure the same cold resource path as Start.
const MENU_PATH: String = "res://scenes/主菜单/主菜单.tscn"
const INTRO_PATH: String = "res://scenes/开头动画/开头动画.tscn"
const Menu = preload("res://scenes/主菜单/主菜单.gd")
const Intro = preload("res://scenes/开头动画/开头动画.gd")
var _frames: Array[float] = []
var _previous: int = 0
var _label: String = "run"
var _capture: bool = false
var _profile: bool = false
var _warm_menu: bool = false
var _large: bool = false
var _capture_loading: bool = false
var _observed_menu: Menu
var _observed_intro: Intro
var _menu_shown_at: int = 0
var _resource_ready_at: int = 0
var _opening_shown_at: int = 0
var _game_ready_at: int = 0
var _scene_switched_at: int = 0
var _first_game_draw_at: int = 0


func _ready() -> void:
	get_tree().current_scene = null
	# Observe the menu after its resource poll, before its deferred scene change.
	process_priority = 1000
	set_process(false)
	get_tree().scene_changed.connect(_record_scene_change)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=").validate_filename()
		elif argument == "--capture":
			_capture = true
		elif argument == "--profile":
			_profile = true
		elif argument == "--intro":
			# Retained for existing commands; the normal startup now always includes the opening.
			pass
		elif argument == "--warm-menu":
			_warm_menu = true
		elif argument == "--large":
			_large = true
		elif argument == "--capture-loading":
			_capture_loading = true
	get_tree().create_timer(60.0).timeout.connect(_timed_out)
	_run.call_deferred()


func _record_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if _scene_switched_at > 0 and _first_game_draw_at == 0:
		_first_game_draw_at = now
	if _profile and now - _previous > 50000:
		print("STARTUP_SLOW_FRAME ms=", float(now - _previous) / 1000.0)
	_frames.append(float(now - _previous) / 1000.0)
	_previous = now


func _process(_delta: float) -> void:
	_record_resource_ready()


func _record_resource_ready() -> void:
	if (
		_resource_ready_at == 0
		and is_instance_valid(_observed_menu)
		and _observed_menu._prepared_scene != null
	):
		_resource_ready_at = Time.get_ticks_usec()
	if is_instance_valid(_observed_intro) and _observed_intro._prepared_scene != null:
		_game_ready_at = Time.get_ticks_usec()
		set_process(false)


func _record_scene_change() -> void:
	var path: String = get_tree().current_scene.scene_file_path
	if path == MENU_PATH:
		_menu_shown_at = Time.get_ticks_usec()
	elif path == INTRO_PATH:
		_opening_shown_at = Time.get_ticks_usec()
		_observed_intro = get_tree().current_scene as Intro
	elif path == Menu.DEFAULT_START_SCENE:
		_scene_switched_at = Time.get_ticks_usec()


func _run() -> void:
	var tree: SceneTree = get_tree()
	if DisplayServer.get_name() == "headless":
		push_error("Startup frame timing requires rendering; omit --headless.")
		tree.quit(2)
		return
	if _profile:
		tree.node_added.connect(_track_ready)
	tree.root.mode = Window.MODE_WINDOWED
	tree.root.size = Vector2i(1920, 1080) if _large else Vector2i(1280, 800)
	tree.root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	assert(tree.change_scene_to_file(MENU_PATH) == OK)
	await tree.scene_changed
	assert(tree.current_scene.scene_file_path == MENU_PATH)
	_observed_menu = tree.current_scene as Menu
	set_process(true)
	_record_resource_ready()
	for frame: int in range(30):
		await tree.process_frame
	var menu: Menu = tree.current_scene as Menu
	if _warm_menu:
		while menu._prepared_scene == null:
			await tree.process_frame
	_previous = Time.get_ticks_usec()
	var started: int = _previous
	RenderingServer.frame_post_draw.connect(_record_frame)
	(menu.get_node("画布/开始") as Button).pressed.emit()
	assert(menu._start_requested)
	assert((menu.get_node("画布/开始") as Button).disabled)
	assert(not tree.root.gui_disable_input, "Loading must not leave global GUI input locked.")
	menu._start()
	if _capture_loading:
		# Screenshot readback affects timing: use this mode only for visual QA.
		for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
			tree.root.size = dimensions
			await tree.process_frame
			await RenderingServer.frame_post_draw
			if tree.current_scene == menu:
				var path: String = (
					"res://artifacts/startup_20261015_loading_%s_%dx%d.png"
					% [_label, dimensions.x, dimensions.y]
				)
				assert(tree.root.get_texture().get_image().save_png(path) == OK)
		tree.root.size = Vector2i(1920, 1080) if _large else Vector2i(1280, 800)
	while (
		tree.current_scene == null or tree.current_scene.scene_file_path != Menu.DEFAULT_START_SCENE
	):
		await tree.scene_changed
	assert(_resource_ready_at > 0, "Observe resource readiness before deferred scene entry.")
	assert(_opening_shown_at > 0, "Start must show the opening before entering gameplay.")
	assert(_game_ready_at > 0, "Gameplay prepares in the background while the opening plays.")
	var scene_ms: float = float(_scene_switched_at - started) / 1000.0
	assert(tree.current_scene.scene_file_path == Menu.DEFAULT_START_SCENE)
	assert(not tree.root.gui_disable_input)
	await RenderingServer.frame_post_draw
	var first_draw_ms: float = float(_first_game_draw_at - started) / 1000.0
	# A warm menu can be ready before the click. Exclude that idle time from the
	# actual scene-entry segment, while preserving raw ready-to-scene timestamps.
	var entry_ready_at: int = maxi(started, _game_ready_at)
	var loading_frames: Array[float] = _frames.duplicate()
	_frames.clear()
	for frame: int in range(180):
		await RenderingServer.frame_post_draw
	RenderingServer.frame_post_draw.disconnect(_record_frame)
	loading_frames.sort()
	_frames.sort()
	print(
		(
			"STARTUP_RESULT "
			+ (
				JSON
				. stringify(
					{
						"label": _label,
						"scene_ms": scene_ms,
						"first_draw_ms": first_draw_ms,
						"menu_to_click_ms": float(started - _menu_shown_at) / 1000.0,
						"click_to_opening_ms": float(_opening_shown_at - started) / 1000.0,
						"opening_to_game_ready_ms":
						float(_game_ready_at - _opening_shown_at) / 1000.0,
						"opening_to_game_scene_ms":
						float(_scene_switched_at - _opening_shown_at) / 1000.0,
						"menu_to_resources_ready_ms":
						float(_resource_ready_at - _menu_shown_at) / 1000.0,
						"resources_ready_before_click": _resource_ready_at <= started,
						"click_to_resources_ready_ms":
						float(maxi(0, _resource_ready_at - started)) / 1000.0,
						"resources_ready_to_scene_ms":
						float(_scene_switched_at - _resource_ready_at) / 1000.0,
						"resources_ready_to_first_draw_ms":
						float(_first_game_draw_at - _resource_ready_at) / 1000.0,
						"entry_after_resources_ready_ms":
						float(_scene_switched_at - entry_ready_at) / 1000.0,
						"scene_to_first_draw_ms":
						float(_first_game_draw_at - _scene_switched_at) / 1000.0,
						"loading_frame_max_ms": loading_frames.back(),
						"loading_frames": loading_frames.size(),
						"play_frame_median_ms": _frames[89],
						"play_frame_p95_ms": _frames[170],
						"play_frame_max_ms": _frames.back(),
						"scene": tree.current_scene.scene_file_path,
					}
				)
			)
		)
	)
	if _capture:
		var path: String = "res://artifacts/startup_20261015_%s.png" % _label
		assert(tree.root.get_texture().get_image().save_png(path) == OK)
		print("STARTUP_CAPTURE " + ProjectSettings.globalize_path(path))
	tree.quit()


func _timed_out() -> void:
	push_error("Startup did not complete within 60 seconds.")
	get_tree().quit(1)


func _track_ready(node: Node) -> void:
	node.ready.connect(_report_ready.bind(node, Time.get_ticks_usec()), CONNECT_ONE_SHOT)


func _report_ready(node: Node, started: int) -> void:
	var milliseconds: float = float(Time.get_ticks_usec() - started) / 1000.0
	if milliseconds >= 5.0:
		print("STARTUP_READY ms=", milliseconds, " node=", node.get_path())
