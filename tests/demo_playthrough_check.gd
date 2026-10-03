extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const STEP_SECONDS: float = 0.1
const MAX_SECONDS: float = 1800.0
const COLLECTION_BATCH_SIZE: int = 6

var _failures: int = 0
var _elapsed: float = 0.0
var _first_upgrade_seconds: float = -1.0
var _first_tamed_seconds: float = -1.0
var _active_income: int = 0
var _passive_income: int = 0
var _spent: int = 0
var _passive_funded_purchase: bool = false
var _pointer: Vector2 = Vector2.UP * 225.0
var _largest_batch: int = 0
var _settlement_batches: int = 0
var _settled_slimes: int = 0
var _spawn_sequence: int = 0
var _spawns_while_pending: int = 0


func _initialize() -> void:
	_playthrough.call_deferred()


func _playthrough() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	seed(78143)
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
		_drive_collection(demo)
		if step % 10 == 9:
			_invest(demo)
		_check_surface_population(demo)
		if demo.run.is_complete or _failures > 0:
			break
		if step % 10 == 9:
			await process_frame
	_check(
		(
			demo.run.pipe_level == demo.run.settings.pipe_upgrade_costs.size()
			and demo.run.net_level == demo.run.settings.net_upgrade_costs.size()
		),
		"Every pipe and net technology is purchased through earned candy."
	)
	_check(
		_largest_batch >= COLLECTION_BATCH_SIZE,
		"Continuous collection fills a batch of six or more."
	)
	_check(
		demo.run.is_complete and demo.run.completed_nests == demo.run.settings.nest_budget,
		"Every budgeted nest is tamed within the prototype playthrough window."
	)
	_check(_first_tamed_seconds > 0.0, "The first tamed nest is reached through earned candy.")
	_check(_active_income > 0 and _passive_income > 0, "Both collection and automation earn candy.")
	_check(
		_settlement_batches > 0 and _settled_slimes > 0,
		"Active income comes from collected batches paid immediately on release."
	)
	_check(_spawns_while_pending > 0, "Collected surface slots refill before the batch is settled.")
	_check(_passive_funded_purchase, "Automatic income participates in a later purchase.")
	_check(
		_active_income + _passive_income - _spent == demo.run.candy,
		"Measured income and purchases account for the final candy balance."
	)
	_check(
		demo.run.pending_candy == 0 and demo.run.pending_slime_count == 0,
		"Goal completion leaves no unclaimed collection reward."
	)
	print(
		(
			"Playthrough: first upgrade %.1fs; first tamed nest %.1fs; completion %.1fs."
			% [_first_upgrade_seconds, _first_tamed_seconds, _elapsed]
		)
	)
	print(
		(
			"Measured candy: active %d; automatic %d; spent %d; remaining %d."
			% [_active_income, _passive_income, _spent, demo.run.candy]
		)
	)
	print(
		(
			"Simulated collection: %d settlements; %d monsters; largest batch %d; %d spawns while unsettled."
			% [_settlement_batches, _settled_slimes, _largest_batch, _spawns_while_pending]
		)
	)
	if _failures == 0:
		print(
			"PASS: zero-candy economy is reachable through continuous capture, local release and buttons."
		)
	for child: Node in demo.get_node("Audio").get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		player.stop()
	await create_timer(0.2).timeout
	current_scene = null
	demo.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)


func _invest(demo: DemoScript) -> void:
	var before_purchase: int = demo.run.candy
	var pending_before: int = demo.run.pending_candy
	var pending_count_before: int = demo.run.pending_slime_count
	if demo.run.get_pipe_upgrade_cost() >= 0:
		var tool_button: Button = demo.get_node("%ToolButton") as Button
		if not tool_button.disabled:
			tool_button.pressed.emit()
			if demo.run.pipe_level > 0 and _first_upgrade_seconds < 0.0:
				_first_upgrade_seconds = _elapsed
	elif demo.run.get_net_upgrade_cost() >= 0:
		if demo.run.candy >= demo.run.get_net_upgrade_cost():
			demo._select_tool(DemoScript.ToolMode.NET)
			var tool_button: Button = demo.get_node("%ToolButton") as Button
			if not tool_button.disabled:
				tool_button.pressed.emit()
			demo._select_tool(DemoScript.ToolMode.PIPE)
	else:
		var nest: NestState = _first_active_nest(demo.run)
		if nest != null:
			demo._select_nest(nest.nest_id)
			var nest_button: Button = demo.get_node("%NestButton") as Button
			if not nest_button.disabled:
				nest_button.pressed.emit()
				if _first_tamed_seconds < 0.0 and demo.run.completed_nests > 0:
					_first_tamed_seconds = _elapsed
	var settled_reward: int = pending_before - demo.run.pending_candy
	if settled_reward > 0:
		_record_settlement(settled_reward, pending_count_before - demo.run.pending_slime_count)
	_spent += before_purchase - demo.run.candy + settled_reward
	if _spent > _active_income:
		_passive_funded_purchase = true


func _seed_new_slime(nest_id: int, demo: DemoScript) -> void:
	_spawn_sequence += 1
	if demo.run.pending_slime_count > 0:
		_spawns_while_pending += 1
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
	var holding: bool = demo.run.pending_slime_count < COLLECTION_BATCH_SIZE
	if demo._slimes.is_empty() and demo.run.pending_slime_count > 0:
		holding = false
	if holding:
		var target: PrototypeSlime = _find_target(demo)
		if target != null:
			_pointer = target.get_capture_point()
	var candy_before: int = demo.run.candy
	var pending_before: int = demo.run.pending_candy
	var count_before: int = demo.run.pending_slime_count
	demo._drive_tool(STEP_SECONDS, _pointer, holding)
	if holding:
		_check(demo.run.candy == candy_before, "Continuous capture leaves the reward pending.")
		_check(
			demo.run.pending_slime_count - count_before <= 1 and demo._capture_targets.size() <= 1,
			"The pipe advances and consumes at most one body during each processing frame."
		)
	else:
		var reward: int = demo.run.candy - candy_before
		_check(
			(
				reward == pending_before
				and demo.run.pending_candy == 0
				and demo.run.pending_slime_count == 0
			),
			"Releasing at the same pointer position pays and clears the complete batch."
		)
		if reward > 0:
			_record_settlement(reward, count_before)


func _record_settlement(reward: int, count: int) -> void:
	_active_income += reward
	_settled_slimes += count
	_settlement_batches += 1
	_largest_batch = maxi(_largest_batch, count)


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
		"Live actors exactly match surface population, excluding already collected pending monsters."
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


func _first_active_nest(run: PrototypeRun) -> NestState:
	for nest: NestState in run.nests:
		if not nest.is_tamed:
			return nest
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
