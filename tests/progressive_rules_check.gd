extends SceneTree

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")

var _failures: Array[String] = []
var _spawn_requests: int = 0
var _goal_count: int = 0
var _nest_requests: int = 0


func _init() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	_check_opening_and_net_unlock()
	_check_bursts_and_population_tiers()
	_check_automatic_income()
	_check_continuous_pipe_combo()
	_check_tool_tiers()
	_check_continuous_discovery()
	_check_governance_roll_weight()
	_check_existing_nests_completion()
	if _failures.is_empty():
		print(
			"PASS: continuous weighted discovery, current-nest completion, seven pipe tiers, net capacity and three-second combos"
		)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check_opening_and_net_unlock() -> void:
	var run: PrototypeRun = _create_run()
	_check(run.nests.size() == 2, "The opening contains exactly two nests.")
	for nest: NestState in run.nests:
		_check(
			nest.species == NestState.Species.SLIME and nest.level == 0,
			"Both opening nests contain basic tier-one slimes."
		)
	_check(
		not run.net_unlocked and not run.can_cast_net() and not run.begin_net_cast(),
		"The locked net cannot cast."
	)
	run.get_nest(1).alive_slimes = 1
	_check(
		run.collect_net_batch([1]) == 0 and run.get_nest(1).alive_slimes == 1,
		"The locked net cannot remove targets or award candy."
	)
	run.advance(100.0)
	_check(run.nests.size() == 2, "Elapsed time alone does not introduce new nest types.")
	run.candy = SETTINGS.pipe_upgrade_costs[0]
	_check(run.upgrade_pipe(), "Speed level two permits net unlock.")
	run.candy = SETTINGS.net_unlock_cost - 1
	_check(not run.upgrade_net(), "The net unlock requires its full advertised price.")
	run.candy += 1
	_check(run.upgrade_net(), "The first net purchase unlocks the tool.")
	_check(
		run.net_unlocked and run.net_level == 0 and run.get_net_capacity() == 5 and run.candy == 0,
		"Unlocking charges once and provides the basic five-target net."
	)
	_check(
		run.nests.size() == 3 and run.get_nest(3).species == NestState.Species.MUCUS,
		"Net unlock introduces one mucus nest."
	)
	run.candy = 1000
	_check(run.upgrade_net() and run.net_level == 1, "Later net purchases upgrade its capacity.")
	_check(run.nests.size() == 3, "Capacity upgrades do not repeat the mucus introduction.")
	run.start_run(_positions())
	_check(
		not run.net_unlocked and run.nests.size() == 2 and run.completed_nests == 0,
		"Restart restores the two basic nests and relocks the net."
	)
	run.free()


func _check_bursts_and_population_tiers() -> void:
	for tier: int in range(1, 4):
		var run: PrototypeRun = _create_run()
		var nest: NestState = run.get_nest(1)
		nest.level = tier - 1
		var capacity: int = [10, 30, 60][tier - 1]
		_check(
			run.get_nest_population_limit(1) == capacity, "Each tier has its stair-step capacity."
		)
		var interval: float = run.get_nest_spawn_interval(1)
		run.advance(interval - 0.01)
		_check(nest.alive_slimes == 0, "A nest remains quiet between bursts.")
		_spawn_requests = 0
		run.slime_requested.connect(_count_spawn_for_first_nest)
		run.advance(0.02)
		_check(
			(
				nest.alive_slimes >= ceili(capacity * 0.2)
				and nest.alive_slimes <= floori(capacity * 0.3)
			),
			"Each full burst ejects twenty to thirty percent of the nest capacity."
		)
		_check(_spawn_requests == nest.alive_slimes, "Every spawned body has exactly one request.")
		nest.alive_slimes = capacity - 1
		nest.spawn_clock = 0.0
		run.advance(interval)
		_check(nest.alive_slimes == capacity, "The final burst clips to remaining capacity.")
		run.advance(interval * 20.0)
		_check(nest.alive_slimes == capacity, "A full nest cannot overfill during a long update.")
		nest.level = 3
		_check(
			run.get_nest_population_limit(1) == 60,
			"The final automated stage retains the sixty-monster capacity."
		)
		run.free()


func _check_continuous_pipe_combo() -> void:
	for tier: int in range(1, 4):
		var run: PrototypeRun = _create_run()
		run.combo_level = tier
		run.get_nest(1).alive_slimes = 20
		for _index: int in range(5):
			run.collect_slime(1)
		_check(
			run.combo_count == 5 and run.candy == 5 * SETTINGS.slime_reward,
			"The first five pipe captures build a streak without a bonus."
		)
		for _index: int in range(3):
			run.collect_slime(1)
		_check(
			run.combo_count == 8 and run.candy == 8 * SETTINGS.slime_reward + 3 * tier,
			"Every capture from the sixth onward adds the researched bonus without resetting."
		)
		run.advance(2.9)
		_check(run.combo_count == 8, "The active streak survives until its three-second deadline.")
		run.net_unlocked = true
		var reward: int = run.collect_net_batch([1, 1])
		_check(
			reward == 2 * SETTINGS.slime_reward and run.combo_count == 8,
			"Net captures neither advance the pipe streak nor receive its bonus."
		)
		run.get_nest(1).level = 3
		run.get_nest(1).is_tamed = true
		run.get_nest(1).income_remainder = 0.9
		run.completed_nests = 1
		var before_income: int = run.candy
		run.advance(0.05)
		_check(
			run.combo_count == 8 and run.candy == before_income + 1,
			"Automatic income pays candy without advancing the pipe streak."
		)
		_check(
			is_equal_approx(run.combo_remaining, 0.05),
			"Net and automatic income do not refresh the remaining buff duration."
		)
		var balance: int = run.candy
		_check(
			not run.collect_slime(999) and run.combo_count == 8 and run.candy == balance,
			"Rejected targets cannot advance a streak or award candy."
		)
		run.collect_slime(1)
		_check(
			is_equal_approx(run.combo_remaining, 3.0) and run.combo_count == 9,
			"A pipe capture within the deadline refreshes the buff to three seconds."
		)
		run.advance(3.01)
		_check(run.combo_count == 0, "The streak resets when its capture window expires.")
		balance = run.candy
		run.collect_slime(1)
		_check(
			run.combo_count == 1 and run.candy == balance + SETTINGS.slime_reward,
			"A new streak must rebuild the first five captures."
		)
		run.free()


func _check_tool_tiers() -> void:
	var run: PrototypeRun = _create_run()
	run.candy = 10000
	_check(
		is_equal_approx(run.get_pipe_capture_seconds(), 0.6),
		"Base pipe speed remains 0.60 seconds."
	)
	var speeds: Array[float] = [0.45, 0.32, 0.22, 0.17, 0.135, 0.11]
	for index: int in range(speeds.size()):
		_check(run.upgrade_pipe(), "Every one of the six pipe upgrades is purchasable.")
		_check(
			is_equal_approx(run.get_pipe_capture_seconds(), speeds[index]),
			"Pipe upgrades expose the configured seven speed tiers."
		)
	_check(not run.upgrade_pipe(), "The seventh pipe tier is the final tier.")
	_check(
		is_equal_approx(run.get_pipe_capture_seconds(), 0.22 / 2.0),
		"The final pipe tier is twice as fast as the former 0.22-second maximum."
	)
	for capacity: int in [5, 10, 20, 30]:
		_check(run.upgrade_net(), "Net unlock and each capacity upgrade are purchasable.")
		_check(
			run.get_net_capacity() == capacity, "Net capacity follows five, ten, twenty, thirty."
		)
	_check(not run.upgrade_net(), "The thirty-target net is the final tier.")
	run.free()


func _check_continuous_discovery() -> void:
	var run: PrototypeRun = _create_run()
	var settings: PrototypeSettings = SETTINGS.duplicate() as PrototypeSettings
	settings.nest_roll_chance_min = 1.0
	settings.nest_roll_chance_max = 1.0
	run.settings = settings
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_net()
	run._random.seed = 72861
	_nest_requests = 0
	run.nest_spawn_requested.connect(_place_requested_nest.bind(run))
	run.advance(settings.nest_roll_interval - 0.01)
	_check(run.nests.size() == 3, "Unlocking starts a fresh interval before any recurring roll.")
	run.advance(0.02)
	_check(
		run.nests.size() == 4 and run.governance_level == 0 and run.completed_nests == 0,
		"Both species enter recurring discovery immediately after the mucus unlock."
	)
	run.advance(settings.nest_roll_interval * 30.0)
	var slime_nests: int = 0
	var mucus_nests: int = 0
	for nest: NestState in run.nests:
		if nest.species == NestState.Species.SLIME:
			slime_nests += 1
		else:
			mucus_nests += 1
	_check(
		run.nests.size() == 34 and _nest_requests == 31 and slime_nests > 3 and mucus_nests > 2,
		"Recurring discovery has neither a five-site quota nor total or species count caps."
	)
	_check(run.generation_stage == 1, "Elapsed time no longer opens a later mandatory pool stage.")
	run.free()
	var pending_run: PrototypeRun = _create_run()
	pending_run.settings = settings
	pending_run.candy = 10000
	pending_run.upgrade_pipe()
	pending_run.upgrade_net()
	_nest_requests = 0
	pending_run.nest_spawn_requested.connect(_count_nest_request)
	pending_run.advance(settings.nest_roll_interval)
	pending_run.advance(settings.nest_roll_interval * 3.0)
	_check(
		_nest_requests == 1 and pending_run.nests.size() == 3,
		"A pending placement request cannot duplicate itself while awaiting a site."
	)
	_check(
		not pending_run.resolve_nest_spawn(Vector2.ZERO, false),
		"No valid surface site declines the request without inventing a nest."
	)
	pending_run.advance(settings.nest_roll_interval)
	_check(
		_nest_requests == 2 and pending_run.resolve_nest_spawn(Vector2(300, 0)),
		"A later successful roll can place a nest after an unavailable site."
	)
	_check(
		not pending_run.resolve_nest_spawn(Vector2(400, 0)) and pending_run.nests.size() == 4,
		"Each placement request can add at most one nest."
	)
	pending_run.free()


func _check_governance_roll_weight() -> void:
	var run: PrototypeRun = _create_run()
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_net()
	_enable_full_governance(run)
	_check(
		is_equal_approx(run.get_nest_roll_chance(), 0.05),
		"An unmanaged planet starts with five percent roll chance."
	)
	for _index: int in range(3):
		run.upgrade_nest(1)
	_check(
		is_equal_approx(run.get_nest_roll_chance(), 0.15),
		"One fully governed nest among three raises the chance to fifteen percent."
	)
	for nest_id: int in [2, 3]:
		for _index: int in range(3):
			run.upgrade_nest(nest_id)
	_check(
		is_equal_approx(run.get_nest_roll_chance(), 0.35),
		"Average governance scales the configured roll chance up to thirty-five percent."
	)
	run.free()


func _check_existing_nests_completion() -> void:
	var locked_run: PrototypeRun = _create_run()
	locked_run.candy = 10000
	_enable_full_governance(locked_run)
	for nest_id: int in [1, 2]:
		for _index: int in range(3):
			locked_run.upgrade_nest(nest_id)
	_check(
		locked_run.is_complete and not locked_run.net_unlocked,
		"Automating every current nest completes the run without a mandatory tool-unlock quota."
	)
	locked_run.upgrade_net()
	_check(
		locked_run.net_unlocked and locked_run.nests.size() == 2,
		"Research can continue after completion while nest additions remain stopped."
	)
	locked_run.free()
	var run: PrototypeRun = _create_run()
	var settings: PrototypeSettings = SETTINGS.duplicate() as PrototypeSettings
	settings.nest_roll_chance_min = 1.0
	settings.nest_roll_chance_max = 1.0
	run.settings = settings
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_net()
	_enable_full_governance(run)
	_goal_count = 0
	run.goal_completed.connect(_count_goal.bind(run))
	run.advance(settings.nest_roll_interval)
	for nest_id: int in [1, 2, 3]:
		for _index: int in range(3):
			run.upgrade_nest(nest_id)
	_check(
		run.is_complete and _goal_count == 1,
		"The final upgrade completes the current planet immediately, before another roll."
	)
	_check(
		not run.resolve_nest_spawn(Vector2(300, 0)),
		"Completion cancels a pending placement instead of adding an ungoverned nest afterward."
	)
	run.advance(settings.nest_roll_interval * 100.0)
	_check(
		run.nests.size() == 3 and _goal_count == 1,
		"Completed planets keep simulating without adding nests or repeating completion."
	)
	run.start_run(_positions())
	_check(
		not run.is_complete and run.generation_stage == 0 and run.nests.size() == 2,
		"Restart clears completion, the roll clock and any pending placement."
	)
	run.free()


func _check_automatic_income() -> void:
	var run: PrototypeRun = _create_run()
	run.candy = 10000
	_enable_full_governance(run)
	var nest: NestState = run.get_nest(1)
	_check(run.upgrade_nest(1) and run.upgrade_nest(1), "The two cultivation stages remain.")
	var before: int = run.candy
	run.advance(1.0)
	_check(
		run.candy == before and run.get_passive_income() == 0.0,
		"Cultivation never pays passive candy."
	)
	nest.spawn_clock = run.get_nest_spawn_interval(1) - 0.01
	_check(run.upgrade_nest(1), "The final construction enables automatic income.")
	_check(nest.spawn_clock == 0.0, "Automation clears an almost-ready spawn burst.")
	var research_balance: int = run.candy
	_check(
		not run.purchase_nest_technology(1, "valuable") and run.candy == research_balance,
		"An automated nest cannot charge for research that requires future monsters."
	)
	_spawn_requests = 0
	run.slime_requested.connect(_count_spawn_for_first_nest)
	before = run.candy
	run.advance(0.1)
	_check(run.candy == before, "Fractional candy is retained until a whole candy accrues.")
	run.advance(0.3)
	_check(
		run.candy == before + 1 and is_equal_approx(nest.income_remainder, 0.2),
		"Small updates preserve fractional income."
	)
	var population: int = nest.alive_slimes
	run.advance(10.0)
	_check(
		_spawn_requests == 0 and nest.alive_slimes == population,
		"An automated nest never spawns or consumes monsters."
	)
	_check(run.candy == before + 31, "Empty automated nests keep producing their configured candy.")
	for _stage: int in range(3):
		run.upgrade_nest(2)
	_check(
		run.is_complete and is_equal_approx(run.get_passive_income(), 6.0),
		"Every automated nest contributes income after completion."
	)
	before = run.candy
	run.advance(2.0)
	_check(
		run.candy == before + 12 and _spawn_requests == 0,
		"Completion keeps income running and spawning stopped."
	)
	before = run.candy
	run.advance(-1.0)
	_check(run.candy == before, "Negative elapsed time cannot change income.")
	run.start_run(_positions())
	_check(
		(
			run.candy == 0
			and run.get_passive_income() == 0.0
			and run.get_nest(1).income_remainder == 0.0
		),
		"Restart clears production and fractional balances."
	)
	run.free()


func _enable_full_governance(run: PrototypeRun) -> void:
	run.upgrade_pipe()
	run.upgrade_pipe()
	run.purchase_technology("cultivation")
	run.purchase_technology("automation")


func _place_requested_nest(species: NestState.Species, run: PrototypeRun) -> void:
	_nest_requests += 1
	_check(
		run.resolve_nest_spawn(Vector2(float(run.generated_nests) * 100.0, 300.0)),
		"An accepted recurring roll places its requested species."
	)
	_check(run.nests.back().species == species, "The placement preserves the rolled species.")


func _count_nest_request(_species: NestState.Species) -> void:
	_nest_requests += 1


func _create_run() -> PrototypeRun:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS
	root.add_child(run)
	run.start_run(_positions())
	return run


func _positions() -> Array[Vector2]:
	return [
		Vector2(-40, -200),
		Vector2(40, -200),
		Vector2(190, -60),
		Vector2(118, 162),
		Vector2(-118, 162)
	]


func _count_spawn_for_first_nest(nest_id: int) -> void:
	if nest_id == 1:
		_spawn_requests += 1


func _count_goal(run: PrototypeRun) -> void:
	_goal_count += 1
	_check(run.is_complete, "Completion observers receive the committed completed state.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
