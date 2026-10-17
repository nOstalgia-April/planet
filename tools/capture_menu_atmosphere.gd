extends Node

const MENU_SCENE: PackedScene = preload("res://scenes/主菜单/主菜单.tscn")
const OUTPUT_DIRECTORY: String = "res://artifacts/menu_atmosphere_20261015"
const CAPTURE_SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 800)]

var _phase: String = "baseline"
var _output_directory: String = OUTPUT_DIRECTORY


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):
			_phase = argument.trim_prefix("--phase=")
		if argument.begins_with("--output-directory="):
			_output_directory = argument.trim_prefix("--output-directory=")
	assert(_phase in ["baseline", "after"], "Use --phase=baseline or --phase=after.")
	get_tree().create_timer(45.0).timeout.connect(_timed_out)
	_capture.call_deferred()


func _capture() -> void:
	var window: Window = get_tree().root
	window.mode = Window.MODE_WINDOWED
	window.size = CAPTURE_SIZES[0]
	var menu: Control = MENU_SCENE.instantiate() as Control
	add_child(menu)
	assert(DirAccess.make_dir_recursive_absolute(_output_directory) == OK)
	print("Capture phase: %s; scene: %s" % [_phase, menu.scene_file_path])
	print("Started: %s" % Time.get_datetime_string_from_system(false, true))
	await get_tree().create_timer(3.0).timeout
	for capture_size: Vector2i in CAPTURE_SIZES:
		window.size = capture_size
		for _frame: int in range(8):
			await get_tree().process_frame
		var frame: Image = await _save_frame(capture_size, "")
		if _phase == "after":
			await get_tree().create_timer(2.0).timeout
			var later_frame: Image = await _save_frame(capture_size, "_t2")
			assert(frame.get_data() != later_frame.get_data(), "Atmosphere must animate.")
			await _check_credits_input(menu, capture_size)
	while menu.is_processing():
		await get_tree().process_frame
	menu.queue_free()
	for _frame: int in range(3):
		await get_tree().process_frame
	print("Finished: %s" % Time.get_datetime_string_from_system(false, true))
	get_tree().quit()


func _save_frame(capture_size: Vector2i, suffix: String) -> Image:
	await RenderingServer.frame_post_draw
	var frame: Image = get_tree().root.get_texture().get_image()
	var filename: String = "%s_%dx%d%s.png" % [_phase, capture_size.x, capture_size.y, suffix]
	var path: String = _output_directory.path_join(filename)
	assert(frame.get_size() == capture_size, "Unexpected rendered image size.")
	assert(frame.save_png(path) == OK)
	print("Saved: %s; image size: %s" % [path, frame.get_size()])
	return frame


func _check_credits_input(menu: Control, capture_size: Vector2i) -> void:
	var credits_button: Button = menu.get_node("画布/制作信息") as Button
	var credits_panel: Control = menu.get_node("画布/制作信息弹窗") as Control
	var credits_frame: Control = credits_panel.get_node("底板") as Control
	var close_button: Button = credits_frame.get_node("关闭") as Button
	assert(not credits_panel.visible)
	await _click(credits_button.get_global_rect().get_center())
	assert(credits_panel.visible, "Atmosphere blocked credits mouse input.")
	var visible_rect: Rect2 = get_viewport().get_visible_rect()
	assert(
		visible_rect.encloses(credits_frame.get_global_rect()), "Credits panel exceeds viewport."
	)
	for node_path: NodePath in [NodePath("画布/开始"), NodePath("画布/制作信息"), NodePath("画布/退出")]:
		var button: Button = menu.get_node(node_path) as Button
		assert(visible_rect.encloses(button.get_global_rect()), "Menu button exceeds viewport.")
	await _save_frame(capture_size, "_credits")
	await _click(menu.get_node("画布/开始").get_global_rect().get_center())
	assert(not menu._start_requested, "Credits must block the underlying Start button.")
	await _click(close_button.get_global_rect().get_center())
	assert(not credits_panel.visible, "Credits close button failed.")
	await _click(credits_button.get_global_rect().get_center())
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await get_tree().process_frame
	assert(not credits_panel.visible, "Escape must close credits.")
	assert(credits_button.has_focus(), "Closing credits must restore keyboard focus.")
	print(
		(
			"PASS: animated frames, credits mouse/Escape close, modal input and UI bounds at %s."
			% capture_size
		)
	)


func _click(position: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var button: InputEventMouseButton = InputEventMouseButton.new()
		button.position = position
		button.global_position = position
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		get_viewport().push_input(button, true)
		await get_tree().process_frame


func _timed_out() -> void:
	push_error("Menu atmosphere capture timed out.")
	get_tree().quit(1)
