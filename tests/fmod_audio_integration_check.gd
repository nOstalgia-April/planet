extends Node

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const MenuScene: PackedScene = preload("res://scenes/主菜单/主菜单.tscn")
const MenuScript = preload("res://scenes/主菜单/主菜单.gd")
const TechnologyPage = preload("res://scripts/ui/technology_page.gd")
const PlanetAudio = preload("res://scripts/planet_audio.gd")

var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run_checks.call_deferred()


func _run_checks() -> void:
	var tree: SceneTree = get_tree()
	var root: Window = tree.root
	_check(GameAudio.banks_loaded, "The main game banks load successfully.")
	var menu: MenuScript = MenuScene.instantiate() as MenuScript
	root.add_child(menu)
	tree.current_scene = menu
	await tree.process_frame
	while not menu._loading_scene.is_empty():
		await tree.process_frame
	_check(GameAudio._music_path == "event:/Mx/Mx_MainMenu", "The menu starts its music.")
	_check(GameAudio._music != null and GameAudio._music.is_valid(), "Menu music is valid.")
	await _check_audio_pause()
	tree.current_scene = null
	menu.queue_free()
	await tree.process_frame
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	tree.current_scene = demo
	demo.set_process(false)
	await tree.process_frame
	_check(GameAudio._music_path == "event:/Mx/Mx_GamePlay", "Gameplay switches the music.")
	_check(demo._vacuum_audio._ready_to_play, "The vacuum events exist in the updated banks.")
	_check(demo._monster_audio.is_ready(), "The monster and candy events exist.")
	_check(demo._planet_audio._ready_to_play, "The planet rotation event exists.")
	_check(UiAudio.is_ready(), "The button and upgrade events exist.")
	var page: TechnologyPage = demo.get_node("HUD/Interface/Technology") as TechnologyPage
	demo.run.candy = 0
	page.selected_key = "valuable"
	_check(
		not demo._is_technology_unaffordable(page.selected_key),
		"A locked research is not unaffordable."
	)
	demo.run.candy = 1000
	_check(demo.run.purchase_technology("cultivation"), "Cultivation unlocks global research.")
	demo.run.candy = 0
	for id: String in ["valuable", "giant"]:
		page.selected_key = id
		page.refresh(demo.run)
		_check(
			demo._is_technology_unaffordable(page.selected_key),
			"Global research checks its cost: " + id
		)
		page._nodes[id].pressed.emit()
		demo.run.candy = 1000
		demo._on_technology_upgrade(id)
		_check(
			demo.run.get_technology_level(id) == 1, "Global research purchases successfully: " + id
		)
		_check(
			not demo._is_technology_unaffordable(page.selected_key),
			"Completed research is not unaffordable."
		)
		demo.run.candy = 0
	demo._monster_audio.monster_sucked(1.0, 3, 1)
	demo._monster_audio.candy_from_net(2, 2)
	demo._monster_audio.golden_collected()
	_check(demo._monster_audio._golden_ready, "Golden_Mon is available.")
	await _check_candy_bursts(demo._monster_audio)
	_check_combo_audio(demo)
	_check_path_resolution()
	demo._play_collection_reward(2, Vector2.ZERO)
	var reward_effect: CollectionEffect = (
		demo._effects.get_child(demo._effects.get_child_count() - 1) as CollectionEffect
	)
	_check(reward_effect != null, "Collection visuals remain independent of the immediate sound.")
	await reward_effect._tween.finished
	await tree.process_frame
	_check(not is_instance_valid(reward_effect), "The collection flight finishes and cleans up.")
	_check_rotation_audio(demo)
	demo._planet_audio.update_rotation(0.01, true, demo._world.rotation + 0.02)
	demo._layout._show_technology()
	_check(
		demo._planet_audio._rotate == null,
		"Opening the paused technology page stops rotation audio."
	)
	demo._layout.close_panels()
	await tree.create_timer(0.4).timeout
	_check(is_equal_approx(GameAudio._music_volume, 1.0), "Gameplay music fades fully in.")
	_check(GameAudio._fading_out.is_empty(), "The previous music finishes fading out.")
	_check_loading_audio(demo._vacuum_audio)
	demo._vacuum_audio.update(0.1, true, true)
	demo._vacuum_audio.update_loading(demo, 0.5)
	demo.restart_run()
	_check(demo._vacuum_audio._loading == null, "Restart stops the loading loop.")
	_check(not demo._vacuum_audio._vacuum_on, "Restart stops the vacuum loop.")
	_check(not demo._vacuum_audio._in_slime, "Restart clears the mucus parameter.")
	tree.current_scene = null
	demo.queue_free()
	await tree.process_frame
	menu = MenuScene.instantiate() as MenuScript
	root.add_child(menu)
	tree.current_scene = menu
	await tree.process_frame
	while not menu._loading_scene.is_empty():
		await tree.process_frame
	_check(
		GameAudio._music_path == "event:/Mx/Mx_MainMenu",
		"Returning to the menu switches music back."
	)
	tree.current_scene = null
	menu.queue_free()
	await tree.process_frame
	if _failures == 0:
		print(
			"PASS: FMOD banks, music crossfades, monster/UI/net events, global research, collection visuals, rotation audio and vacuum reset."
		)
	tree.quit(0 if _failures == 0 else 1)


func _check_audio_pause() -> void:
	var tree: SceneTree = get_tree()
	var enabled: bool = GamePreferences.audio_enabled
	var music_volume: float = GamePreferences.music_volume
	var effects_volume: float = GamePreferences.effects_volume
	var editor_muted: bool = GameAudio._editor_muted
	var effect: FmodEvent = GameAudio.start_loop("event:/Earth_Rotate")
	await tree.create_timer(0.4).timeout
	# Menus (settings, technology page) pause the game: gameplay sounds hold
	# their place while music and UI keep playing under a low-pass.
	tree.paused = true
	await tree.process_frame
	await tree.process_frame
	await tree.create_timer(0.4, true).timeout
	_check(
		not GameAudio._master_bus.get_paused()
		and GameAudio._master_bus.get_mute() == (not enabled),
		"Pausing keeps FMOD output running."
	)
	_check(is_equal_approx(GameAudio._music_menu, 1.0), "Pausing pushes Music_Menu to 1.")
	var music_position: int = GameAudio._music.get_timeline_position()
	var effect_position: int = effect.get_timeline_position()
	await tree.create_timer(0.25, true).timeout
	_check(
		GameAudio._music.get_timeline_position() > music_position,
		"Music keeps playing while paused."
	)
	_check(
		effect.get_timeline_position() == effect_position,
		"Gameplay sounds hold their place while paused."
	)
	tree.paused = false
	await tree.process_frame
	await tree.process_frame
	await tree.create_timer(0.4).timeout
	_check(
		effect.get_timeline_position() > effect_position,
		"Gameplay sounds continue after the pause."
	)
	_check(is_zero_approx(GameAudio._music_menu), "Resuming releases Music_Menu.")
	_check(GameAudio._master_bus.get_mute() == (not enabled), "Resume respects the audio switch.")
	_check(
		AudioServer.is_bus_mute(0) == (not enabled or is_zero_approx(effects_volume)),
		"Resume restores native audio preferences."
	)
	_check(
		(
			GamePreferences.audio_enabled == enabled
			and GamePreferences.music_volume == music_volume
			and GamePreferences.effects_volume == effects_volume
		),
		"Pause and resume preserve saved audio preferences."
	)
	GameAudio.set_editor_muted(true)
	tree.paused = true
	await tree.create_timer(0.05).timeout
	tree.paused = false
	await tree.create_timer(0.05).timeout
	_check(
		GameAudio._master_bus.get_mute() and AudioServer.is_bus_mute(0),
		"Resuming preserves editor mute."
	)
	GameAudio.set_editor_muted(editor_muted)
	GameAudio.stop_loop(effect)


func _check_rotation_audio(demo: DemoScript) -> void:
	var audio: PlanetAudio = demo._planet_audio
	audio.update_rotation(0.01, false, 0.0)
	audio.update_rotation(0.01, true, 0.02)
	var first: FmodEvent = audio._rotate
	_check(first != null and first.is_valid(), "Dragging starts the rotation loop.")
	audio.update_rotation(0.01, true, 0.019)
	_check(audio._rotate == first, "Minor reverse jitter keeps the same loop.")
	audio.update_rotation(0.01, true, 0.0)
	_check(audio._rotate != first and audio._direction == -1, "A real reversal restarts the loop.")
	audio.update_rotation(audio.still_seconds, true, 0.0)
	_check(audio._rotate == null, "Holding still stops the rotation loop.")
	audio.update_rotation(0.01, true, 0.02)
	audio.update_rotation(0.01, false, 0.04)
	_check(audio._rotate == null, "Releasing drag stops the loop.")
	audio.update_rotation(0.1, false, 0.06)
	_check(audio._rotate == null, "Overview self-rotation stays silent.")


# One Candy_Acquire per monster caught: a single monster plays once, a giant
# or full net plays a capped run with shrinking gaps and fading volume.
func _check_candy_bursts(audio: Node) -> void:
	await get_tree().create_timer(1.5).timeout
	_check(audio._scheduled_candy.is_empty(), "Queued candy sounds finish playing.")
	audio.candy_from_net(500, 1)
	_check(
		(
			audio._scheduled_candy.size() == 1
			and is_equal_approx(
				float(audio._scheduled_candy[0]["time"]) - audio._clock,
				audio.candy_after_net_seconds
			)
		),
		"One netted monster plays one candy sound, after Net_Capture."
	)
	while not audio._scheduled_candy.is_empty():
		await get_tree().process_frame
	GameAudio.play(audio.CANDY_EVENT, {}, 0.5)
	var scaled: Array = GameAudio._scaled_effects.back()
	GameAudio._apply_effects_volume()
	_check(
		is_equal_approx(
			(scaled[0] as FmodEvent).get_volume(), GameAudio._effects_gain(scaled[2]) * 0.5
		),
		"The periodic volume refresh keeps a quieter candy voice quieter."
	)
	audio.monster_sucked(0.0, 600, 40)
	var queued: Array[Dictionary] = audio._scheduled_candy.duplicate()
	_check(
		queued.size() == audio.candy_max_voices,
		"A giant queues a capped candy run instead of sounding with the pop."
	)
	_check(
		is_equal_approx(float(queued[0]["time"]) - audio._clock, audio.candy_after_pop_seconds),
		"The pipe's first candy sound waits after SuckUp_Pop."
	)
	_check(
		is_equal_approx(
			float(queued[1]["time"]) - float(queued[0]["time"]), audio.candy_first_gap_seconds
		),
		"The second candy sound waits the first gap."
	)
	_check(
		is_equal_approx(float(queued[1]["volume"]), audio.candy_volume_decay),
		"Each candy sound in a run is quieter than the last."
	)
	var last_gap: float = float(queued[-1]["time"]) - float(queued[-2]["time"])
	_check(last_gap < audio.candy_first_gap_seconds, "Candy sound gaps shrink over a run.")
	_check(
		(
			is_equal_approx(audio._candy_value(1.0), audio._candy_value_range.x)
			and is_equal_approx(audio._candy_value(1000.0), audio._candy_value_range.y)
		),
		"Candy value maps 1 candy to the bottom and rich monsters to the top."
	)
	while not audio._scheduled_candy.is_empty():
		await get_tree().process_frame


# Vacuum_Loading follows one monster's capture bar and restarts per monster.
func _check_loading_audio(audio: Node) -> void:
	var first: Node = Node.new()
	var second: Node = Node.new()
	audio.update_loading(first, 0.4)
	var instance: FmodEvent = audio._loading
	_check(instance != null and instance.is_valid(), "Capturing starts the loading loop.")
	_check(
		is_equal_approx(instance.get_parameter_by_name("Loading_Progress"), 0.4),
		"Loading_Progress follows the capture bar."
	)
	audio.update_loading(first, 0.7)
	_check(audio._loading == instance, "The same monster keeps its loading loop.")
	audio.update_loading(second, 0.1)
	_check(audio._loading != instance, "A new monster restarts the loading loop.")
	audio.update_loading(null, 0.0)
	_check(audio._loading == null, "Finishing or losing the target stops the loading loop.")
	_check(audio._big_slime == null, "An ordinary monster plays no BigSilmeSuck.")
	audio.update_loading(first, 0.6, true)
	var big: FmodEvent = audio._big_slime
	_check(big != null and big.is_valid(), "A giant adds the BigSilmeSuck loop.")
	_check(
		is_equal_approx(big.get_parameter_by_name("Loading_Progress"), 0.6),
		"BigSilmeSuck follows the giant's capture bar."
	)
	audio.update_loading(null, 0.0)
	_check(audio._big_slime == null, "BigSilmeSuck stops with the loading loop.")
	audio.update_peel(first, 0.3)
	var peel: FmodEvent = audio._peel
	_check(peel != null and peel.is_valid(), "Pulling a monster off mucus starts the peel loop.")
	_check(
		is_equal_approx(peel.get_parameter_by_name("MucusPeel_Progress"), 0.3),
		"MucusPeel_Progress follows the peel bar."
	)
	audio.peel_snapped()
	_check(audio._peel == null, "Coming free of the mucus ends the peel loop.")
	audio.update_peel(second, 0.5)
	audio.stop_now()
	_check(audio._peel == null, "Stopping the vacuum stops the peel loop.")
	first.free()
	second.free()

# Candy_Combo climbs the whole ladder a quarter per stage, counting the capture
# being paid, and the stage-clear sound follows the on-screen burst.
func _check_combo_audio(demo: Node) -> void:
	var run: PrototypeRun = demo.run
	run.combo_level = 0
	_check(is_zero_approx(demo._combo_ladder_progress()), "No combo research keeps Candy_Combo at 0.")
	run.combo_level = 4
	run.combo_stage = 0
	run.combo_count = 0
	_check(
		is_equal_approx(demo._combo_ladder_progress(), 1.0 / 12.0),
		"The first capture of stage 1 sits a third of the way up its quarter."
	)
	run.combo_count = run.get_combo_target() - 1
	_check(
		is_equal_approx(demo._combo_ladder_progress(), 0.25),
		"The capture that clears stage 1 sounds at the top of its quarter."
	)
	run.combo_stage = 3
	run.combo_count = run.get_combo_target() - 1
	_check(is_equal_approx(demo._combo_ladder_progress(), 1.0), "Clearing stage 4 reaches 1.")
	run._reset_combo()
	run.combo_level = 0
	var played_before: int = demo._monster_audio._combo_clear_count
	demo._pipe.combo_burst_started.emit(2)
	_check(
		demo._monster_audio._combo_clear_count == played_before + 1,
		"Combo_StageClear plays as the combo burst appears."
	)
	_check(
		run.combo_interrupted.is_connected(demo._monster_audio.combo_broken),
		"Combo_Break follows a combo timeout."
	)

# A path whose FMOD folder moved still reaches its event by name.
func _check_path_resolution() -> void:
	var moved: String = "event:/SomeOldFolder/SuckUp_Pop"
	var resolved: String = GameAudio.resolve_event_path(moved)
	_check(
		resolved.get_file() == "SuckUp_Pop" and FmodServer.check_event_path(resolved),
		"A moved event is found by its name."
	)
	_check(GameAudio.has_events([moved]), "Moved events still count as available.")
	var loop: FmodEvent = GameAudio.start_loop("event:/OldFolder/Earth_Rotate")
	_check(loop != null and loop.is_valid(), "Loops start from a moved path.")
	GameAudio.stop_loop(loop)
	_check(
		GameAudio.resolve_event_path("event:/No_Such_Event") == "event:/No_Such_Event",
		"An unknown name is left unresolved."
	)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
