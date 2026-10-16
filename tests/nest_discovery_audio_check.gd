extends Node

# Run this scene explicitly: it follows F5's real menu and opening before
# forcing discoveries, and watches native FMOD counts rather than only _music.
const Menu = preload("res://scenes/主菜单/主菜单.gd")
const Game = preload("res://features/tutorial_intro/tutorial_game.gd")
const Discovery = preload("res://scripts/nest_discovery_presentation.gd")
const MUSIC: String = "event:/Mx/Mx_GamePlay"

var _failures: Array[String] = []
var _game: Game
var _music: FmodEvent
var _had_preferences: bool = false
var _saved_preferences: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_had_preferences = FileAccess.file_exists(GamePreferences.SAVE_PATH)
	if _had_preferences:
		_saved_preferences = FileAccess.get_file_as_string(GamePreferences.SAVE_PATH)
	_run.call_deferred()


func _run() -> void:
	var tree: SceneTree = get_tree()
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/主菜单/主菜单.tscn")
	await tree.scene_changed
	var menu: Menu = tree.current_scene as Menu
	menu.get_node("画布/开始").pressed.emit()
	await tree.scene_changed
	_check(tree.current_scene.scene_file_path == Menu.OPENING_SCENE, "Start plays the opening.")
	await tree.scene_changed
	_game = tree.current_scene as Game
	_game.tutorial.cancel()
	# Leave camera/presentation processing live; freeze automatic economy/spawns
	# so each requested discovery is the only changing gameplay condition.
	_game.set_process(false)
	await tree.create_timer(3.5, true, false, true).timeout
	_music = GameAudio._music
	_check(_music != null and _music.is_valid(), "Gameplay owns a valid music instance.")
	_check_music("after the opening")
	_request(NestState.Species.SLIME)
	await _watch(1.0, false, "first discovery")
	_toggle_audio()
	await _watch(1.0, true, "muted during discovery")
	_toggle_audio()
	await _watch(10.0, false, "discovery and its sound tail finish")
	_check(_game._nest_discovery.phase == Discovery.Phase.IDLE, "Discovery finishes normally.")
	_check(
		FmodServer.get_event("event:/Mx/OpeningAnimation").get_instance_count() == 0,
		"The opening's intended tail finishes without leaving another track behind."
	)
	_toggle_audio()
	# Keep watching beyond New_Nest's 8.7-second duration, including a new
	# species started while muted. Neither event may reopen the output.
	_request(NestState.Species.MUCUS)
	await _watch(11.0, true, "new species while muted")
	_toggle_audio()
	await _watch(0.5, false, "unmute restores the same music")
	_check(
		is_equal_approx(_music.get_volume(), GamePreferences.music_volume),
		"Unmute restores the chosen music volume."
	)
	tree.current_scene = null
	_game.queue_free()
	await tree.process_frame
	_restore_preferences()
	if _failures.is_empty():
		print(
			"PASS: real F5 menu/opening, one gameplay music instance, first/new-species discovery, toolbar mute/unmute and 11 seconds of muted playback."
		)
	else:
		for failure: String in _failures:
			push_error(failure)
	tree.quit(0 if _failures.is_empty() else 1)


func _request(species: NestState.Species) -> void:
	_game.run._pending_nest_species = species
	_game._on_nest_spawn_requested(species)
	_check(
		_game._monster_audio._new_nest != null and _game._monster_audio._new_nest.is_valid(),
		"The requested discovery starts New_Nest."
	)


func _toggle_audio() -> void:
	_game._layout.game_menu.get_node("Toolbar/Music").pressed.emit()


func _watch(seconds: float, muted: bool, context: String) -> void:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().create_timer(0.1, true, false, true).timeout
		_check_music(context)
		_check(GameAudio._master_bus.get_mute() == muted, context + ": FMOD master mute.")
		_check(
			AudioServer.is_bus_mute(0) == muted, context + ": native audio follows toolbar mute."
		)
		if muted:
			_check(is_zero_approx(_music.get_volume()), context + ": music volume is zero.")
			var cue: FmodEvent = _game._monster_audio._new_nest
			if cue != null and cue.is_valid():
				_check(
					is_zero_approx(cue.get_volume()), context + ": discovery cue volume is zero."
				)


func _check_music(context: String) -> void:
	_check(GameAudio._music == _music, context + ": discovery keeps the original music instance.")
	_check(GameAudio._music_path == MUSIC, context + ": gameplay remains the active music.")
	_check(GameAudio._pending_music == null, context + ": no second music is queued.")
	_check(GameAudio._fading_out.is_empty(), context + ": no old music remains.")
	for bank: FmodBank in GameAudio._banks:
		for description: FmodEventDescription in bank.get_description_list():
			var path: String = description.get_path()
			if not path.get_file().begins_with("Mx_"):
				continue
			_check(
				description.get_instance_count() == (1 if path == MUSIC else 0),
				context + ": expected native music count for " + path
			)


func _restore_preferences() -> void:
	if _had_preferences:
		var file: FileAccess = FileAccess.open(GamePreferences.SAVE_PATH, FileAccess.WRITE)
		file.store_string(_saved_preferences)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GamePreferences.SAVE_PATH))


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
