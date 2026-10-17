extends Node

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")
const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Demo = preload("res://scripts/disk_demo.gd")
const Drill = preload("res://scripts/drill_monster.gd")
const Cleanup = preload("res://scripts/flower_cleanup_effect.gd")
const OUTPUT: String = "res://artifacts/flower_cleanup_01a14bae"

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_rules()
	await _check_live()
	print("Flower cleanup: %d failures." % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_rules() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS.duplicate() as PrototypeSettings
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	run._add_nest(NestState.Species.MUCUS, Vector2(200, 0))
	run._add_nest(NestState.Species.DRILL, Vector2(-200, 0))
	run.governance_level = 3
	_check(not run.are_all_nests_automated(), "Research alone does not enable cleanup.")
	for nest: NestState in run.nests:
		nest.alive_slimes = 1
		nest.is_tamed = true
		nest.level = 3
	run.nests.back().is_tamed = false
	_check(not run.collect_flower_target(1, 1, 1, false), "One unfinished nest blocks cleanup.")
	run.nests.back().is_tamed = true
	run.nests.back().is_discovering = true
	_check(not run.are_all_nests_automated(), "Discovery must finish first.")
	run.nests.back().is_discovering = false
	run.completed_nests = run.nests.size()
	run.combo_level = 1
	run.combo_count = 1
	run.combo_stage_candy = 1
	run.combo_remaining = 2.0
	var before: int = run.candy
	_check(run.collect_flower_target(1, 3, 1, true), "Valuable slime can be cleaned.")
	_check(run.candy == before + 3, "Valuable payout is preserved.")
	_check(
		run.combo_count == 1 and run.combo_stage_candy == 1 and run.combo_remaining == 2.0,
		"Cleanup neither advances nor refreshes the manual combo."
	)
	_check(
		not run.collect_flower_target(1, 3, 1, true), "Cannot pay for the same population twice."
	)
	run.nests[1].alive_slimes = 8
	_check(
		run.collect_flower_target(2, 24, 8, true), "Giant population and reward settle together."
	)
	_check(run.nests[1].alive_slimes == 0 and run.candy == before + 27, "No giant units remain.")
	_check(run.collect_flower_target(3, 2, 1, false), "Mucus monsters can be cleaned.")
	run.settings.drill_reward_weights = PackedInt32Array([1, 0, 0])
	before = run.candy
	_check(run.collect_flower_target(4, 0, 1, true), "Drill rewards use the treasure roll.")
	_check(
		run.candy == before + run.get_base_value() * 10 * run.settings.valuable_reward_multiplier,
		"Valuable drill treasure multiplier is preserved."
	)
	_check(not run.is_complete, "Completion still waits for all flower colors.")
	for nest: NestState in run.nests:
		run.record_flower(nest.nest_id)
	_check(run.is_complete, "Last monster and all flowers finish the run.")
	run.free()


func _automate(demo: Demo, index: int) -> void:
	var nest: NestState = demo.run.nests[index]
	nest.is_tamed = true
	nest.level = 3
	demo.run.completed_nests += 1
	demo._nest_views[index].update_state(3, true, 3, false)


func _spawn(demo: Demo, index: int, point: Vector2) -> PrototypeSlime:
	var nest: NestState = demo.run.nests[index]
	nest.alive_slimes += 1
	demo._on_slime_requested(nest.nest_id)
	var actor: PrototypeSlime = demo._slimes.back()
	actor.restore_to_surface(point)
	actor.set_process(false)
	return actor


func _check_live() -> void:
	var demo: Demo = PLAY.instantiate() as Demo
	add_child(demo)
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	demo.run.settings = demo.run.settings.duplicate() as PrototypeSettings
	demo.run.governance_level = 3
	for actor: PrototypeSlime in demo._slimes:
		actor.queue_free()
	demo._slimes.clear()
	for nest: NestState in demo.run.nests:
		nest.alive_slimes = 0
	var home: Vector2 = demo.run.nests[0].position
	var near: PrototypeSlime = _spawn(demo, 0, home + Vector2(8, 8))
	var far: PrototypeSlime = _spawn(demo, 1, -home)
	_automate(demo, 0)
	demo._advance_flower_cleanup(10.0)
	_check(demo._slimes.size() == 2, "Partial automation does not remove actors.")
	_automate(demo, 1)
	demo._capture_targets.append(near)
	_check(demo._find_flower_target(home) == null, "Active suction target is protected.")
	demo._capture_targets.clear()
	demo._net_phase = Demo.NetPhase.CLOSING
	demo._net_anchor = near.get_capture_point()
	_check(demo._find_flower_target(home) == null, "Active net target is protected.")
	demo._net_phase = Demo.NetPhase.IDLE
	_check(demo._find_flower_target(home) == near, "Nearest in-range actor is selected.")
	demo._advance_flower_cleanup(demo.run.settings.flower_cleanup_interval * 0.5)
	_check(demo._slimes.size() == 2, "Cleanup respects its interval.")
	demo._advance_flower_cleanup(demo.run.settings.flower_cleanup_interval * 0.5)
	_check(demo._slimes.size() == 1 and demo._slimes[0] == far, "Far actors remain outside range.")
	_check(demo.run.nests[0].alive_slimes == 0, "Live actor removal matches population.")
	await get_tree().process_frame
	var saved: Dictionary = demo.capture_gameplay_save()
	_check(demo.accepts_gameplay_save(saved), "Cleanup leaves a consistent save.")
	demo.restore_gameplay_save(saved)
	demo.set_process(false)
	_check(demo.run.are_all_nests_automated(), "Loading preserves cleanup eligibility.")
	_check(demo._flower_cleanup_elapsed == 0.0, "Loading resets the interval without pending hits.")
	demo.flower_cleanup_scene = null
	demo._slimes[0].position = home
	demo._slimes[0].set_process(false)
	demo._advance_flower_cleanup(demo.run.settings.flower_cleanup_interval)
	_check(demo._slimes.is_empty(), "Cleanup works without its optional effect.")
	# Underground drills are not deleted before they surface.
	demo.run._add_nest(NestState.Species.DRILL, home + Vector2(40, 0), true)
	demo.run.nests.back().is_discovering = false
	_automate(demo, 2)
	var drill: Drill = _spawn(demo, 2, home) as Drill
	drill.phase = Drill.Phase.TRAVEL
	_check(demo._find_flower_target(home) == null, "Underground drill waits.")
	drill.phase = Drill.Phase.EXPOSED
	_check(demo._find_flower_target(home) == drill, "Surfaced drill becomes eligible.")
	demo._advance_flower_cleanup(demo.run.settings.flower_cleanup_interval)
	_check(demo._slimes.is_empty(), "Surfaced drill is settled.")
	# Overview and pause use the same gameplay loop, without depending on visible effects.
	var overview_actor: PrototypeSlime = _spawn(demo, 0, home)
	demo._view.restore_save(demo._world.rotation, 0.0)
	_check(demo._view.is_overview(), "Overview setup reaches the distant view.")
	demo._flower_cleanup_elapsed = 0.0
	demo.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.15, true).timeout
	_check(
		demo._flower_cleanup_elapsed == 0.0 and not overview_actor.consumed,
		"Pause freezes the gameplay cleanup clock."
	)
	get_tree().paused = false
	await get_tree().create_timer(demo.run.settings.flower_cleanup_interval + 0.15).timeout
	demo.set_process(false)
	_check(demo._slimes.is_empty(), "The live gameplay loop also clears monsters in overview.")
	demo.restart_run()
	demo.set_process(false)
	_check(demo._flower_cleanup_elapsed == 0.0, "Restart resets cleanup timing.")
	_check(not demo.run.are_all_nests_automated(), "Restart disables cleanup.")
	_check(demo._effects.get_child_count() == 0, "Restart removes old effects.")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture(demo)
	demo.queue_free()
	await get_tree().process_frame


func _capture(demo: Demo) -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	demo.flower_cleanup_scene = load("res://scenes/effects/flower_cleanup.tscn") as PackedScene
	demo._pipe.hide()
	demo._net.hide()
	demo.run.governance_level = 3
	for index: int in range(demo.run.nests.size()):
		_automate(demo, index)
	var view: NestView = demo._nest_views[0]
	var turn: float = angle_difference(demo._world.rotation, -PI / 2.0 - view.position.angle())
	var radius: float = (
		demo._planet.radius * demo._world.scale.x * demo._view.projection_root.scale.x
	)
	demo._view.begin_drag(Vector2.ZERO)
	demo._view.drag_to(Vector2(turn * radius, 0.0))
	demo._view.end_drag()
	await get_tree().create_timer(0.2).timeout
	var target: PrototypeSlime = _spawn(demo, 0, view.position.rotated(0.18) * 0.94)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "/before.png")
	demo._collect_flower_target(view, target)
	var effect: Cleanup = null
	for child: Node in demo._effects.get_children():
		if child is Cleanup:
			effect = child
	_check(effect != null, "Visible cleanup creates its effect.")
	await get_tree().create_timer(0.07).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "/hit.png")
	get_tree().paused = true
	var alpha: float = effect.modulate.a if is_instance_valid(effect) else -1.0
	await get_tree().create_timer(0.2, true).timeout
	_check(
		is_instance_valid(effect) and effect.modulate.a == alpha, "Pause freezes cleanup effect."
	)
	get_tree().paused = false
	await get_tree().create_timer(1.0).timeout
	_check(not is_instance_valid(effect), "Cleanup effect frees itself.")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT + "/after.png")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
