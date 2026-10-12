extends Node

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")
const DemoScript = preload("res://scripts/disk_demo.gd")
const Drill = preload("res://scripts/drill_monster.gd")
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
			"PASS: declining drill discovery, four-nest cap, 1/2/4 population, travel, capture gating, treasure, art and restart"
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
	var discoveries: int = 0
	for index: int in range(300):
		if run._choose_spawn_species() == NestState.Species.DRILL:
			discoveries += 1
	_check(discoveries > 0, "Drill nest participates in natural discovery.")
	run._pending_nest_species = NestState.Species.DRILL
	_check(
		run.resolve_nest_spawn(Vector2(200, 0)),
		"Drill nest resolves through the existing discovery path."
	)
	var previous_weight: float = run.settings.drill_discovery_weight
	for count: int in range(1, run.settings.drill_nest_limit):
		var weight: float = run.get_drill_discovery_weight()
		_check(
			weight > 0.0 and weight < previous_weight,
			"Each existing drill nest lowers discovery weight."
		)
		previous_weight = weight
		var can_roll: bool = false
		for index: int in range(1000):
			can_roll = can_roll or run._choose_spawn_species() == NestState.Species.DRILL
		_check(can_roll, "Additional drill nests remain discoverable below the cap.")
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
	await get_tree().process_frame
	demo.run._pending_nest_species = NestState.Species.DRILL
	demo._on_nest_spawn_requested(NestState.Species.DRILL)
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
		within_range and on_surface,
		"Travel respects the fixed two-thirds arc and playable surface."
	)
	_check(farthest > 1.5, "Drill reaches distant regions instead of staying beside its nest.")
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
	if "--capture" in OS.get_cmdline_user_args():
		await _capture(demo, actor)
	for level: int in range(SETTINGS.pipe_capture_seconds.size()):
		demo.run.pipe_level = level
		_check(
			is_equal_approx(demo._capture_seconds_for(actor), 0.5),
			"Drill capture estimate stays at 0.5 seconds at every pipe level."
		)
		demo._capture_at(0.25, actor.get_capture_point(), true)
		_check(
			not actor.consumed and is_equal_approx(actor.capture_progress, 0.5),
			"Real pipe reaches half progress after 0.25 seconds at every upgrade level."
		)
		_check(actor.art._suction, "Half-captured drill shows its suction expression.")
		demo._capture_at(0.0, actor.get_capture_point(), false)
		_check(
			actor.capture_progress == 0.0 and not actor.art._suction,
			"Release resets progress and restores the drill expression."
		)
	var before: int = demo.run.candy
	demo._capture_at(0.49, actor.get_capture_point(), true)
	_check(not actor.consumed, "Even the fastest pipe cannot capture drill before 0.5 seconds.")
	demo._capture_at(0.011, actor.get_capture_point(), true)
	_check(
		demo._slimes.is_empty() and nest.alive_slimes == 0,
		"The real pipe catches exposed drill and frees its nest slot."
	)
	_check(demo.run.candy - before in [10, 30, 100], "Real pipe awards one randomized treasure.")
	_check(demo._effects.get_child_count() > 0, "Capture creates the burst-and-return effect.")
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/drill_treasure_1920x1080.png")
	demo.restart_run()
	_check(
		demo._slimes.is_empty() and demo._effects.get_child_count() == 0,
		"Restart clears drill actors and pending visuals."
	)
	demo.queue_free()
	await get_tree().process_frame


func _capture(demo: DemoScript, actor: Drill) -> void:
	# Let the production squash finish before checking the resting silhouette.
	demo._nest_views[2]._art._spawn.animation_player.advance(1.0)
	for size: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		demo._apply_layout()
		actor._update_surface_rotation()
		actor._sync_art()
		demo._pipe.hide()
		for frame: int in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://artifacts/drill_monster_%dx%d.png" % [size.x, size.y]
		)
	var nest_view: NestView = demo._nest_views[2]
	for level: int in range(4):
		nest_view.update_state(level, level == 3, 3)
		nest_view._art.set_stage(level, false)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/drill_nest_stage_%d.png" % level)
		if level < 3:
			nest_view.pulse_spawn()
			nest_view._art._spawn.animation_player.advance(0.25)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				"res://artifacts/drill_nest_spawn_%d.png" % level
			)
	nest_view.update_state(0, false, 3)
	nest_view._art.set_stage(0, false)
	for phase_name: String in ["launch", "dive", "tunnel", "exposed", "suction"]:
		match phase_name:
			"launch":
				actor.launch(Vector2.RIGHT)
				actor._process(0.5)
			"dive":
				actor._advance_phase()
			"tunnel":
				actor._advance_phase()
			"exposed":
				actor._enter_phase(Drill.Phase.EXPOSED, actor.exposed_seconds, &"夹夹")
			"suction":
				actor.apply_capture(
					0.25, demo.run.get_pipe_capture_seconds(), actor.get_capture_point()
				)
		actor.art.animation_player.advance(0.4)
		actor._sync_art()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/drill_phase_%s.png" % phase_name)
	actor.capture_progress = 0.0
	actor.release_capture(0.0)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
