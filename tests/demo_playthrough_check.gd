extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const STEP_SECONDS: float = 0.1
const MAX_SECONDS: float = 1800.0
const CONTINUOUS_CAPTURE_TARGET: int = 6

var _failures: int = 0
var _elapsed: float = 0.0
var _first_upgrade_seconds: float = -1.0
var _first_tamed_seconds: float = -1.0
var _active_income: int = 0
var _passive_income: int = 0
var _spent: int = 0
var _passive_funded_purchase: bool = false
var _pointer: Vector2 = Vector2.UP * 225.0
var _collected_slimes: int = 0
var _paid_capture_frames: int = 0
var _holding: bool = false
var _spawn_sequence: int = 0
var _spawns_while_holding: int = 0
var _mucus_collected: int = 0
var _valuable_collected: int = 0
var _breakthrough_times: Array[float] = []


func _initialize() -> void:
	_playthrough.call_deferred()


func _playthrough() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	seed(78143)
	demo.run._random.seed = 78143
	demo._site_random.seed = 91841
	demo.run.slime_requested.connect(_seed_new_slime.bind(demo))
	_check(demo.run.candy == 0, "The playthrough begins with zero candy.")
	var max_steps: int = int(MAX_SECONDS / STEP_SECONDS)
	for step: int in range(max_steps):
		_elapsed = float(step + 1) * STEP_SECONDS
		var before_advance: int = demo.run.candy
		demo.run.advance(STEP_SECONDS)
		_passive_income += demo.run.candy - before_advance
		for slime: PrototypeSlime in demo._slimes:
			slime._process(STEP_SECONDS)
		demo._advance_ground_mucus(STEP_SECONDS)
		_drive_collection(demo)
		if step % 10 == 9:
			_invest(demo)
		if step % 1200 == 1199:
			print(
				(
					"Progress %.0fs: value %d, speed %d, candy %d, automated %d/%d"
					% [
						_elapsed,
						demo.run.base_value_level,
						demo.run.pipe_level,
						demo.run.candy,
						demo.run.completed_nests,
						demo.run.generated_nests
					]
				)
			)
		_check_surface_population(demo)
		if demo.run.is_complete or _failures > 0:
			break
		if step % 10 == 9:
			await process_frame
	_check(
		(
			demo.run.pipe_level == demo.run.settings.pipe_upgrade_costs.size()
			and demo.run.net_level == demo.run.settings.net_upgrade_costs.size()
			and demo.run.base_value_level == demo.run.settings.base_value_upgrade_costs.size()
		),
		"Every value, pipe and net technology is purchased through earned candy."
	)
	_check(
		_collected_slimes >= CONTINUOUS_CAPTURE_TARGET,
		"Continuous held collection pays for six or more bodies without a release."
	)
	_check(
		demo.run.is_complete and demo.run.completed_nests == demo.run.generated_nests,
		"Every discovered nest is automated within the prototype playthrough window."
	)
	_check(
		demo.run.generated_nests > 3,
		"The live playthrough also resolves recurring nest rolls after net unlock."
	)
	_check(
		(
			is_equal_approx(demo.run.get_pipe_capture_seconds(), 0.11)
			and demo.run.get_net_capacity() == 30
		),
		"Earned research reaches the revised final pipe speed and net capacity."
	)
	_check(_first_tamed_seconds > 0.0, "The first tamed nest is reached through earned candy.")
	_check(_active_income > 0 and _passive_income > 0, "Both collection and automation earn candy.")
	_check(
		_paid_capture_frames == _collected_slimes and _collected_slimes > 0,
		"Each completed body contributes one independently paid capture frame."
	)
	_check(
		demo.run.governance_level == 3 and demo.run.combo_level == 3,
		"Governance and all three combo tiers are purchased through earned candy."
	)
	_check(
		_mucus_collected > 0 and _valuable_collected > 0,
		"Manual collection processes both species and researched high-value individuals."
	)
	_check(_spawns_while_holding > 0, "Collected surface slots refill while input stays held.")
	_check(_passive_funded_purchase, "Automatic income participates in a later purchase.")
	_check(
		_active_income + _passive_income - _spent == demo.run.candy,
		"Measured income and purchases account for the final candy balance."
	)
	print(
		(
			"Playthrough: first upgrade %.1fs; first tamed nest %.1fs; completion %.1fs; discovered nests %d."
			% [_first_upgrade_seconds, _first_tamed_seconds, _elapsed, demo.run.generated_nests]
		)
	)
	print(
		(
			"Measured candy: active %d; automatic %d; spent %d; remaining %d."
			% [_active_income, _passive_income, _spent, demo.run.candy]
		)
	)
	print("Value breakthrough times: ", _breakthrough_times)
	print(
		(
			"Simulated collection: %d immediate payments; %d monsters; %d spawns while held."
			% [_paid_capture_frames, _collected_slimes, _spawns_while_holding]
		)
	)
	if _failures == 0:
		print(
			"PASS: zero-candy economy is reachable through continuous paid capture and upgrade buttons."
		)
	for child: Node in demo.get_node("Audio").get_children():
		if child is AudioStreamPlayer:
			child.stop()
	await create_timer(0.2).timeout
	current_scene = null
	demo.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)


func _invest(demo: DemoScript) -> void:
	var before_purchase: int = demo.run.candy
	var value_before: int = demo.run.base_value_level
	var first_nest: NestState = demo.run.get_nest(1)
	if demo.run.pipe_level == 0:
		demo._layout.quick_upgrade_requested.emit(0)
	elif demo.run.base_value_level == 0:
		demo._layout.technology_upgrade_requested.emit("base_value")
	elif not demo.run.net_unlocked:
		demo._layout.quick_upgrade_requested.emit(1)
	elif demo.run.governance_level == 0:
		demo._layout.technology_upgrade_requested.emit("governance")
	elif first_nest.level == 0:
		_invest_in_nest(demo, first_nest)
	elif demo.run.combo_level == 0:
		demo._layout.technology_upgrade_requested.emit("combo")
	elif demo.run.pipe_level == 1:
		demo._layout.quick_upgrade_requested.emit(0)
	elif demo.run.base_value_level == 1:
		demo._layout.technology_upgrade_requested.emit("base_value")
	elif demo.run.valuable_level == 0:
		demo._layout.technology_upgrade_requested.emit("valuable")
	elif demo.run.pipe_level == 2:
		demo._layout.quick_upgrade_requested.emit(0)
	elif demo.run.base_value_level == 2:
		demo._layout.technology_upgrade_requested.emit("base_value")
	elif demo.run.governance_level == 1:
		demo._layout.technology_upgrade_requested.emit("governance")
	elif first_nest.level == 1:
		_invest_in_nest(demo, first_nest)
	elif demo.run.base_value_level == 3 and demo.run.pipe_level >= 4:
		demo._layout.technology_upgrade_requested.emit("base_value")
	elif demo.run.get_pipe_upgrade_cost() >= 0:
		demo._layout.quick_upgrade_requested.emit(0)
	elif demo.run.governance_level < 3:
		demo._layout.technology_upgrade_requested.emit("governance")
	elif first_nest.level < 3:
		_invest_in_nest(demo, first_nest)
	elif demo.run.combo_level < 3:
		demo._layout.technology_upgrade_requested.emit("combo")
	elif demo.run.get_net_upgrade_cost() >= 0:
		demo._layout.quick_upgrade_requested.emit(1)
	else:
		var nest: NestState = _first_active_nest(demo.run)
		if nest != null:
			_invest_in_nest(demo, nest)
	if demo.run.pipe_level > 0 and _first_upgrade_seconds < 0.0:
		_first_upgrade_seconds = _elapsed
	if demo.run.base_value_level > value_before:
		_breakthrough_times.append(_elapsed)
	if demo.run.completed_nests > 0 and _first_tamed_seconds < 0.0:
		_first_tamed_seconds = _elapsed
	_spent += before_purchase - demo.run.candy
	if _spent > _active_income:
		_passive_funded_purchase = true
	demo._update_nest_hover(Vector2(5.0, 5.0))


func _invest_in_nest(demo: DemoScript, nest: NestState) -> void:
	_focus_world_point(demo, nest.position)
	for view: NestView in demo._nest_views:
		if view.nest_id == nest.nest_id:
			var shape: CollisionShape2D = (
				view.get_node("SelectionArea/CollisionShape2D") as CollisionShape2D
			)
			demo._update_nest_hover(shape.get_global_transform_with_canvas().origin)
			break
	_check(demo.selected_nest_id == nest.nest_id, "Hover selects the nest to invest in.")
	var nest_button: Button = demo.get_node("%NestButton") as Button
	if not nest_button.disabled:
		nest_button.pressed.emit()


func _seed_new_slime(nest_id: int, demo: DemoScript) -> void:
	_spawn_sequence += 1
	if _holding:
		_spawns_while_holding += 1
	var slime: PrototypeSlime = demo._slimes.back()
	slime._rng.seed = 78143 + _spawn_sequence * 73 + nest_id
	var nest: NestState = demo.run.get_nest(nest_id)
	var direction: Vector2 = Vector2.from_angle(
		float(_spawn_sequence) * 2.399963 + nest.position.angle()
	)
	slime.launch(direction)
	slime._speed_variation = 1.0
	slime.set_process(false)


func _drive_collection(demo: DemoScript) -> void:
	_holding = true
	var target: PrototypeSlime = _find_target(demo)
	if target != null:
		_pointer = target.get_capture_point()
		if not demo._can_collect(_pointer, demo.run.get_pipe_radius()):
			_focus_world_point(demo, _pointer)
	var candy_before: int = demo.run.candy
	var population_before: int = demo._slimes.size()
	var actors_before: Array[PrototypeSlime] = demo._slimes.duplicate()
	var combo_before: int = demo.run.combo_count
	var fraction_before: int = demo.run._combo_reward_remainder
	var effects_before: int = demo.get_node("%Effects").get_child_count()
	demo._drive_tool(STEP_SECONDS, _pointer, _holding)
	var collected: int = population_before - demo._slimes.size()
	var reward: int = demo.run.candy - candy_before
	var individual_reward: int = 0
	for slime: PrototypeSlime in actors_before:
		if not demo._slimes.has(slime):
			individual_reward += slime.reward
			if slime.species == PrototypeSlime.Species.MUCUS:
				_mucus_collected += 1
			if slime.high_value:
				_valuable_collected += 1
	var bonus: int = 0
	if collected > 0 and combo_before + collected > demo.run.settings.combo_target:
		bonus = floori(
			float(individual_reward * demo.run.get_combo_reward_percent() + fraction_before) / 100.0
		)
	_check(
		collected in [0, 1] and demo._capture_targets.size() <= 1,
		"The pipe advances and consumes at most one body during each processing frame."
	)
	_check(
		reward == individual_reward + bonus,
		"Every collected body's species value and earned combo bonus pay in the same input frame."
	)
	_check(
		demo.get_node("%Effects").get_child_count() == effects_before + collected,
		"Every collected body adds its own visible feedback in the same frame."
	)
	if collected > 0:
		_active_income += reward
		_collected_slimes += collected
		_paid_capture_frames += 1


func _check_surface_population(demo: DemoScript) -> void:
	var surface_population: int = 0
	for nest: NestState in demo.run.nests:
		surface_population += nest.alive_slimes
		_check(
			(
				nest.alive_slimes >= 0
				and nest.alive_slimes <= demo.run.get_nest_population_limit(nest.nest_id)
			),
			"The current live population stays within its source nest's tier limit."
		)
	_check(
		demo._slimes.size() == surface_population,
		"Live actors exactly match the remaining surface population."
	)


func _find_target(demo: DemoScript) -> PrototypeSlime:
	if not demo._capture_targets.is_empty():
		return demo._capture_targets[0]
	var nearest: PrototypeSlime = null
	var nearest_distance: float = INF
	for slime: PrototypeSlime in demo._slimes:
		var distance: float = slime.get_capture_point().distance_squared_to(_pointer)
		if distance < nearest_distance:
			nearest = slime
			nearest_distance = distance
	return nearest


func _focus_world_point(demo: DemoScript, point: Vector2) -> void:
	# Follow real camera rotation instead of waiting forever for an off-screen target.
	var angle: float = wrapf(Vector2.UP.angle() - point.angle() - demo._world.rotation, -PI, PI)
	var radius: float = (
		demo._planet.radius * demo._world.scale.x * demo._view.projection_root.scale.x
	)
	demo._capture_at(0.0, point, false)
	demo._view.begin_drag(Vector2.ZERO)
	demo._view.drag_to(Vector2(angle * radius, 0.0))
	demo._view.end_drag()


func _first_active_nest(run: PrototypeRun) -> NestState:
	for nest: NestState in run.nests:
		if not nest.is_tamed:
			return nest
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
