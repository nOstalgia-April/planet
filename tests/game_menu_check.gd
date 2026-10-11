extends Node

const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const OUTPUT: String = "res://artifacts/game_menu_20261012"

var _game: Play
var _failures: Array[String] = []
var _saved_config: String
var _had_config: bool
var _old_music: float
var _old_effects: float
var _old_enabled: bool
var _old_fullscreen: bool


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_had_config = FileAccess.file_exists(GamePreferences.SAVE_PATH)
	if _had_config:
		_saved_config = FileAccess.get_file_as_string(GamePreferences.SAVE_PATH)
	_old_music = GamePreferences.music_volume
	_old_effects = GamePreferences.effects_volume
	_old_enabled = GamePreferences.music_enabled
	_old_fullscreen = GamePreferences.fullscreen
	_run.call_deferred()


func _run() -> void:
	GamePreferences.reset_defaults()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_tree().root.size = resolution
		_game = PLAY.instantiate() as Play
		_game.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(_game)
		await _settle()
		_game.run.advance(15.0)
		await _settle()
		var layout: DiskDemoLayout = _game._layout
		var menu: Control = layout.game_menu
		_check(not _game.has_node("预览导航"), "preview navigation removed")
		_check(
			not layout.has_node("Legacy") and not layout.has_node("Goal"), "obsolete HUD removed"
		)
		_check(not layout.get_node("PipeUpgrade").visible, "upgrade popup starts hidden")
		await _capture("play", resolution)
		await _click(menu.get_node("Toolbar/Pause"))
		_check(get_tree().paused, "pause button stops scene tree")
		var spawn_clock: float = _game.run.nests[0].spawn_clock
		var position: Vector2 = _game._slimes[0].position
		await get_tree().create_timer(0.25, true).timeout
		_check(
			is_equal_approx(spawn_clock, _game.run.nests[0].spawn_clock), "pause freezes nest timer"
		)
		_check(position.is_equal_approx(_game._slimes[0].position), "pause freezes creature motion")
		_check(not _game._vacuum_audio._vacuum_on, "pause stops vacuum loop")
		await _capture("paused", resolution)
		await _click(menu.get_node("Toolbar/Settings"))
		_check(menu.is_open() and get_tree().paused, "settings opens while paused")
		await _capture("settings", resolution)
		await _click(menu.get_node("%ResumeGame"))
		_check(get_tree().paused, "closing settings preserves manual pause")
		await _key(KEY_ESCAPE)
		_check(not get_tree().paused, "escape resumes manual pause")
		await _click(menu.get_node("Toolbar/Settings"))
		_check(get_tree().paused, "settings pauses running game")
		menu.get_node("%MusicVolume").value = 37.0
		menu.get_node("%EffectsVolume").value = 24.0
		await _settle()
		_check(is_equal_approx(GamePreferences.music_volume, 0.37), "music slider applies")
		_check(is_equal_approx(GamePreferences.effects_volume, 0.24), "effects slider applies")
		var config: ConfigFile = ConfigFile.new()
		_check(config.load(GamePreferences.SAVE_PATH) == OK, "preferences saved")
		_check(
			is_equal_approx(config.get_value("audio", "music"), 0.37), "saved music volume matches"
		)
		_check(
			is_equal_approx(GameAudio._music.get_volume(), GameAudio._music_volume * 0.37),
			"FMOD music gain matches slider"
		)
		var effect: FmodEvent = GameAudio.start_loop("event:/Earth_Rotate")
		_check(is_equal_approx(effect.get_volume(), 0.24), "FMOD effects gain matches slider")
		GamePreferences.set_effects_volume(0.0)
		_check(is_zero_approx(effect.get_volume()), "existing effect can be muted")
		_check(AudioServer.is_bus_mute(0), "fallback effects also mute")
		GameAudio.stop_loop(effect)
		await _click(menu.get_node("%Controls"))
		await _capture("controls", resolution)
		await _key(KEY_ESCAPE)
		_check(
			menu.is_open() and not menu.get_node("%ControlsText").visible,
			"escape folds controls first"
		)
		await _key(KEY_ESCAPE)
		_check(not menu.is_open() and not get_tree().paused, "escape closes settings and resumes")
		await _click(menu.get_node("Toolbar/Music"))
		_check(
			not GamePreferences.music_enabled and is_zero_approx(GameAudio._music.get_volume()),
			"toolbar mutes music"
		)
		await _capture("music_muted", resolution)
		await _click(menu.get_node("Toolbar/Music"))
		_check(
			GamePreferences.music_enabled and GameAudio._music.get_volume() > 0.0,
			"toolbar restores music volume"
		)
		await _click(layout._technology_button)
		if not layout.is_technology_open():
			print(
				"TECH DIAGNOSTIC paused=",
				get_tree().paused,
				" manual=",
				layout._manual_pause,
				" modal=",
				menu.is_open(),
				" hovered=",
				get_viewport().gui_get_hovered_control()
			)
			await _capture("technology_failed", resolution)
		_check(layout.is_technology_open() and get_tree().paused, "technology still pauses")
		await _key(KEY_ESCAPE)
		_check(
			not layout.is_technology_open() and not get_tree().paused,
			"technology closes and resumes"
		)
		await _click(menu.get_node("Toolbar/Settings"))
		await _click(menu.get_node("%Restart"))
		await _capture("confirm", resolution)
		await _key(KEY_ESCAPE)
		_check(
			menu.is_open() and not menu.get_node("%Confirmation").visible, "escape cancels restart"
		)
		await _click(menu.get_node("%Restart"))
		await _click(menu.get_node("%ConfirmAction"))
		_check(not get_tree().paused and not menu.is_open(), "confirmed restart resumes")
		_check(_game.run.candy == 0 and _game._slimes.is_empty(), "confirmed restart resets run")
		_game.queue_free()
		await _settle()
	GamePreferences.set_fullscreen(true)
	await _settle()
	_check(
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
		"fullscreen applies"
	)
	GamePreferences.set_fullscreen(false)
	await _settle()
	_check(
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED,
		"windowed mode restores"
	)
	get_tree().current_scene = null
	_game = PLAY.instantiate() as Play
	_game.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	await _settle()
	await _click(_game._layout.game_menu.get_node("Toolbar/Settings"))
	await _click(_game._layout.game_menu.get_node("%MainMenu"))
	await _click(_game._layout.game_menu.get_node("%CancelAction"))
	_check(_game._layout.game_menu.is_open(), "return-to-menu cancellation keeps game")
	await _click(_game._layout.game_menu.get_node("%MainMenu"))
	await _click(_game._layout.game_menu.get_node("%ConfirmAction"))
	await _settle()
	_check(not get_tree().paused, "main menu is not paused")
	_check(
		get_tree().current_scene.scene_file_path == "res://scenes/主菜单/主菜单.tscn",
		"confirmed menu action changes scene"
	)
	_check(GameAudio._music_path == "event:/Mx_MainMenu", "main menu music starts")
	get_tree().current_scene.queue_free()
	get_tree().current_scene = null
	await _settle()
	_restore_preferences()
	for failure: String in _failures:
		push_error(failure)
	print(
		(
			"PASS: game menu, pause lifecycle, input, FMOD gains, persistence, restart and two resolutions."
			if _failures.is_empty()
			else "FAIL: game menu"
		)
	)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _restore_preferences() -> void:
	GamePreferences.music_volume = _old_music
	GamePreferences.effects_volume = _old_effects
	GamePreferences.music_enabled = _old_enabled
	GamePreferences.set_fullscreen(_old_fullscreen)
	if _had_config:
		var file: FileAccess = FileAccess.open(GamePreferences.SAVE_PATH, FileAccess.WRITE)
		file.store_string(_saved_config)
	else:
		DirAccess.remove_absolute(GamePreferences.SAVE_PATH)


func _key(key: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.pressed = true
	get_tree().root.push_input(event, true)
	await _settle()


func _click(control: Control) -> void:
	print("CLICK ", control.name)
	var point: Vector2 = control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	get_tree().root.push_input(motion, true)
	await _settle()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_tree().root.push_input(event, true)
		await get_tree().process_frame
	await _settle()


func _settle() -> void:
	for frame: int in range(6):
		await get_tree().process_frame


func _capture(label: String, resolution: Vector2i) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	print("CAPTURE ", label, resolution)
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	var path: String = "%s/%s_%dx%d.png" % [OUTPUT, label, resolution.x, resolution.y]
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture saved")


func _check(condition: bool, description: String) -> void:
	if not condition:
		print("CHECK FAILED ", description, " at ", get_tree().root.size)
		_failures.append(description)
