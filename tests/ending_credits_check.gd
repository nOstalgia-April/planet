extends Node

const PREVIEW: PackedScene = preload("res://features/ending_preview/ending_preview.tscn")
const Preview = preload("res://features/ending_preview/ending_preview.gd")
const Credits = preload("res://scripts/ui/ending_credits.gd")
const MainMenu = preload("res://scenes/主菜单/主菜单.gd")
const CAPTURE_DIR: String = "res://artifacts/credits_drag_20261018"
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
var _menu_requests: int = 0
var _captured_core: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	get_window().mode = Window.MODE_WINDOWED
	await _open_preview()
	_check_content()
	await _check_sizes()
	await _check_restart_and_replay()
	await _check_drag_and_no_skip()
	_check_natural_finish()
	await _capture("finished")
	await _click(_credits._return_button)
	_check(_menu_requests == 1, "The return button opens the menu after completion.")
	await _check_main_menu()
	await _open_preview()
	for _drag: int in range(20):
		if not _credits.playing:
			break
		await _drag(Vector2(0.0, -300.0))
	_check(_finished == 2 and _menu_requests == 1, "Dragging to the end waits for a return click.")
	await _click(_credits._return_button)
	_check(_menu_requests == 2, "Dragged completion also returns through the button.")
	await _check_main_menu()
	for failure: String in _failures:
		push_error(failure)
	print(
		(
			"PASS: ending artwork, layouts, drag, blocked skip/Esc, finish button and restart."
			if _failures.is_empty()
			else "FAIL: ending credits"
		)
	)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _open_preview() -> void:
	_game = PREVIEW.instantiate() as Preview
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	_credits = _game._completion
	_credits.finished.connect(func() -> void: _finished += 1)
	_credits.menu_requested.connect(func() -> void: _menu_requests += 1)
	await _wait_for_credits()
	_game.set_process(false)
	_credits.set_process(false)


func _wait_for_credits() -> void:
	var deadline: int = Time.get_ticks_msec() + 20000
	while not _credits.playing and Time.get_ticks_msec() < deadline:
		if _game.story.receipt.playing:
			_check(
				_game._restoration.core.is_visible_in_tree(),
				"The white core remains visible behind the note."
			)
			_check(not _game._restoration.core.is_processing(), "The note holds the core still.")
			if "--capture" in OS.get_cmdline_user_args() and not _captured_core:
				_captured_core = true
				_game.story.receipt.hide()
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(
					CAPTURE_DIR.path_join("static_white_core.png")
				)
				_game.story.receipt.show()
			_game.story.receipt.reveal_all()
			_game.story.receipt.close()
		elif _game.story.phase == _game.StoryFlow.Phase.TALKING:
			_game.story.active_dialogue.advance()
		await get_tree().process_frame
	_check(_game.run.is_complete, "The preview completes the real three-color objective.")
	_check(_credits.playing, "The existing victory sequence opens the credits.")


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
	var art: TextureRect = _credits.get_node("Roll/Thanks/EndingArt") as TextureRect
	var atlas: AtlasTexture = art.texture as AtlasTexture
	_check(atlas != null, "Ending artwork uses the supplied transparent image region.")
	if atlas != null:
		_check(
			atlas.atlas.resource_path == "res://assets/ui/ending/alien_and_planet.png",
			"Ending artwork references the user's original image."
		)
		_check(atlas.region == Rect2(1062, 183, 738, 795), "Transparent margins are excluded.")
	_check(not _credits.has_node("Actions"), "The three end-card buttons are removed.")
	_check(not _credits._return_button.visible, "No return button appears during playback.")
	_check(_credits._return_button.text == "返回主菜单", "The final action says return to main menu.")
	_check(not _game._layout.game_menu.visible, "Credits hide the gameplay menu.")
	_check(not _game._layout.get_node("Economy").visible, "Credits hide the gameplay economy.")
	_check(not _game._layout._tool_dock.is_visible_in_tree(), "Credits hide the bottom dock.")
	_check(
		_game._planet_art._blend_material.get_shader_parameter("original_restored_core") == true,
		"Credits preserve the restored artwork's original center color."
	)


func _check_sizes() -> void:
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_window().size = dimensions
		_game._apply_layout()
		await _settle()
		_credits.reset()
		_credits.play()
		_credits.set_process(false)
		var art: TextureRect = _credits.get_node("Roll/Thanks/EndingArt") as TextureRect
		var thanks: Control = _credits.get_node("Roll/Thanks") as Control
		var target_y: float = _credits.size.y * 0.5 - thanks.position.y - thanks.size.y * 0.5
		_credits._process(
			(
				_credits.opening_hold_seconds
				+ (_credits.size.y + 24.0 - target_y) / _credits.scroll_speed
			)
		)
		_check(_credits.playing, "The thanks and image scroll through the screen before finishing.")
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var art_rect: Rect2 = art.get_global_rect()
		_check(
			absf(art_rect.get_center().x - viewport_size.x * 0.5) <= 2.0,
			"The supplied drawing is horizontally centered."
		)
		_check(
			get_viewport().get_visible_rect().encloses(art_rect),
			"The supplied drawing fits the viewport."
		)
		var return_rect: Rect2 = _credits._return_button.get_global_rect()
		_check(
			(
				return_rect.get_center().x > viewport_size.x * 0.8
				and return_rect.get_center().y > viewport_size.y * 0.8
			),
			"Return remains in the bottom right."
		)
		await _capture("rolling_%d" % dimensions.x)


func _check_restart_and_replay() -> void:
	_game.restart_run()
	_credits._process(120.0)
	await _settle()
	_check(not _credits.visible and not _credits.playing, "Restart cancels the credits.")
	_check(_menu_requests == 0 and _finished == 0, "Cancelled credits cannot return to the menu.")
	_check(not _game.run.is_complete, "Restart clears the victory objective.")
	await _key(KEY_R)
	await _wait_for_credits()
	_game.set_process(false)
	_credits.set_process(false)


func _check_natural_finish() -> void:
	_credits._process(3.0)
	var before: float = _credits._scrolled
	_credits.play()
	_credits.set_process(false)
	_check(is_equal_approx(_credits._scrolled, before), "Duplicate play preserves scroll position.")
	var art: TextureRect = _credits.get_node("Roll/Thanks/EndingArt") as TextureRect
	var until_art_leaves: float = art.get_global_rect().end.y / _game._layout.scale.y
	_credits._process((until_art_leaves - 1.0) / _credits.scroll_speed)
	_check(_menu_requests == 0, "Credits wait for the last pixel of the drawing to scroll out.")
	_check(art.get_global_rect().end.y > 0.0, "The drawing is still visible before completion.")
	_credits._process(2.0)
	_check(_finished == 1 and _menu_requests == 0, "Natural completion waits for the player.")
	_check(_credits._return_button.is_visible_in_tree(), "Completion reveals the return button.")
	_check(
		art.get_global_rect().end.y < 0.0, "The drawing fully exits before returning to the menu."
	)
	_credits.play()
	_credits.finish_credits()
	_check(
		_menu_requests == 0 and _finished == 1, "Repeated completion cannot return automatically."
	)


func _check_drag_and_no_skip() -> void:
	await _key(KEY_ESCAPE)
	await _key(KEY_ENTER)
	await _key(KEY_SPACE)
	_credits.return_to_menu()
	await _click(_credits._return_button)
	_check(_menu_requests == 0 and _credits.playing, "Keys and hidden return cannot skip credits.")
	_check(not get_tree().paused, "Escape does not pause credits.")
	var before: float = _credits._scrolled
	await _drag(Vector2(0.0, -200.0))
	_check(_credits._scrolled > before + 100.0, "An upward drag advances the rolling credits.")
	before = _credits._scrolled
	await _drag(Vector2(0.0, 100.0))
	_check(is_equal_approx(before, _credits._scrolled), "Downward dragging does not rewind.")
	_credits._process(1.0)
	_check(
		is_equal_approx(_credits._scrolled - before, _credits.scroll_speed),
		"Releasing the drag restores normal scroll speed."
	)


func _drag(displacement: Vector2) -> void:
	var point: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	get_tree().root.push_input(press, true)
	await get_tree().process_frame
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point + displacement
	motion.relative = displacement
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(motion, true)
	await get_tree().process_frame
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.position = motion.position
	release.button_index = MOUSE_BUTTON_LEFT
	get_tree().root.push_input(release, true)
	await _settle()


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(CAPTURE_DIR.path_join(label + ".png"))


func _check_main_menu() -> void:
	await _settle()
	_check(not get_tree().paused, "Returning to the main menu clears pause.")
	var current: Node = get_tree().current_scene
	_check(current is MainMenu, "The real main menu is displayed.")
	_check(GameAudio._music_path == "event:/Mx/Mx_MainMenu", "Main menu music resumes.")
	if current is MainMenu:
		var menu: MainMenu = current as MainMenu
		var deadline: int = Time.get_ticks_msec() + 12000
		while not menu._loading_scene.is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		_check(
			menu._prepared_scene != null, "The returned menu finishes preparing its start scene."
		)
	if current != null:
		get_tree().current_scene = null
		current.queue_free()
	await _settle()


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
