extends Node

const Menu = preload("res://scenes/主菜单/主菜单.gd")
const StoryFlow = preload("res://features/tutorial_intro/story_flow.gd")
const MENU_PATH: String = "res://scenes/主菜单/主菜单.tscn"
const PREVIEW_PATHS: Array[String] = [
	"res://features/mascot_audio_preview/opening_audio_preview.tscn",
	"res://features/mascot_audio_preview/phase_two_audio_preview.tscn",
	"res://features/mascot_audio_preview/phase_three_audio_preview.tscn",
	"res://features/tutorial_intro/full_flow_preview.tscn",
]
const RETURN_BUTTON: NodePath = ^"UI/Toolbar/Return"
var _capture_directory: String = "res://artifacts/mascot_flow_navigation_%d" % Time.get_ticks_usec()

@onready var _tree: SceneTree = get_tree()


func _ready() -> void:
	_tree.current_scene = null
	_run.call_deferred()


func _run() -> void:
	_tree.root.mode = Window.MODE_WINDOWED
	_tree.create_timer(60.0).timeout.connect(_timed_out)
	assert(_tree.change_scene_to_file(MENU_PATH) == OK)
	await _tree.scene_changed
	for index: int in range(PREVIEW_PATHS.size()):
		var menu: Menu = _tree.current_scene as Menu
		assert(not menu._preview_panel.visible, "返回主菜单后默认收起预览列表。")
		(menu.get_node("画布/预览") as Button).pressed.emit()
		await _tree.process_frame
		var previews: GridContainer = menu.get_node("画布/预览选择/列表") as GridContainer
		assert(menu._preview_panel.visible)
		assert(previews.get_child_count() == PREVIEW_PATHS.size(), "预览列表包含三个说话入口和完整流程。")
		if index == 0:
			await _check_menu_layout(previews)
		(previews.get_child(index) as Button).pressed.emit()
		await _tree.scene_changed
		assert(_tree.current_scene.scene_file_path == PREVIEW_PATHS[index], "按钮必须打开对应说话预览。")
		await _tree.process_frame
		if index == 3:
			await _check_full_flow()
			_send_escape()
		else:
			(_tree.current_scene.get_node(RETURN_BUTTON) as Button).pressed.emit()
		await _tree.scene_changed
		assert(_tree.current_scene.scene_file_path == MENU_PATH, "每个预览必须能返回主菜单。")
		assert(not _tree.paused and is_equal_approx(Engine.time_scale, 1.0))
	await _check_escape_return()
	print("PASS: audio and full-flow preview entries, title layout, navigation and Escape return.")
	GameLifecycle.request_quit()


func _check_menu_layout(previews: GridContainer) -> void:
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		_tree.root.size = dimensions
		await _tree.process_frame
		await _tree.process_frame
		for child: Button in previews.get_children():
			var rectangle: Rect2 = (
				child.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, child.size)
			)
			assert(_tree.root.get_visible_rect().encloses(rectangle), "预览按钮必须完整显示。")
			assert(child.size.x >= child.get_combined_minimum_size().x, "入口文字不能挤出按钮。")
		if "--capture" in OS.get_cmdline_user_args():
			assert(DirAccess.make_dir_recursive_absolute(_capture_directory) == OK)
			await RenderingServer.frame_post_draw
			var destination: String = (
				"%s/preview_menu_%dx%d.png" % [_capture_directory, dimensions.x, dimensions.y]
			)
			assert(_tree.root.get_texture().get_image().save_png(destination) == OK)
			print("CAPTURE: " + destination)


func _check_full_flow() -> void:
	var story: StoryFlow = _tree.current_scene.get_node("StoryFlow") as StoryFlow
	var deadline: int = Time.get_ticks_msec() + 20000
	while story.phase != StoryFlow.Phase.TALKING and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	assert(story.kind == StoryFlow.Kind.OPENING, "完整流程自然推进到看板娘入场与对白。")
	assert(not _tree.paused and is_equal_approx(Engine.time_scale, 0.5), "对白阶段背景半速播放；Esc 仍需可用。")
	var restart: InputEventKey = InputEventKey.new()
	restart.keycode = KEY_R
	restart.pressed = true
	Input.parse_input_event(restart)
	await _tree.process_frame
	assert(story.game._view.is_overview(), "重播从远景重新开始。")
	deadline = Time.get_ticks_msec() + 20000
	while story.phase != StoryFlow.Phase.TALKING and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	assert(story.kind == StoryFlow.Kind.OPENING and story.phase == StoryFlow.Phase.TALKING)
	if "--capture" in OS.get_cmdline_user_args():
		await _tree.create_timer(2.0, true, false, true).timeout
		await RenderingServer.frame_post_draw
		var destination: String = _capture_directory + "/full_flow.png"
		assert(_tree.root.get_texture().get_image().save_png(destination) == OK)
		print("CAPTURE: " + destination)


func _check_escape_return() -> void:
	var menu: Menu = _tree.current_scene as Menu
	menu._open_scene(PREVIEW_PATHS[1])
	await _tree.scene_changed
	await _tree.process_frame
	_send_escape()
	await _tree.scene_changed
	assert(_tree.current_scene.scene_file_path == MENU_PATH, "Esc 必须经过实际输入路由返回主菜单。")


func _send_escape() -> void:
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	var release: InputEventKey = escape.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)


func _timed_out() -> void:
	push_error("说话音效预览导航检查超时。")
	_tree.quit(1)
