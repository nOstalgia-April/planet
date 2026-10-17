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
	await _check_effect_instance_lifetimes()
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
	_check_presentation_quiet(demo._monster_audio)
	_check_drill_audio(demo._monster_audio)
	_check_upgrade_hints(demo)
	await _check_terrain_pops(demo._planet_audio)
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
	await _check_tool_switch_audio(demo)
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


func _check_effect_instance_lifetimes() -> void:
	var near_view_gain: float = GameAudio._near_view_gain
	var audio_enabled: bool = GamePreferences.audio_enabled
	var effects_volume: float = GamePreferences.effects_volume
	GamePreferences.audio_enabled = true
	GamePreferences.effects_volume = 0.37
	GamePreferences.changed.emit()
	GameAudio.set_near_view_gain(1.0)
	var effect: FmodEvent = GameAudio.start_loop("event:/Vacuum/Vacuum_Loading")
	_check(effect != null and effect.is_valid(), "A managed effect is available during the check.")
	# Vacuum_On starts Vacuum_Loop inside FMOD, without creating a Godot wrapper.
	GameAudio.play("event:/Vacuum/Vacuum_On")
	for index: int in range(8):
		GameAudio.play("event:/UI/Button_Hover")
		await get_tree().create_timer(0.025).timeout
	await get_tree().create_timer(0.25).timeout
	GameAudio._apply_effects_volume()
	_check(is_equal_approx(effect.get_volume(), 0.37), "Valid effects still receive their volume.")
	GameAudio.set_near_view_gain(0.0)
	_check(is_zero_approx(effect.get_volume()), "Overview still silences valid near-view effects.")
	GameAudio.set_near_view_gain(1.0)
	_check(is_equal_approx(effect.get_volume(), 0.37), "Near view restores valid effect volume.")
	GameAudio.play("event:/Vacuum/Vacuum_Off")
	GameAudio.stop_loop(effect)
	await get_tree().create_timer(0.25).timeout
	GameAudio._apply_effects_volume()
	GameAudio.set_near_view_gain(near_view_gain)
	GamePreferences.audio_enabled = audio_enabled
	GamePreferences.effects_volume = effects_volume
	GamePreferences.changed.emit()


func _check_audio_pause() -> void:
	var tree: SceneTree = get_tree()
	var enabled: bool = GamePreferences.audio_enabled
	var music_volume: float = GamePreferences.music_volume
	var effects_volume: float = GamePreferences.effects_volume
	var editor_muted: bool = GameAudio._editor_muted
	var effect: FmodEvent = GameAudio.start_loop("event:/Earth_Rotate")
	await tree.create_timer(0.4).timeout
	# Menus (settings, technology page) pause the game: gameplay sounds hold
	# their place, while music (under Music_Menu) and UI sounds keep playing.
	tree.paused = true
	# The game turns the vacuum off as it pauses; Vacuum_Off must still run
	# to stop Vacuum_Loop, which FMOD started and the freeze cannot reach.
	GameAudio.play("event:/Vacuum/Vacuum_Off")
	await tree.process_frame
	await tree.process_frame
	await tree.create_timer(0.4, true).timeout
	var gameplay_bus: FmodBus = FmodServer.get_bus(GameAudio.GAMEPLAY_BUS)
	_check(gameplay_bus.get_mute(), "Pausing mutes the gameplay bus, Vacuum_Loop included.")
	var vacuum_off: Array = FmodServer.get_event("event:/Vacuum/Vacuum_Off").get_instance_list()
	_check(
		vacuum_off.size() > 0 and vacuum_off.all(func(e: FmodEvent) -> bool: return not e.get_paused()),
		"Vacuum_Off keeps running through the pause to stop Vacuum_Loop."
	)
	_check(
		(
			not GameAudio._master_bus.get_paused()
			and GameAudio._master_bus.get_mute() == (not enabled)
		),
		"Pausing keeps FMOD output running."
	)
	_check(is_equal_approx(GameAudio._music_menu, 1.0), "Pausing pushes Music_Menu to 1.")
	_check(
		is_equal_approx(FmodServer.get_global_parameter_by_name("Music_Menu"), 1.0),
		"FMOD receives Music_Menu = 1 (the music's 800 Hz low-pass)."
	)
	var music_position: int = GameAudio._music.get_timeline_position()
	var effect_position: int = effect.get_timeline_position()
	await tree.create_timer(0.25, true).timeout
	_check(
		(
			not GameAudio._music.get_paused()
			and GameAudio._music.get_timeline_position() > music_position
		),
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
		(
			not GameAudio._music.get_paused()
			and GameAudio._music.get_timeline_position() > music_position
		),
		"Music is still playing after the pause."
	)
	_check(
		effect.get_timeline_position() > effect_position,
		"Gameplay sounds continue after the pause."
	)
	_check(is_zero_approx(GameAudio._music_menu), "Resuming releases Music_Menu.")
	_check(not gameplay_bus.get_mute(), "Resuming unmutes the gameplay bus.")
	_check(
		is_zero_approx(FmodServer.get_global_parameter_by_name("Music_Menu")),
		"FMOD receives Music_Menu = 0 after resuming."
	)
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


# Keys 1/2 and the tool dock play Switch-Vacuum / Switch-Net instead of Click;
# a locked net opens its upgrade with an ordinary Click.
func _check_tool_switch_audio(demo: DemoScript) -> void:
	var vacuum: FmodEventDescription = FmodServer.get_event(UiAudio.SWITCH_VACUUM_EVENT)
	var net: FmodEventDescription = FmodServer.get_event(UiAudio.SWITCH_NET_EVENT)
	var click: FmodEventDescription = FmodServer.get_event(UiAudio.CLICK_EVENT)
	_check(UiAudio._switch_ready, "Switch-Vacuum and Switch-Net are in the Bank.")
	# Earlier clicks finishing mid-check would change the counts below.
	var deadline: int = Time.get_ticks_msec() + 3000
	while (
		click.get_instance_count() + vacuum.get_instance_count() + net.get_instance_count() > 0
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame
	var clicks: int = click.get_instance_count()
	var vacuums: int = vacuum.get_instance_count()
	demo._quick_pipe_button.button_down.emit()
	_check(vacuum.get_instance_count() == vacuums + 1, "The vacuum button plays Switch-Vacuum.")
	_check(click.get_instance_count() == clicks, "The vacuum button no longer plays Click.")
	var was_unlocked: bool = demo.run.net_unlocked
	demo.run.net_unlocked = true
	var nets: int = net.get_instance_count()
	demo._quick_net_button.button_down.emit()
	_check(net.get_instance_count() == nets + 1, "The net button plays Switch-Net.")
	_check(click.get_instance_count() == clicks, "The net button no longer plays Click.")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	vacuums = vacuum.get_instance_count()
	demo._unhandled_key_input(key)
	_check(vacuum.get_instance_count() == vacuums + 1, "Key 1 plays Switch-Vacuum.")
	key.keycode = KEY_2
	nets = net.get_instance_count()
	demo._unhandled_key_input(key)
	_check(net.get_instance_count() == nets + 1, "Key 2 plays Switch-Net.")
	demo.run.net_unlocked = false
	nets = net.get_instance_count()
	demo._quick_net_button.button_down.emit()
	_check(
		net.get_instance_count() == nets and click.get_instance_count() == clicks + 1,
		"A locked net plays Click, not Switch-Net."
	)
	demo.run.net_unlocked = was_unlocked
	demo._select_tool(DemoScript.ToolMode.PIPE)
	vacuums = vacuum.get_instance_count()
	demo._select_tool(DemoScript.ToolMode.PIPE)
	_check(vacuum.get_instance_count() == vacuums, "A silent tool refresh plays no switch sound.")


# Candy_Combo climbs the whole ladder a quarter per stage, counting the capture
# being paid, and the stage-clear sound follows the on-screen burst.
func _check_combo_audio(demo: Node) -> void:
	var run: PrototypeRun = demo.run
	run.combo_level = 0
	_check(
		is_zero_approx(demo._combo_ladder_progress()), "No combo research keeps Candy_Combo at 0."
	)
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
	run.combo_stage_completed.emit(2, 0)
	_check(
		demo._monster_audio._combo_clear_count == played_before + 1,
		"Combo_StageClear plays the moment a combo stage is cleared, before the burst."
	)
	_check(
		run.combo_interrupted.is_connected(demo._monster_audio.combo_broken),
		"Combo_Break follows a combo timeout."
	)


# A new nest's presentation silences spawn bursts and chatter, queued ones
# included, while the new nest's own appearance still sounds.
func _check_presentation_quiet(audio: Node) -> void:
	audio.monster_spawned(NestState.Species.SLIME)
	audio.monster_sounds_muted = true
	_check(
		audio._pending_spawns.is_empty() and audio._scheduled_triggers.is_empty(),
		"Muting drops spawn sounds that were still queued."
	)
	audio.monster_spawned(NestState.Species.SLIME)
	_check(audio._pending_spawns.is_empty(), "No spawn sound queues while muted.")
	var chatter: FmodEventDescription = FmodServer.get_event("event:/Monsters/SlimeMon_Rand")
	var before: int = chatter.get_instance_count()
	for _frame: int in range(120):
		audio.update_chatter(1.0, {NestState.Species.SLIME: 100})
	_check(chatter.get_instance_count() == before, "No chatter plays while muted.")
	var appear: FmodEventDescription = FmodServer.get_event("event:/Nest/Slime_NestAppear")
	var appeared: int = appear.get_instance_count()
	audio.nest_appeared(NestState.Species.SLIME)
	_check(appear.get_instance_count() == appeared + 1, "The new nest still plays its appearance.")
	audio.monster_sounds_muted = false
	audio.monster_spawned(NestState.Species.SLIME)
	_check(not audio._pending_spawns.is_empty(), "Spawn sounds return after the presentation.")
	audio._pending_spawns.clear()


# Drill_Crawl loops only while a drill crawls; Drill_OutofDirt plays as it
# jumps out. Both stay quiet during a new nest's presentation.
func _check_drill_audio(audio: Node) -> void:
	const Drill = preload("res://scripts/drill_monster.gd")
	var out: FmodEventDescription = FmodServer.get_event(audio.DRILL_OUT_EVENT)
	audio._on_drill_phase(Drill.Phase.TRAVEL, 101)
	var crawl: FmodEvent = audio._crawling.get(101)
	_check(crawl != null and crawl.is_valid(), "A crawling drill starts Drill_Crawl.")
	audio._on_drill_phase(Drill.Phase.PAUSE, 101)
	_check(not audio._crawling.has(101), "A pausing drill stops Drill_Crawl.")
	audio._on_drill_phase(Drill.Phase.TRAVEL, 101)
	audio.monster_sounds_muted = true
	_check(audio._crawling.get(101) == null, "A presentation silences the crawl.")
	var outs: int = out.get_instance_count()
	audio._on_drill_phase(Drill.Phase.EMERGE, 102)
	_check(out.get_instance_count() == outs, "No Drill_OutofDirt during a presentation.")
	audio.monster_sounds_muted = false
	_check(audio._crawling.get(101) != null, "The crawl resumes after the presentation.")
	outs = out.get_instance_count()
	audio._on_drill_phase(Drill.Phase.EMERGE, 101)
	_check(out.get_instance_count() == outs + 1, "A drill jumping out plays Drill_OutofDirt.")
	_check(not audio._crawling.has(101), "Jumping out ends Drill_Crawl.")
	audio._on_drill_phase(Drill.Phase.TRAVEL, 103)
	audio._stop_crawl(103)
	_check(audio._crawling.is_empty(), "A drill leaving the scene stops its crawl.")


# A tool's hint plays once when its upgrade becomes affordable and the tab
# comes up on its own; hovers, menus and view switches do not repeat it.
func _check_upgrade_hints(demo: DemoScript) -> void:
	const Dock = preload("res://scripts/ui/bottom_dock.gd")
	var dock: Dock = demo._layout._tool_dock as Dock
	for tool: int in range(2):
		var hint: FmodEventDescription = FmodServer.get_event(
			GameAudio.resolve_event_path(UiAudio.UPGRADE_HINT_EVENTS[tool])
		)
		var hints: int = hint.get_instance_count()
		dock.upgrade_offered.emit(tool)
		_check(hint.get_instance_count() == hints + 1, "An offered tab %d plays its hint." % tool)
	var offers: Array[int] = []
	var record: Callable = func(tool: int) -> void: offers.append(tool)
	dock.upgrade_offered.connect(record)
	var saved: Array[int] = dock.states.duplicate()
	dock.suppress(false)
	dock.set_near_view(true)
	_check(dock.is_visible_in_tree() and not dock._view_transitioning, "The dock is shown.")
	dock.states[0] = Dock.ToolState.SHORT
	dock._refresh_visibility()
	dock._hovered[0] = true
	dock._refresh_visibility()
	_check(offers.is_empty(), "Hovering an unaffordable upgrade plays no hint.")
	dock._hovered[0] = false
	dock.states[0] = Dock.ToolState.READY
	dock._refresh_visibility()
	_check(offers == [0], "An upgrade becoming affordable hints once.")
	dock.suppress(true)
	dock.suppress(false)
	dock.set_near_view(false)
	dock.set_near_view(true)
	dock._hovered[0] = true
	dock._refresh_visibility()
	_check(offers == [0], "Menus, view switches and hovers do not repeat the hint.")
	dock._hovered[0] = false
	dock.states[0] = Dock.ToolState.SHORT
	dock._refresh_visibility()
	dock.states[0] = Dock.ToolState.READY
	dock._refresh_visibility()
	_check(offers == [0, 0], "The next affordable upgrade hints again.")
	dock.upgrade_offered.disconnect(record)
	dock.states = saved
	dock._refresh_visibility()


# Rocks pop at the start of "appear", trees a moment later; a replay hidden
# behind the overview stays silent.
func _check_terrain_pops(audio: Node) -> void:
	const TerrainScene: PackedScene = preload("res://scenes/场景动画/山丘树木.tscn")
	var terrain: Node2D = TerrainScene.instantiate() as Node2D
	terrain.set_process(false)
	add_child(terrain)
	var pops: Array[bool] = []
	terrain.popped.connect(func(trees: bool) -> void: pops.append(trees))
	terrain.replay()
	terrain._process(0.0)
	_check(pops == [false], "The rocks pop as the terrain appears.")
	terrain._process(terrain.tree_pop_seconds)
	_check(pops == [false, true], "The trees pop once, a moment later.")
	terrain._process(1.0)
	_check(pops.size() == 2, "Each group pops only once per appearance.")
	terrain.set_near_blend(0.0)
	terrain.replay()
	terrain._process(1.0)
	_check(pops.size() == 2, "A hidden terrain stays silent.")
	terrain.queue_free()
	var tree_pop: FmodEventDescription = FmodServer.get_event(audio.TERRAIN_POP_EVENT)
	var played: int = tree_pop.get_instance_count()
	audio.terrain_popped(false)
	audio.terrain_popped(true)
	_check(tree_pop.get_instance_count() == played + 2, "Rocks and trees each play TreePopUp.")
	await get_tree().process_frame


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
