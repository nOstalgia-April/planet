extends Node

const Menu = preload("res://scenes/主菜单/主菜单.gd")
const MENU_PATH: String = "res://scenes/主菜单/主菜单.tscn"
const PREVIEW_PATHS: Array[String] = [
	"res://features/mascot_audio_preview/opening_audio_preview.tscn",
	"res://features/mascot_audio_preview/phase_two_audio_preview.tscn",
	"res://features/mascot_audio_preview/phase_three_audio_preview.tscn",
]
const RETURN_BUTTON: NodePath = ^"UI/Toolbar/Return"
const CAPTURE_DIRECTORY: String = "res://artifacts/mascot_audio_preview"

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
		assert(previews.get_child_count() == 3, "预览列表只保留三个说话音效入口。")
		if index == 0:
			await _check_menu_layout(previews)
		(previews.get_child(index) as Button).pressed.emit()
		await _tree.scene_changed
		assert(_tree.current_scene.scene_file_path == PREVIEW_PATHS[index], "按钮必须打开对应说话预览。")
		await _tree.process_frame
		(_tree.current_scene.get_node(RETURN_BUTTON) as Button).pressed.emit()
		await _tree.scene_changed
		assert(_tree.current_scene.scene_file_path == MENU_PATH, "每个预览必须能返回主菜单。")
	await _check_escape_return()
	print("PASS: three audio preview entries, title layout, button navigation and Escape return.")
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
			assert(DirAccess.make_dir_recursive_absolute(CAPTURE_DIRECTORY) == OK)
			await RenderingServer.frame_post_draw
			var destination: String = (
				"%s/preview_menu_%dx%d.png" % [CAPTURE_DIRECTORY, dimensions.x, dimensions.y]
			)
			assert(_tree.root.get_texture().get_image().save_png(destination) == OK)


func _check_escape_return() -> void:
	var menu: Menu = _tree.current_scene as Menu
	menu._open_scene(PREVIEW_PATHS[1])
	await _tree.scene_changed
	await _tree.process_frame
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await _tree.scene_changed
	escape.pressed = false
	Input.parse_input_event(escape)
	assert(_tree.current_scene.scene_file_path == MENU_PATH, "Esc 必须经过实际输入路由返回主菜单。")


func _timed_out() -> void:
	push_error("说话音效预览导航检查超时。")
	_tree.quit(1)
