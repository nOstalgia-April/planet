extends SceneTree

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const PlayScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")
const Fusion = preload("res://scripts/giant_slime_fusion.gd")
const HarvestEffect = preload("res://scripts/giant_harvest_effect.gd")

var _failures: int = 0


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	_check_global_research()
	_check_local_groups()
	_check_population_settlement()
	await _check_live_fusion()
	await _check_all_nests()
	await _check_demo_balance()
	await _check_visibility_and_tools()
	await _check_live_settlement()
	await _check_harvest_stream()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_showcase()
	if "--capture-harvest" in OS.get_cmdline_user_args():
		await _capture_harvest_showcase()
	if _failures == 0:
		print(
			"PASS: global research, local offscreen fusion, independent giants, overflow, protected tools, weighted rewards, overview and restart"
		)
	quit(0 if _failures == 0 else 1)


func _check_global_research() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS.duplicate() as PrototypeSettings
	run.settings.giant_fusion_threshold = 12
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	run.candy = 10000
	for id: String in ["valuable", "giant"]:
		_check(not run.purchase_technology(id), "Both global branches require cultivation.")
	_check(run.candy == 10000, "Locked research never charges.")
	run.purchase_technology("cultivation")
	for id: String in ["valuable", "giant"]:
		var before: int = run.candy
		var cost: int = run.get_technology_cost(id)
		_check(
			run.purchase_technology(id) and run.candy == before - cost,
			"Global research charges once."
		)
		_check(not run.purchase_technology(id), "Global research has no per-nest repurchase.")
	var contributions: Dictionary[int, int] = {1: 4, 2: 8}
	run.get_nest(1).alive_slimes = 4
	run.get_nest(2).alive_slimes = 8
	_check(
		not run.fuse_population(contributions, 1), "A smaller contributor cannot own the fusion."
	)
	_check(run.fuse_population(contributions, 2), "The greatest contributor owns the full fusion.")
	_check(
		run.get_nest(1).alive_slimes == 0 and run.get_nest(2).alive_slimes == 12,
		"Fusion permits overflow and conserves population."
	)
	_check(not run.fuse_population(contributions, 2), "A consumed batch cannot transfer twice.")
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	_check(
		run.valuable_level == 0 and not run.giant_unlocked,
		"Restart clears both global technologies."
	)
	run.free()


func _check_local_groups() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS.duplicate() as PrototypeSettings
	run.settings.giant_fusion_threshold = 12
	run.start_run([Vector2(-200, 0), Vector2(0, 0)])
	run._add_nest(NestState.Species.MUCUS, Vector2(200, 0))
	run.giant_unlocked = true
	var actors: Array[PrototypeSlime] = []
	for nest: NestState in run.nests:
		for _index: int in range(4):
			var actor: PrototypeSlime = PrototypeSlime.new()
			actor.nest_id = nest.nest_id
			actors.append(actor)
	_check(
		Fusion.plan_batches(run, actors, 99.0).is_empty(),
		"Disjoint activities cannot pool twelve actors."
	)
	_check(
		Fusion.plan_batches(run, actors, 100.0).is_empty(),
		"A-B-C overlap chains cannot merge non-overlapping A and C."
	)
	var plans: Array[Fusion.Plan] = Fusion.plan_batches(run, actors, 200.0)
	_check(
		plans.size() == 1 and plans[0].owner_id == 1,
		"Mutually overlapping nests fuse; ties choose the lowest nest ID."
	)
	actors[0].population_units = 12
	_check(
		Fusion.plan_batches(run, actors, 200.0).is_empty(),
		"Existing giants are excluded from the next threshold."
	)
	for actor: PrototypeSlime in actors:
		actor.free()
	run.free()


func _make_demo(scene: PackedScene = DemoScene) -> DemoScript:
	var demo: DemoScript = scene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	demo.run.settings = SETTINGS.duplicate() as PrototypeSettings
	# Small fixtures exercise exact accounting independently of the demo balance.
	demo.run.settings.giant_fusion_threshold = 12
	demo.run.candy = 100000
	return demo


func _offscreen_pair(
	demo: DemoScript,
	second_species: NestState.Species = NestState.Species.SLIME,
	counts: Vector2i = Vector2i(4, 8)
) -> void:
	demo.run._add_nest(NestState.Species.SLIME, demo._planet.get_nest_position(PI * 0.5 - 0.32))
	demo.run._add_nest(second_species, demo._planet.get_nest_position(PI * 0.5 + 0.32))
	_spawn_normals(demo, 3, counts.x)
	_spawn_normals(demo, 4, counts.y)


func _spawn_normals(demo: DemoScript, nest_id: int, count: int) -> void:
	for _index: int in range(count):
		demo.run.get_nest(nest_id).alive_slimes += 1
		demo._on_slime_requested(nest_id)
		var actor: PrototypeSlime = demo._slimes.back()
		actor._process(actor.launch_seconds)
		actor.set_process(false)
		actor.restore_to_surface(demo.run.get_nest(nest_id).position * 0.82)
		actor.set_process(false)


func _enable_fusion(demo: DemoScript) -> void:
	demo.run.purchase_technology("cultivation")
	demo.run.purchase_technology("giant")


func _giants(demo: DemoScript) -> Array[PrototypeSlime]:
	var result: Array[PrototypeSlime] = []
	for actor: PrototypeSlime in demo._slimes:
		if actor.population_units > 1:
			result.append(actor)
	return result


func _check_live_fusion() -> void:
	var demo: DemoScript = _make_demo()
	_offscreen_pair(demo)
	demo._advance_giant_fusion(2.0)
	_check(_giants(demo).is_empty(), "Fusion stays locked before global research.")
	_enable_fusion(demo)
	var gold: PrototypeSlime = demo._slimes[0]
	gold.configure_species(PrototypeSlime.Species.SLIME, true, 6)
	var before: int = demo.run.candy
	demo._advance_giant_fusion(1.0)
	var first: PrototypeSlime = _giants(demo)[0]
	first.set_process(false)
	_check(
		demo._slimes.size() == 1 and first.nest_id == 4,
		"Four plus eight becomes one giant at the eight-contributor nest."
	)
	_check(
		first.population_units == 12 and first.reward == 28,
		"Fusion preserves all twelve units and gold value."
	)
	_check(
		first.body_size > 30 and first.position.distance_to(demo.run.get_nest(4).position) < 70,
		"The new giant is large and appears near its owner."
	)
	_check(
		demo.run.candy == before and demo.run.combo_count == 0,
		"Fusion itself never awards candy or combo."
	)
	_check(
		demo.run.get_nest(3).alive_slimes == 0 and demo.run.get_nest(4).alive_slimes == 12,
		"One host overflows while the other regains its slots."
	)
	demo.run._advance_nest_population(demo.run.get_nest(4), 100.0)
	_check(demo._slimes.size() == 1, "The overflowing host obeys its normal production cap.")
	_spawn_normals(demo, 3, 10)
	demo._advance_giant_fusion(1.0)
	_check(
		_giants(demo).size() == 1 and first.population_units == 12,
		"Ten fresh actors never feed or retrigger the existing giant."
	)
	demo.run.upgrade_nest(4)
	demo.run._advance_nest_population(
		demo.run.get_nest(4), demo.run.get_nest_spawn_interval(4) + 0.01
	)
	for actor: PrototypeSlime in demo._slimes:
		if actor.population_units == 1:
			actor._process(actor.launch_seconds)
			actor.restore_to_surface(demo.run.get_nest(actor.nest_id).position * 0.82)
			actor.set_process(false)
	demo._advance_giant_fusion(1.0)
	_check(
		_giants(demo).size() == 2 and first.population_units == 12,
		"A second threshold produces an independent giant."
	)
	_check(_giants(demo)[1].nest_id == 3, "The next batch chooses its own largest contributor.")
	var total: int = 0
	for actor: PrototypeSlime in demo._slimes:
		total += actor.population_units
	_check(
		total == demo.run.get_species_population(NestState.Species.SLIME),
		"Runtime entities and weighted nest ledger agree."
	)
	demo.run.purchase_technology("base_value")
	_check(first.reward == 56, "A real fused giant retains gold value after a breakthrough.")
	before = demo.run.candy
	var occupied: int = demo.run.get_nest(4).alive_slimes
	demo._capture_at(2.0, first.get_capture_point(), true)
	_check(
		demo.run.candy == before + 56 and demo.run.get_nest(4).alive_slimes == occupied - 12,
		"One suction collects the real giant and all its occupied slots."
	)
	demo.restart_run()
	_check(
		_giants(demo).is_empty() and not demo.run.giant_unlocked,
		"Restart clears every giant and research."
	)
	current_scene = null
	demo.queue_free()
	await process_frame


func _check_all_nests() -> void:
	var demo: DemoScript = _make_demo()
	_spawn_normals(demo, 1, 1)
	var original: PrototypeSlime = demo._slimes[0]
	demo.run.purchase_technology("cultivation")
	demo.run.purchase_technology("valuable")
	_spawn_normals(demo, 1, 8)
	_spawn_normals(demo, 2, 8)
	demo.run._add_nest(NestState.Species.MUCUS, demo._planet.get_nest_position(PI * 0.5))
	_spawn_normals(demo, 3, 1)
	var golden_sources: Array[int] = []
	for actor: PrototypeSlime in demo._slimes:
		if actor.high_value and not golden_sources.has(actor.nest_id):
			golden_sources.append(actor.nest_id)
	_check(
		not original.high_value, "Global high-value research preserves already-born individuals."
	)
	_check(
		golden_sources.size() == 3,
		"Both existing nests and a newly discovered mucus nest produce gold."
	)
	_check(demo._slimes.back().reward == 12, "Global gold research preserves mucus species value.")
	demo.restart_run()
	demo.run.candy = 100000
	_offscreen_pair(demo, NestState.Species.MUCUS)
	_enable_fusion(demo)
	demo._slimes[0].configure_species(PrototypeSlime.Species.SLIME, true, 6)
	demo._advance_giant_fusion(1.0)
	var giant: PrototypeSlime = _giants(demo)[0]
	_check(
		giant.species == PrototypeSlime.Species.MUCUS and giant.nest_id == 4,
		"All nest species participate and the giant keeps its host species."
	)
	_check(
		giant.fused_value_units == 22 and giant.reward == 44,
		"Mixed ordinary, gold and mucus contributions preserve their exact total value."
	)
	demo.run.purchase_technology("base_value")
	_check(giant.reward == 88, "Mixed fusion value scales once with global base value.")
	demo.run.purchase_technology("pipe")
	demo.run.purchase_technology("net_unlock")
	var before: int = demo.run.candy
	demo._net_anchor = giant.get_capture_point()
	demo._resolve_net()
	_check(
		demo.run.candy == before + 88 and demo.run.get_nest(4).alive_slimes == 0,
		"Net collection settles one mixed giant once and releases all twelve slots."
	)
	current_scene = null
	demo.queue_free()
	await process_frame


func _check_demo_balance() -> void:
	var demo: DemoScript = _make_demo()
	demo.run.settings.giant_fusion_threshold = SETTINGS.giant_fusion_threshold
	_check(
		SETTINGS.nest_population_limits == PackedInt32Array([10, 30, 60]),
		"The current demo capacities remain intact."
	)
	_check(
		SETTINGS.giant_fusion_threshold > 30 and SETTINGS.giant_fusion_threshold < 40,
		"The demo threshold lies between one cultivated nest and the mixed pair capacity."
	)
	_offscreen_pair(demo, NestState.Species.SLIME, Vector2i(8, 27))
	_enable_fusion(demo)
	demo.run.upgrade_nest(4)
	demo._advance_giant_fusion(1.0)
	_check(_giants(demo).is_empty(), "Thirty-five actors stay separate at the demo threshold.")
	_spawn_normals(demo, 4, 1)
	demo._advance_giant_fusion(1.0)
	var giant: PrototypeSlime = _giants(demo)[0]
	_check(
		giant.population_units == 36 and giant.reward == 72,
		"The real demo creates a thirty-six-unit giant at the configured threshold."
	)
	_check(
		demo.run.get_nest(4).alive_slimes == 36 and demo.run.get_nest_population_limit(4) == 30,
		"The demo host can temporarily exceed its actual thirty-unit cap."
	)
	current_scene = null
	demo.queue_free()
	await process_frame


func _check_visibility_and_tools() -> void:
	var demo: DemoScript = _make_demo()
	_spawn_normals(demo, 1, 4)
	_spawn_normals(demo, 2, 8)
	_enable_fusion(demo)
	demo._advance_giant_fusion(1.0)
	_check(_giants(demo).is_empty(), "Visible nests cannot fuse their actors.")
	demo.restart_run()
	demo.run.candy = 100000
	_offscreen_pair(demo)
	_enable_fusion(demo)
	var protected: PrototypeSlime = demo._slimes[0]
	var old_position: Vector2 = protected.position
	protected.position = demo._world.to_local(Vector2(640, 520))
	demo._advance_giant_fusion(1.0)
	_check(_giants(demo).is_empty(), "A visible actor from an offscreen nest is protected.")
	protected.position = old_position
	protected.capture_progress = 0.5
	demo._advance_giant_fusion(1.0)
	_check(_giants(demo).is_empty(), "Active suction excludes its target.")
	protected.capture_progress = 0.0
	protected._launch_elapsed = 0.0
	demo._advance_giant_fusion(1.0)
	_check(_giants(demo).is_empty(), "Airborne newborns must land before fusion.")
	protected._launch_elapsed = protected.launch_seconds
	demo._net_phase = DemoScript.NetPhase.CASTING
	demo._net_anchor = protected.get_capture_point()
	demo._advance_giant_fusion(1.0)
	_check(_giants(demo).is_empty(), "An in-flight net reserves its future targets.")
	demo._net_phase = DemoScript.NetPhase.IDLE
	demo._view.zoom_steps(-1.0)
	demo._advance_giant_fusion(1.0)
	_check(_giants(demo).is_empty(), "Camera transitions do not replace actors.")
	demo._view.zoom_steps(1.0, false)
	demo._view.zoom_steps(-1.0, false)
	demo._advance_giant_fusion(1.0)
	_check(_giants(demo).is_empty(), "The fully visible overview has no offscreen nest region.")
	demo._view.zoom_steps(1.0, false)
	demo._advance_giant_fusion(1.0)
	_check(_giants(demo).size() == 1, "Fusion resumes after all protections clear.")
	current_scene = null
	demo.queue_free()
	await process_frame


func _capture_showcase() -> void:
	root.mode = Window.MODE_WINDOWED
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		var demo: DemoScript = _make_demo(PlayScene)
		demo.run.settings.giant_fusion_threshold = SETTINGS.giant_fusion_threshold
		await process_frame
		_offscreen_pair(demo, NestState.Species.SLIME, Vector2i(8, 28))
		_enable_fusion(demo)
		demo.run.upgrade_nest(4)
		demo._advance_giant_fusion(1.0)
		var giant: PrototypeSlime = _giants(demo)[0]
		demo._view.zoom_steps(-1.0, false)
		demo._view.focus_surface(giant.position.angle(), false)
		_spawn_normals(demo, giant.nest_id, 3)
		var offset: float = 60.0
		var side: Vector2 = giant.position.normalized().orthogonal()
		for actor: PrototypeSlime in demo._slimes:
			actor.set_process(false)
			if actor.population_units == 1:
				actor.position = demo._planet.project_to_surface(giant.position + side * offset)
				offset += 28.0
			actor._update_surface_rotation()
		demo._pipe.hide()
		demo._refresh_hud()
		for _frame: int in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		_check(
			(
				root.get_texture().get_image().save_png(
					"res://artifacts/giant_slime_%dx%d.png" % [resolution.x, resolution.y]
				)
				== OK
			),
			"Giant showcase saved."
		)
		current_scene = null
		demo.queue_free()
		await process_frame


func _check_harvest_stream() -> void:
	var demo: DemoScript = _make_demo()
	_offscreen_pair(demo)
	_enable_fusion(demo)
	demo._advance_giant_fusion(1.0)
	var giant: PrototypeSlime = _giants(demo)[0]
	giant.set_process(false)
	var pointer: Vector2 = giant.get_capture_point()
	var before: int = demo.run.candy
	var occupancy: int = demo.run.get_nest(giant.nest_id).alive_slimes
	var step: float = demo.run.get_pipe_capture_seconds() / 5.0
	demo._capture_at(step, pointer, true)
	var stream: HarvestEffect = demo._giant_harvest
	_check(stream != null and stream.emitted_bursts > 0, "A partial giant capture emits candy.")
	var first_bursts: int = stream.emitted_bursts
	var original_height: float = giant._get_body_center_offset().length()
	demo._capture_at(step, pointer, true)
	_check(
		(
			stream.emitted_bursts > first_bursts
			and giant._get_body_center_offset().length() < original_height
		),
		"Candy continues across capture ticks while the giant shrinks."
	)
	_check(
		giant.get_capture_point().distance_to(pointer) < 0.01,
		"Shrinking keeps the body at the stationary suction mouth."
	)
	_check(
		demo.run.candy == before and demo.run.get_nest(giant.nest_id).alive_slimes == occupancy,
		"Spray presentation never pays or releases population before completion."
	)
	for candy: CollectionEffect in stream.get_children():
		_check(
			not candy.get_node("AmountLabel").visible,
			"In-progress candy has no false payout label."
		)
	demo._capture_at(0.0, pointer, false)
	_check(
		demo._giant_harvest == null and stream._finished and giant.capture_progress == 0.0,
		"Interrupting capture stops emission and restores the giant."
	)
	first_bursts = stream.emitted_bursts
	stream.update_capture(Vector2.ZERO, Vector2.ONE, 1.0)
	_check(stream.emitted_bursts == first_bursts, "A stopped stream cannot emit again.")
	demo._capture_at(step, giant.get_capture_point(), true)
	_check(demo._giant_harvest != stream, "Resuming uses a fresh visual stream.")
	var payout: int = giant.reward
	demo._capture_at(demo.run.get_pipe_capture_seconds(), giant.get_capture_point(), true)
	_check(
		demo.run.candy == before + payout and demo._giant_harvest == null,
		"A resumed harvest still pays the complete amount exactly once."
	)
	await create_timer(1.1).timeout
	_check(not is_instance_valid(stream), "Finished candy flights and their emitter clean up.")
	demo.restart_run()
	demo.run.candy = 100000
	_offscreen_pair(demo)
	_enable_fusion(demo)
	demo._advance_giant_fusion(1.0)
	giant = _giants(demo)[0]
	giant.set_process(false)
	demo._capture_at(step, giant.get_capture_point(), true)
	demo.restart_run()
	_check(
		demo._giant_harvest == null and demo._effects.get_child_count() == 0,
		"Restart clears every active spray and flight."
	)
	current_scene = null
	demo.queue_free()
	await process_frame


func _capture_harvest_showcase() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var demo: DemoScript = _make_demo(PlayScene)
	demo.run.settings.giant_fusion_threshold = SETTINGS.giant_fusion_threshold
	await process_frame
	_offscreen_pair(demo, NestState.Species.SLIME, Vector2i(8, 28))
	_enable_fusion(demo)
	demo.run.upgrade_nest(4)
	demo._advance_giant_fusion(1.0)
	var giant: PrototypeSlime = _giants(demo)[0]
	giant.set_process(false)
	demo._view.zoom_steps(-1.0, false)
	demo._view.focus_surface(giant.position.angle(), false)
	giant._update_surface_rotation()
	demo._refresh_hud()
	for _frame: int in range(4):
		await process_frame
	var pointer: Vector2 = giant.get_capture_point()
	demo._pipe.show()
	demo._pipe.set_tool_state(pointer, pointer, true)
	DirAccess.make_dir_recursive_absolute("res://artifacts/giant_harvest_frames")
	# Advance presentation explicitly so image saving cannot stretch the effect timing.
	Engine.time_scale = 0.0
	for frame: int in range(60):
		for effect: Node in demo._effects.get_children():
			if effect is CollectionEffect:
				effect._tween.custom_step(0.02)
			elif effect is HarvestEffect:
				for candy: CollectionEffect in effect.get_children():
					candy._tween.custom_step(0.02)
		if frame >= 8 and frame <= 38:
			demo._capture_at(demo.run.get_pipe_capture_seconds() / 30.0, pointer, true)
		elif frame > 38:
			demo._pipe.set_tool_state(pointer, pointer, false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://artifacts/giant_harvest_frames/frame_%03d.png" % frame
		)
	Engine.time_scale = 1.0
	current_scene = null
	demo.queue_free()
	await process_frame


func _check_population_settlement() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	var nest: NestState = run.get_nest(1)
	nest.alive_slimes = 12
	_check(not run.collect_slime(1, 24, 13), "Cannot collect more population than the nest owns.")
	_check(not run.collect_slime(1, 24, 0), "Zero population cannot produce a reward.")
	_check(run.candy == 0 and nest.alive_slimes == 12, "Rejected harvests preserve both totals.")
	_check(run.collect_slime(1, -1, 12), "A weighted harvest releases all population units.")
	_check(run.candy == 24 and nest.alive_slimes == 0, "Default reward conserves the source value.")
	_check(not run.collect_slime(1, 24, 12), "The same population cannot be collected twice.")
	run.free()


func _check_live_settlement() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	var fused: PrototypeSlime = _spawn_weighted(demo, 12, 14)
	demo._refresh_overview()
	_check(demo._overview.population_counts.x == 12, "Overview retains the represented population.")
	demo._view.zoom_steps(-1.0, false)
	_check(demo._overview.clusters.size() == 1, "One body produces one local overview cluster.")
	_check(
		demo._overview.clusters[0].count == 12, "Cluster size uses the complete fused population."
	)
	demo._view.zoom_steps(1.0, false)
	demo.run.candy = 10000
	demo.run.purchase_technology("base_value")
	_check(fused.reward == 56, "Eleven ordinary and one gold preserve all value after research.")
	demo.run.combo_level = 1
	var before: int = demo.run.candy
	demo._capture_at(2.0, fused.get_capture_point(), true)
	_check(
		demo.run.candy == before + 56 and demo.run.get_nest(1).alive_slimes == 0,
		"A single suction settles the complete reward and releases twelve units."
	)
	_check(demo.run.combo_count == 1, "A fused harvest is one manual combo action.")
	demo.run.net_unlocked = true
	_spawn_weighted(demo, 12, 12)
	_spawn_weighted(demo, 1, 1)
	demo._net_anchor = Vector2(0, -190)
	before = demo.run.candy
	demo._resolve_net()
	_check(
		demo.run.candy == before + 52 and demo.run.get_nest(1).alive_slimes == 0,
		"A net settles weighted and ordinary individuals in one batch."
	)
	_check(demo._net_caught_count == 2, "The net holds two bodies regardless of represented units.")
	_check(demo.run.combo_count == 1, "Net harvesting does not increment the manual combo.")
	demo.restart_run()
	_check(demo._slimes.is_empty(), "Restart clears fused and ordinary actors together.")
	current_scene = null
	demo.queue_free()
	await process_frame


func _spawn_weighted(demo: DemoScript, population: int, value_units: int) -> PrototypeSlime:
	demo.run.get_nest(1).alive_slimes += population
	demo._on_slime_requested(1)
	var actor: PrototypeSlime = demo._slimes.back()
	actor._process(actor.launch_seconds)
	actor.set_process(false)
	actor.population_units = population
	actor.fused_value_units = value_units if population > 1 else 0
	actor.reward = demo.run.get_base_value() * value_units
	actor.position = Vector2(0, -190)
	return actor


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
