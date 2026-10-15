extends Node

const PlayScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const PlayScript = preload("res://features/场景预览/游玩预览.gd")
const Restoration = preload("res://scripts/planet_restoration.gd")

var _failures: Array[String] = []
var _goals: int = 0
var _game: PlayScript
var _captures: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_captures = "--capture" in OS.get_cmdline_user_args()
	_check_victory()
	_game = PlayScene.instantiate() as PlayScript
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	# Drive the real scene deliberately without unrelated random discovery/capture.
	_game.set_process(false)
	_game._view.set_process(false)
	_game._restoration.set_process(false)
	_game.run.candy = 100000
	_game.run.purchase_technology("cultivation")
	_game.run.purchase_technology("automation")
	await get_tree().process_frame
	_check_core_white(0.0, "Initial scene")
	await _capture("initial")
	for _stage: int in range(3):
		_check(_game.run.upgrade_nest(1), "fixture upgrades succeed")
	_check(
		_game._restoration.unlocked_species.is_empty(),
		"wait for the actual flower, not the purchase"
	)
	# The three growth clips take about 2.17 seconds; fast rendering can exhaust
	# a frame-count limit before the real flower animation finishes.
	var flower_deadline_msec: int = Time.get_ticks_msec() + 10000
	while (
		_game._restoration.unlocked_species.is_empty()
		and Time.get_ticks_msec() < flower_deadline_msec
	):
		await get_tree().process_frame
	_check(_game._restoration.unlocked_species == [0], "real flower completion unlocks pink once")
	_check(_game._view.presentation_locked, "flower reveal locks player camera input")
	var old_zoom: float = _game._view.target_zoom
	_game._view.zoom_steps(-1.0)
	_check(_game._view.target_zoom == old_zoom, "camera input cannot skip confirmation")
	_game._restoration._process(0.4)
	_check(not _game._view.is_overview(), "confirmation holds near view")
	_game._restoration._process(0.41)
	_check(
		_game._restoration.phase == Restoration.Phase.TERRAIN,
		"flower confirmation first restores visible terrain"
	)
	_game._restoration._process(_game._restoration.terrain_seconds)
	_check(_game._view.is_overview(), "colored terrain then forces overview")
	_game._view._process(1.0)
	_game._restoration._process(0.0)
	_game._restoration._process(1.2)
	_check(
		is_equal_approx(_game._planet_art.color_progress.x, 0.5),
		"top-down fill progresses over time"
	)
	_game._show_completion()
	_check(not _game._completion.visible, "victory panel waits for the color presentation")
	_game._completion_tween.kill()
	_game._restoration.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.04, true).timeout
	_check(is_equal_approx(_game._planet_art.color_progress.x, 0.5), "pause freezes reveal timing")
	get_tree().paused = false
	_game._restoration.set_process(false)
	await _capture("pink_half")
	_game._restoration.reveal_flower(2, 0)
	_check(
		_game._restoration.unlocked_species.size() == 1,
		"duplicate species does not queue another reveal"
	)
	_game._restoration._process(1.2)
	_game._restoration._process(1.2)
	_check(not _game._view.presentation_locked, "ordinary reveal releases camera")
	await _capture("pink_complete")
	# Test queue order for flowers appearing before the current reveal completes.
	_game._restoration.reveal_flower(3, 1)
	_game._restoration.reveal_flower(4, 2)
	_game._restoration._process(0.8)
	_game._view._process(1.0)
	_game._restoration._process(0.0)
	_game._restoration._process(2.4)
	_game._restoration._process(1.2)
	_check(_game._restoration.completed_species == [0, 1], "queued colors present serially")
	_check(
		_game._restoration.phase == Restoration.Phase.CONFIRM, "last color has its own confirmation"
	)
	_game._restoration._process(0.8)
	_game._view._process(1.0)
	_game._restoration._process(0.0)
	_game._restoration._process(1.2)
	_check(
		_game._restoration.bright_background.modulate.a == 0.0,
		"bright background waits for last fill"
	)
	await _capture("green_half")
	_game._restoration._process(1.2)
	_check(
		_game._restoration.phase == Restoration.Phase.FINISH, "last fill starts final transition"
	)
	_game._restoration._process(1.0)
	_game._restoration._process(1.2)
	_check(
		_game._planet_art.restored_mix == 1.0, "all colors switch to the supplied animated globe"
	)
	_game._planet_art.animation_player.seek(0.25, true)
	_game._planet_art._process(0.0)
	_check(
		(
			_game._planet_art._blend_material.get_shader_parameter("restored_texture")
			== _game._planet_art.restored_frames[1]
		),
		"restored globe uses the shared five-FPS animation clock"
	)
	_check(
		_game._restoration.bright_background.modulate.a == 0.0,
		"all colors retain the colored background while an existing nest is not automated"
	)
	_check(_game._restoration.core.modulate.a == 0.0, "old core does not obscure restored globe")
	_check_core_white(0.0, "Three colors before full automation")
	var rotation: float = _game._world.rotation
	_game._view._process(1.0)
	_check(not is_equal_approx(rotation, _game._world.rotation), "completed globe rotates")
	await _capture("three_colors_before_automation")
	_game.run.get_nest(2).alive_slimes = 1
	for _stage: int in range(3):
		_check(_game.run.upgrade_nest(2), "last existing nest can become automated")
	_check(not _game.run.is_complete, "background automation fixture still has a monster")
	_game._restoration._process(0.0)
	_game._restoration._process(0.8)
	_game._view._process(1.0)
	_game._restoration._process(0.0)
	_check(
		_game._restoration.phase == Restoration.Phase.BACKGROUND,
		"all current nests automated starts the background transition without a new color"
	)
	_game._restoration._process(0.5)
	_check(
		is_equal_approx(_game._restoration.bright_background.modulate.a, 0.5),
		"background fades to white after full automation"
	)
	_check_core_white(0.5, "Three-color white transition midpoint")
	_game._restoration._process(0.5)
	_game._restoration._process(1.2)
	_check(
		_game._restoration.bright_background.modulate.a == 1.0,
		"all current nests automated enables white even with monsters remaining"
	)
	_check_core_white(1.0, "Three-color white transition complete")
	for species: int in range(3):
		_game._population_palette.emphasize_species(species, 10.0)
		_game._population_palette.advance_population(Vector3.ZERO, 0.5)
		_check_core_white(1.0, "Temporary emphasis during white presentation")
		_game._population_palette.advance_population(Vector3.ZERO, 0.5)
		_check_core_white(1.0, "Temporary emphasis settled during white presentation")
	await _capture("complete")
	_game._view.zoom_steps(1.0, false)
	await _capture("complete_near")
	_game.restart_run()
	_check(_game._planet_art.color_progress == Vector3.ZERO, "restart removes every color")
	_check(_game._planet_art.restored_mix == 0.0, "restart restores original globe")
	_check(
		_game._restoration.bright_background.modulate.a == 0.0,
		"restart restores original background"
	)
	_check_core_white(0.0, "Restart after three-color white presentation")
	_game._restoration.reveal_flower(1, 0)
	_game.restart_run()
	_game._restoration._process(10.0)
	_check(
		not _game._view.presentation_locked and not _game._view.is_overview(),
		"restart cancels queued camera work"
	)
	_game._restoration.reveal_flower(1, 0)
	_game._restoration._process(0.8)
	if _game._restoration.phase == Restoration.Phase.TERRAIN:
		_game._restoration._process(_game._restoration.terrain_seconds)
	_game._view._process(1.0)
	_game._restoration._process(0.0)
	_game._restoration._process(1.0)
	_game.restart_run()
	_check(
		_game._planet_art.color_progress == Vector3.ZERO, "restart cancels partially painted color"
	)
	await _capture("restart")
	# Full automation is sufficient even when only one species exists.
	_game.run.candy = 100000
	_game.run.purchase_technology("cultivation")
	_game.run.purchase_technology("automation")
	for nest: NestState in _game.run.nests:
		nest.alive_slimes = 1
		for _stage: int in range(3):
			_game.run.upgrade_nest(nest.nest_id)
	_game._restoration.reveal_flower(1, 0)
	_game._restoration._process(0.8)
	if _game._restoration.phase == Restoration.Phase.TERRAIN:
		_game._restoration._process(_game._restoration.terrain_seconds)
	_game._view._process(1.0)
	_game._restoration._process(0.0)
	_game._restoration._process(2.4)
	_game._restoration._process(1.2)
	_game._restoration._process(0.5)
	_check_core_white(0.5, "Single-species white transition midpoint")
	_game._restoration._process(0.5)
	_game._restoration._process(1.2)
	_check(
		(
			_game._restoration.unlocked_species == [0]
			and _game._restoration.bright_background.modulate.a == 1.0
		),
		"all current nests automated enables white without unlocking all three colors"
	)
	_check(
		_game._planet_art.restored_mix == 0.0 and _game._restoration.core.modulate.a == 1.0,
		"Single-species white presentation keeps the original animated core visible."
	)
	_check_core_white(1.0, "Single-species white transition complete")
	_game.restart_run()
	_check_core_white(0.0, "Restart after single-species white presentation")
	_game.queue_free()
	await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print(
			"PASS: monster-clear victory, flower trigger, color queue, automation-gated white background, rotation and restart."
		)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_core_white(expected: float, context: String) -> void:
	var core_material: ShaderMaterial = (
		_game._population_palette.core_sprite.material as ShaderMaterial
	)
	var globe_material: ShaderMaterial = _game._planet_art.sprite.material as ShaderMaterial
	var core_white: float = core_material.get_shader_parameter("core_white_mix")
	var globe_white: float = globe_material.get_shader_parameter("core_white_mix")
	_check(
		(
			is_equal_approx(core_white, expected)
			and is_equal_approx(globe_white, expected)
			and is_equal_approx(_game._restoration.bright_background.modulate.a, expected)
		),
		context + ": both core materials remain synchronized with the white background."
	)


func _check_victory() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = (
		preload("res://resources/prototype_settings.tres").duplicate() as PrototypeSettings
	)
	add_child(run)
	var positions: Array[Vector2] = [Vector2(-80, -200), Vector2(80, -200)]
	run.start_run(positions)
	_check(not run.is_complete, "empty opening does not win before monsters appear")
	run.goal_completed.connect(func() -> void: _goals += 1)
	run.candy = 100000
	run.purchase_technology("cultivation")
	run.purchase_technology("automation")
	run.get_nest(1).alive_slimes = 2
	run.get_nest(2).alive_slimes = 3
	# This fixture isolates automation and cleanup after the three color unlocks.
	run.unlocked_colors.assign([0, 1, 2])
	# Isolate population victory from the independently tracked flower colors.
	run.unlocked_colors.assign([0, 1, 2])
	for nest: NestState in run.nests:
		for _stage: int in range(3):
			run.upgrade_nest(nest.nest_id)
	_check(not run.is_complete, "all nests automated with remaining monsters does not win")
	run.collect_slime(1, -1, 2)
	_check(not run.is_complete, "other nests and fused population still count")
	run.net_unlocked = true
	_check(run.collect_net_batch([2], [], [3]) == 0, "net cannot harvest the final fused body")
	_check(not run.is_complete, "an immune giant still prevents victory")
	run.collect_slime(2, -1, 3)
	_check(run.is_complete and _goals == 1, "final giant suction wins exactly once")
	run.advance(200.0)
	_check(
		run.get_species_population(0) == 0 and _goals == 1, "victory does not spawn monsters again"
	)
	run.start_run(positions)
	run.get_nest(1).species = NestState.Species.DRILL
	run.get_nest(1).alive_slimes = 1
	run.collect_slime(1)
	_check(
		not run.is_complete and run.completed_nests == 0 and _goals == 1,
		"last drill capture cannot win before all nests are automated"
	)
	run.advance(20.0)
	_check(run.get_species_population(0) > 0, "untamed nests keep producing after an early clear")
	run.start_run(positions)
	_check(not run.is_complete and run.completed_nests == 0, "restart resets victory")
	run.free()


func _capture(label: String) -> void:
	if not _captures:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"res://artifacts/restoration_20261014_automation_" + label + ".png"
	)
	print("CAPTURE ", label, " ", Time.get_datetime_string_from_system())


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
