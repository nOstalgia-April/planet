extends Node

const PREVIEW: PackedScene = preload("res://features/ending_preview/ending_preview.tscn")
const Preview = preload("res://features/ending_preview/ending_preview.gd")
const Credits = preload("res://scripts/ui/ending_credits.gd")
const MainMenu = preload("res://scenes/主菜单/主菜单.gd")
const EXPECTED_CAST: String = "史莱姆：小粉\n粘液怪：小蓝\n钻头怪：小黄"
const EXPECTED_PROJECT: String = "委托项目：星际家政 · 紧急清扫委托\n任务地点：M星\n委托单位：星际督查局\n执行小队：星际家政0101小组"
const EXPECTED_TEAM: String = (
	"游戏策划：常常、小墨\n视觉美术：aji、精盐\n角色设计：精盐\n场景美术：aji\n动画制作：aji、精盐\n"
	+ "程序开发：常常\n声音设计/作曲：fred\n音频交互程序：fred\n文案：小墨"
)

var _game: Preview
var _credits: Credits
var _failures: Array[String] = []
var _finished: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1920, 1080)
	_game = PREVIEW.instantiate() as Preview
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	_credits = _game._completion
	_credits.finished.connect(func() -> void: _finished += 1)
	var deadline: int = Time.get_ticks_msec() + 12000
	while not _credits.playing and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_game.run.is_complete, "F6 preview completes the real three-color objective.")
	_check(_credits.playing, "The existing victory sequence opens the credits.")
	_game.set_process(false)
	_credits.set_process(false)
	_check_content()
	_check_natural_finish()
	await _check_skip_escape_and_close()
	await _check_preview_replay()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_sizes()
	await _check_restart()
	await _check_main_menu()
	for failure: String in _failures:
		push_error(failure)
	print(
		(
			"PASS: ending credits content, replay guard, natural finish, skip, Esc, HUD restoration, restart and main menu."
			if _failures.is_empty()
			else "FAIL: ending credits"
		)
	)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_content() -> void:
	_check((_credits.get_node("Roll/Cast/Names") as Label).text == EXPECTED_CAST, "Cast is exact.")
	_check(
		(_credits.get_node("Roll/Project/Details") as Label).text == EXPECTED_PROJECT,
		"Commission details are exact."
	)
	_check((_credits.get_node("Roll/Team/Names") as Label).text == EXPECTED_TEAM, "Team is exact.")
	_check(
		(_credits.get_node("Roll/Thanks/Title") as Label).text == "特别感谢",
		"The final thanks heading is exact."
	)
	_check(
		(_credits.get_node("Roll/Thanks/Message") as Label).text == "所有参与本次星际清扫任务的伙伴",
		"The final thanks message is exact."
	)
	_check(not _game._layout.game_menu.visible, "Credits hide the gameplay menu.")
	_check(not _game._layout.get_node("Economy").visible, "Credits hide the gameplay economy.")
	_check(
		_game._planet_art._blend_material.get_shader_parameter("original_restored_core") == true,
		"Credits preserve the restored artwork's original center color."
	)
	_check(
		not _game._layout._tool_dock.is_visible_in_tree(), "Credits hide the entire bottom dock."
	)


func _check_natural_finish() -> void:
	_credits._process(3.0)
	var before: float = _credits._scrolled
	_credits.play()
	_credits.set_process(false)
	_check(is_equal_approx(_credits._scrolled, before), "Duplicate play preserves scroll position.")
	var finished_before: int = _finished
	for _step: int in range(500):
		_credits._process(0.25)
		if not _credits.playing:
			break
	_check(not _credits.playing and _credits.visible, "Natural completion retains the end card.")
	_check(_finished == finished_before + 1, "Natural completion emits finished once.")
	_check_final_card()
	_credits.play()
	_credits._process(10.0)
	_check(not _credits.playing, "Duplicate play cannot restart a completed visible card.")
	_check(_finished == finished_before + 1, "A finished card cannot finish twice.")


func _check_final_card() -> void:
	_check(_credits._actions.visible, "The final card presents the three actions.")
	_check(not _credits._skip.visible, "The final card removes Skip.")
	for group: String in ["Cast", "Project", "Team"]:
		var control: Control = _credits.get_node("Roll/" + group) as Control
		_check(
			is_zero_approx(control.modulate.a),
			"Earlier credits fully leave the final card: " + group
		)
	_check(_credits._thanks.is_visible_in_tree(), "The final thanks remains visible.")


func _check_skip_escape_and_close() -> void:
	_begin_roll()
	await _click(_credits.get_node("Skip") as Button)
	_check(not _credits.playing and _credits._actions.visible, "Skip opens the final card.")
	_begin_roll()
	await _key(KEY_ESCAPE)
	_check(not _credits.playing and _credits.visible, "Esc skips a running credit roll.")
	_check(not get_tree().paused, "Esc during credits does not pause gameplay.")
	await _key(KEY_ESCAPE)
	_check(not get_tree().paused, "Esc on the final card cannot pause gameplay.")
	await _click(_credits.get_node("Actions/Close") as Button)
	_check(not _credits.visible and not _credits.playing, "Close stops and hides the credit roll.")
	_check(_game._layout.game_menu.visible, "Close restores the gameplay menu.")
	_check(_game._layout.get_node("Economy").visible, "Close restores the gameplay economy.")
	_check(_game._layout.get_node("StatusLabel").visible, "Close restores gameplay status.")
	_check(not _game._layout._tool_dock._suppressed, "Close releases the bottom dock.")
	_check(_game._layout._tool_dock.is_visible_in_tree(), "Close restores the entire bottom dock.")
	_check(_game._layout._view_shortcut.visible, "Close restores the view switch.")
	_check(
		_game._planet_art._blend_material.get_shader_parameter("original_restored_core") == false,
		"Close restores the gameplay center treatment."
	)


func _check_restart() -> void:
	_begin_roll()
	_credits._process(8.0)
	var finished_before: int = _finished
	_game.restart_run()
	_credits._process(120.0)
	await _settle()
	_check(not _credits.visible and not _credits.playing, "Restart stops an active credit roll.")
	_check(_finished == finished_before, "Cancelled credit rolls do not emit stale completion.")
	_check(not _game.run.is_complete, "Restart clears victory rules.")
	_check(
		_game._planet_art._blend_material.get_shader_parameter("original_restored_core") == false,
		"Restart clears the ending artwork treatment."
	)
	_begin_roll()
	_credits.finish_credits()
	await _click(_credits.get_node("Actions/Replay") as Button)
	_check(not _credits.visible and not _credits.playing, "Replay closes the final card.")
	_check(not _game.run.is_complete and _game.run.candy == 0, "Replay starts a fresh game.")
	_check(not get_tree().paused, "Replay leaves the fresh game running.")


func _check_preview_replay() -> void:
	await _key(KEY_R)
	var deadline: int = Time.get_ticks_msec() + 6000
	while not _credits.playing and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(
		_game.run.is_complete and _credits.playing, "F6 preview R replays the victory and ending."
	)
	_credits.set_process(false)


func _check_main_menu() -> void:
	_begin_roll()
	_credits.finish_credits()
	await _click(_credits.get_node("Actions/Menu") as Button)
	await _settle()
	_check(not get_tree().paused, "Returning to the main menu clears pause.")
	var current: Node = get_tree().current_scene
	_check(
		current != null and current.scene_file_path == "res://scenes/主菜单/主菜单.tscn",
		"The ending menu action opens the real main menu."
	)
	_check(GameAudio._music_path == "event:/Mx/Mx_MainMenu", "Main menu music resumes.")
	if current is MainMenu:
		var menu: MainMenu = current as MainMenu
		var deadline: int = Time.get_ticks_msec() + 12000
		while not menu._loading_scene.is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		_check(
			menu._prepared_scene != null, "Returned main menu finishes preparing its start scene."
		)
	if current != null:
		get_tree().current_scene = null
		current.queue_free()
	await _settle()


func _begin_roll() -> void:
	_credits.reset()
	_credits.play()
	_credits.set_process(false)


func _capture_sizes() -> void:
	var directory: String = (
		"res://artifacts/ending_credits_%d_%d"
		% [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	)
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Capture directory exists.")
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_window().size = dimensions
		_game._apply_layout()
		await _settle()
		_begin_roll()
		_credits._process(
			_credits.opening_hold_seconds + (_credits.size.y * 0.76 + 24.0) / _credits.scroll_speed
		)
		await _capture(directory, dimensions, "01_cast_project")
		_begin_roll()
		var team: Control = _credits.get_node("Roll/Team") as Control
		var target_y: float = _credits.size.y * 0.42 - team.position.y - team.size.y * 0.5
		_credits._process(
			(
				_credits.opening_hold_seconds
				+ (_credits.size.y + 24.0 - target_y) / _credits.scroll_speed
			)
		)
		await _capture(directory, dimensions, "02_team")
		_credits._process(120.0)
		_check_final_card()
		await _capture(directory, dimensions, "03_thanks_actions")
	print("CAPTURES: ", ProjectSettings.globalize_path(directory))


func _capture(directory: String, dimensions: Vector2i, phase: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(image.get_size() == dimensions, "Captured output has the requested physical size.")
	var path: String = "%s/%dx%d_%s.png" % [directory, dimensions.x, dimensions.y, phase]
	_check(image.save_png(path) == OK, "Current rendered ending saved.")
	print("CAPTURE: ", path, " ", Time.get_datetime_string_from_system())


func _click(button: Button) -> void:
	await _settle()
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_tree().root.push_input(event, true)
		await get_tree().process_frame
	await _settle()


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		get_tree().root.push_input(event, true)
		await get_tree().process_frame
	await _settle()


func _settle() -> void:
	for _frame: int in range(4):
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
