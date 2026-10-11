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
	_check(GameAudio._music_path == "event:/Mx_MainMenu", "The menu starts its music.")
	_check(GameAudio._music != null and GameAudio._music.is_valid(), "Menu music is valid.")
	tree.current_scene = null
	menu.queue_free()
	await tree.process_frame
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	tree.current_scene = demo
	demo.set_process(false)
	await tree.process_frame
	_check(GameAudio._music_path == "event:/Mx_GamePlay", "Gameplay switches the music.")
	_check(demo._vacuum_audio._ready_to_play, "The vacuum events exist in the updated banks.")
	_check(demo._monster_audio.is_ready(), "The monster and candy events exist.")
	_check(demo._planet_audio._ready_to_play, "The planet rotation event exists.")
	_check(UiAudio.is_ready(), "The button and upgrade events exist.")
	var page: TechnologyPage = demo.get_node("HUD/Interface/Technology") as TechnologyPage
	demo.run.candy = 0
	page.selected_key = "valuable"
	_check(
		not demo._is_technology_page_unaffordable(page), "A locked research is not unaffordable."
	)
	demo.run.candy = 1000
	_check(demo.run.purchase_technology("cultivation"), "Cultivation unlocks global research.")
	demo.run.candy = 0
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	for id: String in ["valuable", "giant"]:
		page.selected_key = id
		page.refresh(demo.run)
		_check(
			demo._is_technology_page_unaffordable(page), "Global research checks its cost: " + id
		)
		page.purchase.gui_input.emit(click)
		demo.run.candy = 1000
		demo._on_technology_upgrade(id)
		_check(
			demo.run.get_technology_level(id) == 1, "Global research purchases successfully: " + id
		)
		_check(
			not demo._is_technology_page_unaffordable(page),
			"Completed research is not unaffordable."
		)
		demo.run.candy = 0
	demo._monster_audio.monster_sucked(10)
	demo._monster_audio.candy_from_net()
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
	demo._vacuum_audio.update(0.1, true, true)
	demo.restart_run()
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
		GameAudio._music_path == "event:/Mx_MainMenu", "Returning to the menu switches music back."
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


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
