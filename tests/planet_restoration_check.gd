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
	await _capture("initial")
	for _stage: int in range(3):
		_check(_game.run.upgrade_nest(1), "fixture upgrades succeed")
	_check(
		_game._restoration.unlocked_species.is_empty(),
		"wait for the actual flower, not the purchase"
	)
	for _frame: int in range(480):
		if not _game._restoration.unlocked_species.is_empty():
			break
		await get_tree().process_frame
	_check(_game._restoration.unlocked_species == [0], "real flower completion unlocks pink once")
	_check(_game._view.presentation_locked, "flower reveal locks player camera input")
	var old_zoom: float = _game._view.target_zoom
	_game._view.zoom_steps(-1.0)
	_check(_game._view.target_zoom == old_zoom, "camera input cannot skip confirmation")
	_game._restoration._process(0.4)
	_check(not _game._view.is_overview(), "confirmation holds near view")
	_game._restoration._process(0.41)
	_check(_game._view.is_overview(), "confirmation forces overview")
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
		_game._restoration.bright_background.modulate.a == 1.0,
		"all colors enable bright background"
	)
	_check(_game._restoration.core.modulate.a == 0.0, "old core does not obscure restored globe")
	var rotation: float = _game._world.rotation
	_game._view._process(1.0)
	_check(not is_equal_approx(rotation, _game._world.rotation), "completed globe rotates")
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
	_game._restoration.reveal_flower(1, 0)
	_game.restart_run()
	_game._restoration._process(10.0)
	_check(
		not _game._view.presentation_locked and not _game._view.is_overview(),
		"restart cancels queued camera work"
	)
	_game._restoration.reveal_flower(1, 0)
	_game._restoration._process(0.8)
	_game._view._process(1.0)
	_game._restoration._process(0.0)
	_game._restoration._process(1.0)
	_game.restart_run()
	_check(
		_game._planet_art.color_progress == Vector3.ZERO, "restart cancels partially painted color"
	)
	await _capture("restart")
	_game.queue_free()
	await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print(
			"PASS: monster-clear victory, actual flower trigger, color queue, input lock, final animation/background, rotation and restart."
		)
	get_tree().quit(0 if _failures.is_empty() else 1)


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
	for nest: NestState in run.nests:
		for _stage: int in range(3):
			run.upgrade_nest(nest.nest_id)
	_check(not run.is_complete, "all nests automated with remaining monsters does not win")
	run.collect_slime(1, -1, 2)
	_check(not run.is_complete, "other nests and fused population still count")
	run.net_unlocked = true
	run.collect_net_batch([2], [], [3])
	_check(run.is_complete and _goals == 1, "final net capture wins exactly once")
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
		"res://artifacts/restoration_20261011_" + label + ".png"
	)
	print("CAPTURE ", label, " ", Time.get_datetime_string_from_system())


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
