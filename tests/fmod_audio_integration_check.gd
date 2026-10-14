extends Node

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const MenuScene: PackedScene = preload("res://scenes/主菜单/主菜单.tscn")
const TechnologyPage = preload("res://scripts/ui/technology_page.gd")
const PlanetAudio = preload("res://scripts/planet_audio.gd")

var _failures: int = 0


func _ready() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var tree: SceneTree = get_tree()
	var root: Window = tree.root
	_check(GameAudio.banks_loaded, "The main game banks load successfully.")
	var menu: Control = MenuScene.instantiate() as Control
	root.add_child(menu)
	tree.current_scene = menu
	await tree.process_frame
	_check(GameAudio._music_path == "event:/Mx/Mx_MainMenu", "The menu starts its music.")
	_check(GameAudio._music != null and GameAudio._music.is_valid(), "Menu music is valid.")
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
		not demo._is_technology_unaffordable(page.selected_key), "A locked research is not unaffordable."
	)
	demo.run.candy = 1000
	_check(demo.run.purchase_technology("cultivation"), "Cultivation unlocks global research.")
	demo.run.candy = 0
	for id: String in ["valuable", "giant"]:
		page.selected_key = id
		page.refresh(demo.run)
		_check(
			demo._is_technology_unaffordable(page.selected_key), "Global research checks its cost: " + id
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
	demo._monster_audio.monster_sucked(10, 3, 1)
	demo._monster_audio.candy_from_net(2, 2)
	demo._monster_audio.golden_collected()
	_check(demo._monster_audio._golden_ready, "Golden_Mon is available.")
	await _check_candy_bursts(demo._monster_audio)
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
		demo._planet_audio._rotate == null, "Opening the paused technology page stops rotation audio."
	)
	await tree.create_timer(0.4).timeout
	_check(is_equal_approx(GameAudio._music_volume, 1.0), "Gameplay music fades fully in.")
	_check(GameAudio._fading_out.is_empty(), "The previous music finishes fading out.")
	demo._layout.close_panels()
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
	menu = MenuScene.instantiate() as Control
	root.add_child(menu)
	tree.current_scene = menu
	await tree.process_frame
	_check(
		GameAudio._music_path == "event:/Mx/Mx_MainMenu", "Returning to the menu switches music back."
	)
	tree.current_scene = null
	menu.queue_free()
	await tree.process_frame
	if _failures == 0:
		print(
			"PASS: FMOD banks, music crossfades, monster/UI/net events, global research, collection visuals, rotation audio and vacuum reset."
		)
	tree.quit(0 if _failures == 0 else 1)


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
	_check(audio._scheduled_candy.is_empty(), "One monster plays one candy sound, however rich.")
	audio.monster_sucked(0, 600, 40)
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
		is_equal_approx(audio._candy_value(1.0), audio._candy_value_range.x)
		and is_equal_approx(audio._candy_value(1000.0), audio._candy_value_range.y),
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

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
