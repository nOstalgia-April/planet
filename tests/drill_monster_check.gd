extends Node

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")
const DemoScript = preload("res://scripts/disk_demo.gd")
const Discovery = preload("res://scripts/nest_discovery_presentation.gd")
const Drill = preload("res://scripts/drill_monster.gd")
const DrillTreasure = preload("res://scripts/drill_treasure.gd")
const PLAY_SCENE: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
var _failures: Array[String] = []
@onready var root: Window = get_tree().root


func _ready() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	_check_economy()
	await _check_live()
	if _failures.is_empty():
		print(
			"PASS: drill discovery, population, travel, basic suction, leave, input gates, treasure, art and restart"
		)
	else:
		for failure: String in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_economy() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS.duplicate() as PrototypeSettings
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	run._random.seed = 70341
	run._pending_nest_species = NestState.Species.DRILL
	_check(
		run.resolve_nest_spawn(Vector2(200, 0)),
		"Drill nest resolves through the existing discovery path."
	)
	for count: int in range(1, run.settings.drill_nest_limit):
		var weight: float = run.get_drill_discovery_weight()
		_check(
			is_equal_approx(weight, run.settings.drill_discovery_weight),
			"Drill target proportion stays constant below the cap."
		)
		run._pending_nest_species = NestState.Species.DRILL
		_check(
			run.resolve_nest_spawn(Vector2(0, 200 + count * 20)),
			"Multiple drill nests can resolve."
		)
	_check(run.get_drill_nest_count() == 4, "The default run allows four drill nests.")
	_check(run.get_drill_discovery_weight() == 0.0, "Discovery stops at the configured cap.")
	for index: int in range(1000):
		_check(
			run._choose_spawn_species() != NestState.Species.DRILL,
			"Capped species is excluded from rolls."
		)
	run._pending_nest_species = NestState.Species.DRILL
	_check(
		not run.resolve_nest_spawn(Vector2(0, 200)), "Resolution also enforces the configured cap."
	)
	var nest: NestState = run.get_nest(3)
	for level: int in range(3):
		nest.level = level
		nest.alive_slimes = 0
		nest.spawn_clock = 0.0
		var capacity: int = [1, 2, 4][level]
		_check(run.get_nest_population_limit(3) == capacity, "Drill capacity follows 1/2/4.")
		for count: int in range(capacity):
			run._advance_nest_population(nest, run.get_nest_spawn_interval(3))
			_check(
				nest.alive_slimes == count + 1, "Every refresh creates exactly one drill monster."
			)
		run._advance_nest_population(nest, 100.0)
		_check(
			nest.alive_slimes == capacity and nest.spawn_clock == 0.0,
			"Full nests stop without banking bursts."
		)
	var counts: Dictionary[int, int] = {10: 0, 30: 0, 100: 0}
	for index: int in range(20000):
		var reward: int = run.roll_drill_treasure()
		counts[reward] += 1
	_check(
		absf(float(counts[10]) / 20000.0 - 0.70) < 0.02, "Common treasure uses 70 percent weight."
	)
	_check(absf(float(counts[30]) / 20000.0 - 0.25) < 0.02, "Rich treasure uses 25 percent weight.")
	_check(absf(float(counts[100]) / 20000.0 - 0.05) < 0.01, "Jackpot uses 5 percent weight.")
	run.combo_level = 3
	run.combo_count = 10
	run.base_value_level = 2
	nest.alive_slimes = 1
	var before: int = run.candy
	_check(run.collect_slime(3), "Treasure settles on a valid catch.")
	_check(
		run.candy - before in [50, 150, 500],
		"Treasure follows current normal slime value without extra combo multipliers."
	)
	before = run.candy
	_check(
		not run.collect_slime(3) and run.candy == before, "Empty population cannot settle twice."
	)
	for level: int in [0, 2, SETTINGS.base_value_upgrade_costs.size()]:
		run.base_value_level = level
		for seed_value: int in [3, 7, 41, 109]:
			run._random.seed = seed_value
			nest.alive_slimes = 1
			before = run.candy
			_check(run.collect_slime(3), "Ordinary treasure can settle.")
			var ordinary_reward: int = run.candy - before
			run._random.seed = seed_value
			nest.alive_slimes = 1
			before = run.candy
			_check(run.collect_slime(3, -1, 1, true), "Valuable treasure can settle.")
			_check(
				run.candy - before == ordinary_reward * SETTINGS.valuable_reward_multiplier,
				"Valuable drill multiplies the same treasure roll at the current base value."
			)
			before = run.candy
			_check(
				not run.collect_slime(3, -1, 1, true) and run.candy == before,
				"Valuable treasure cannot settle twice."
			)
	nest.is_tamed = true
	run._advance_nest_population(nest, 100.0)
	_check(nest.alive_slimes == 0, "Automation stops new drill spawns.")
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	_check(run.nests.size() == 2 and run.candy == 0, "Restart resets the run.")
	run.free()


func _check_live() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var demo: DemoScript = PLAY_SCENE.instantiate() as DemoScript
	root.add_child(demo)
	get_tree().current_scene = demo
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	demo._layout.close_panels()
	demo._window_has_focus = true
	await get_tree().process_frame
	demo.run._pending_nest_species = NestState.Species.DRILL
	demo._on_nest_spawn_requested(NestState.Species.DRILL)
	var discovery: Discovery = demo.get_node("NestDiscoveryPresentation") as Discovery
	for _frame: int in range(240):
		var delta: float = 0.05 * Engine.time_scale
		demo._view._process(delta)
		discovery._process(delta)
		if discovery.phase == Discovery.Phase.IDLE:
			break
	var nest: NestState = demo.run.get_nest(3)
	_check(nest != null, "A real drill nest fits the planet.")
	if nest == null:
		demo.queue_free()
		await get_tree().process_frame
		return
	print(
		"Drill footprint/site count: ", demo._nest_site_distance, "/", demo._nest_site_angles.size()
	)
	demo.run._advance_nest_population(nest, demo.run.get_nest_spawn_interval(3))
	var actor: Drill = demo._slimes[-1] as Drill
	_check(actor != null, "Live spawn uses drill scene.")
	actor.set_process(false)
	actor._rng.seed = 28139
	_check(
		not actor.can_capture() and not actor.can_net_capture() and not actor.can_fuse(),
		"Launch is protected from suction, nets and fusion."
	)
	var states: Dictionary = {}
	var farthest: float = 0.0
	var within_range: bool = true
	var on_surface: bool = true
	for step: int in range(9000):
		actor._process(0.05)
		states[actor.phase] = true
		var offset: float = absf(angle_difference(nest.position.angle(), actor.position.angle()))
		farthest = maxf(farthest, offset)
		within_range = within_range and offset <= PI * actor.range_fraction + 0.001
		on_surface = on_surface and demo._planet.contains_surface_point(actor.position)
		if actor.phase != Drill.Phase.EXPOSED:
			_check(
				not actor.apply_capture(10.0, 0.1, actor.position),
				"Underground and transition phases reject capture directly."
			)
	_check(states.size() == 6, "The live actor visits every phase of its repeating cycle.")
	_check(
		is_equal_approx(actor.art_settings.get_monster_scale(PrototypeSlime.Species.DRILL), 0.55),
		"All drill phases share the small size from the approved screenshot."
	)
	_check(
		within_range and on_surface,
		"Travel respects the fixed two-thirds arc and playable surface."
	)
	_check(farthest > 1.5, "Drill reaches distant regions instead of staying beside its nest.")
	_check_travel_cycles(actor)
	demo._refresh_overview()
	_check(
		demo._overview.population_counts == Vector2i.ZERO,
		"Overview does not reveal treasure monster positions."
	)
	actor._enter_phase(Drill.Phase.EXPOSED, actor.exposed_seconds, &"夹夹")
	demo._view.zoom_steps(-1.0, false)
	demo._view.focus_surface(nest.position.angle(), false)
	actor.position = demo._planet.project_to_surface(nest.position * 0.9)
	actor._update_surface_rotation()
	actor._sync_art()
	demo.run.net_unlocked = true
	demo._net_anchor = actor.get_capture_point()
	demo._resolve_net()
	_check(
		demo._slimes.has(actor) and nest.alive_slimes == 1,
		"The real net path leaves the drill untouched."
	)
	_check_input_gates(demo, actor)
	_check_escape(demo, actor)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_feedback(demo, actor)
	_check_suction_capture(demo, actor, nest)
	if "--capture" in OS.get_cmdline_user_args():
		for size: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
			root.size = size
			demo._apply_layout()
			await _capture("caught", size)
	await _check_valuable_live(demo, nest)
	demo.restart_run()
	_check(
		demo._slimes.is_empty() and demo._effects.get_child_count() == 0,
		"Restart clears drill actors, feedback and pending visuals."
	)
	demo.queue_free()
	await get_tree().process_frame


func _check_travel_cycles(actor: Drill) -> void:
	actor._rng.seed = 51927
	var counts: Dictionary[int, int] = {2: 0, 3: 0, 4: 0, 5: 0}
	for cycle: int in range(512):
		actor._enter_phase(Drill.Phase.DIVE, 0.875, &"钻地")
		actor._advance_phase()
		var expected_legs: int = actor._turns_remaining + 1
		var legs: int = 0
		while actor.phase == Drill.Phase.TRAVEL and legs < 6:
			legs += 1
			actor._advance_phase()
			_check(actor.phase == Drill.Phase.PAUSE, "Each movement ends with a pause.")
			actor._advance_phase()
		_check(
			actor.phase == Drill.Phase.EMERGE and legs == expected_legs,
			"Mole emerges after the sampled total, including its first long movement."
		)
		_check(legs >= 2 and legs <= 5, "Every underground cycle has 2–5 movements.")
		if counts.has(legs):
			counts[legs] += 1
	_check(counts[2] > 0 and counts[5] > 0, "Both movement-count limits are reachable.")
	_check(
		counts[3] > counts[2] and counts[3] > counts[4] and counts[4] > counts[5],
		"Movement counts peak at three and five remains a rare tail."
	)
	print("Drill movement counts over 512 cycles: ", counts)


func _check_input_gates(demo: DemoScript, actor: Drill) -> void:
	demo._view_blocks_tool_until_release = false
	demo._window_has_focus = true
	var point: Vector2 = actor.get_capture_hit_rect().get_center()
	_mouse(point, false)
	_check(not actor.has_node("CaptureCue"), "The hold prompt is removed.")
	demo._window_has_focus = false
	_drive_interaction(demo, point, 1.0)
	_check(actor.capture_progress == 0.0, "Unfocused window blocks suction.")
	demo._window_has_focus = true
	demo._view.presentation_locked = true
	_drive_interaction(demo, point, 1.0)
	_check(actor.capture_progress == 0.0, "Presentation blocks suction.")
	demo._view.presentation_locked = false
	demo._view.begin_drag(point)
	_drive_interaction(demo, point, 1.0)
	_check(actor.capture_progress == 0.0, "Planet drag blocks suction.")
	demo._view.end_drag()
	demo._layout._show_technology()
	_drive_interaction(demo, point, 1.0)
	_check(actor.capture_progress == 0.0, "Technology panel blocks suction.")
	demo._layout.close_panels()
	demo._view_blocks_tool_until_release = false


func _check_escape(demo: DemoScript, actor: Drill) -> void:
	actor._enter_phase(Drill.Phase.EXPOSED, 0.15, &"夹夹")
	actor._process(0.2)
	_check(actor.phase == Drill.Phase.DIVE, "Uncaptured mole returns underground.")
	_check(not actor.apply_capture(10.0, 0.1, actor.position), "Buried mole rejects suction.")
	actor._enter_phase(Drill.Phase.EXPOSED, 0.15, &"夹夹")
	demo._capture_at(0.01, actor.get_capture_point(), true)
	actor._process(0.2)
	_check(actor.phase == Drill.Phase.EXPOSED, "Active suction pauses the escape timer.")
	demo._capture_at(0.0, actor.get_capture_point(), false)
	_check(actor.capture_progress == 0.0 and not actor.art._suction, "Leaving resets suction.")
	actor._process(0.2)
	_check(actor.phase == Drill.Phase.DIVE, "Leaving resumes the escape timer.")
	actor._enter_phase(Drill.Phase.EXPOSED, actor.exposed_seconds, &"夹夹")


func _check_suction_capture(demo: DemoScript, actor: Drill, nest: NestState) -> void:
	actor._enter_phase(Drill.Phase.EXPOSED, actor.exposed_seconds, &"夹夹")
	var point: Vector2 = actor.get_capture_hit_rect().get_center()
	var before: int = demo.run.candy
	_mouse(point, false)
	demo._select_tool(DemoScript.ToolMode.PIPE)
	for level: int in range(SETTINGS.pipe_capture_seconds.size()):
		demo.run.pipe_level = level
		var duration: float = demo.run.get_pipe_capture_seconds()
		_drive_interaction(demo, point, duration * 0.5)
		_check(
			is_equal_approx(actor.capture_progress, 0.5),
			"Suction follows the pipe upgrade duration."
		)
		_check(actor.art._suction, "Suction uses the struggling expression.")
		_check(demo._capture_targets.has(actor), "Mole uses the normal capture target list.")
		demo._capture_at(0.0, actor.get_capture_point(), false)
		_check(actor.capture_progress == 0.0, "Leaving resets partial capture.")
	demo.run.pipe_level = 0
	var duration: float = demo.run.get_pipe_capture_seconds()
	_drive_interaction(demo, point, duration * 0.5)
	_mouse(point, true)
	_mouse(point, false)
	_check(
		is_equal_approx(actor.capture_progress, 0.5), "Mouse release does not cancel basic suction."
	)
	_drive_interaction(demo, point, duration * 0.5 + 0.001)
	_check(
		actor.consumed and not demo._slimes.has(actor) and nest.alive_slimes == 0,
		"Suction collects one mole."
	)
	var earned: int = demo.run.candy - before
	var multiplier: int = demo.run.get_base_value()
	if actor.high_value:
		multiplier *= SETTINGS.valuable_reward_multiplier
	_check(
		earned in [10 * multiplier, 30 * multiplier, 100 * multiplier],
		"Treasure reward retains its value."
	)
	_drive_interaction(demo, point, 2.0)
	_check(demo.run.candy == before + earned, "Capture pays only once.")
	_check(demo._effects.get_child(-1) is DrillTreasure, "Capture creates treasure feedback.")


func _drive_interaction(demo: DemoScript, point: Vector2, seconds: float) -> void:
	var target: Vector2 = demo._world.get_global_transform_with_canvas().affine_inverse() * point
	demo._drive_tool(seconds, target, demo.update_pointer_release_state())


func _check_valuable_live(demo: DemoScript, nest: NestState) -> void:
	demo.run.valuable_level = 1
	demo._spawn_directions[nest.nest_id] = 8
	demo.run._advance_nest_population(nest, demo.run.get_nest_spawn_interval(nest.nest_id))
	var actor: Drill = demo._slimes[-1] as Drill
	actor.set_process(false)
	_check(
		actor.high_value and actor.art == actor.valuable_art, "Research spawns upgraded drill art."
	)
	for clip: StringName in [&"跳出", &"夹夹", &"钻地", &"待机"]:
		for frame: int in range(actor.art.get_frame_count(clip)):
			actor.art.show_frame(clip, frame)
			_check(
				actor.get_source_texture().resource_path.contains("高价值怪物/地鼠"),
				"Every visible drill pose retains the upgraded individual."
			)
	actor._enter_phase(Drill.Phase.EXPOSED, actor.exposed_seconds, &"夹夹")
	actor.position = demo._planet.project_to_surface(nest.position * 0.9)
	actor._update_surface_rotation()
	actor.refresh_presentation()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_feedback(demo, actor)
	_check_suction_capture(demo, actor, nest)
	demo.run._advance_nest_population(nest, demo.run.get_nest_spawn_interval(nest.nest_id))
	var ordinary: Drill = demo._slimes[-1] as Drill
	_check(
		not ordinary.high_value and ordinary.art == ordinary.ordinary_art,
		"The next spawn preserves the eight-spawn cadence."
	)


func _capture_feedback(demo: DemoScript, actor: Drill) -> void:
	actor._enter_phase(Drill.Phase.EXPOSED, actor.exposed_seconds, &"夹夹")
	var point: Vector2 = actor.get_capture_hit_rect().get_center()
	_mouse(point, false)
	_drive_interaction(demo, point, demo.run.get_pipe_capture_seconds() * 0.5)
	await _capture("valuable_suction" if actor.high_value else "ordinary_suction", root.size)
	demo._capture_at(0.0, actor.get_capture_point(), false)


func _capture(label: String, size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame: int in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/mole_basic_suction_20261017")
	var path: String = (
		"res://artifacts/mole_basic_suction_20261017/%s_%dx%d.png" % [label, size.x, size.y]
	)
	_check(root.get_texture().get_image().save_png(path) == OK, "Fresh capture saved.")
	print("CAPTURE: ", path)


func _mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
