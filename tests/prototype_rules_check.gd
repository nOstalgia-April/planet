extends SceneTree

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")

var _spawn_requests: int = 0
var _completion_signals: int = 0
var _failures: Array[String] = []


func _init() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS
	root.add_child(run)
	run.slime_requested.connect(_on_slime_requested)
	run.goal_completed.connect(_on_goal_completed.bind(run))
	var positions: Array[Vector2] = [
		Vector2(0.0, -200.0),
		Vector2(190.0, -60.0),
		Vector2(118.0, 162.0),
		Vector2(-118.0, 162.0),
		Vector2(-190.0, -60.0),
	]
	run.start_run(positions)
	_check(
		(
			run.nests.size() == SETTINGS.initial_nests
			and run.generated_nests == SETTINGS.initial_nests
		),
		"The configured initial nests begin the run."
	)
	_check(run.get_nest(1).position == positions[0], "Candidate position order is preserved.")
	_check(
		run.get_net_radius() > run.get_pipe_radius(), "The larger net is available at the start."
	)
	_check(
		(
			_prices_increase(SETTINGS.nest_upgrade_costs)
			and _prices_increase(SETTINGS.pipe_upgrade_costs)
			and _prices_increase(SETTINGS.net_upgrade_costs)
		),
		"Each purchase path increases its price at each tier."
	)
	_check(
		not run.upgrade_pipe() and not run.upgrade_net() and not run.upgrade_nest(1),
		"Insufficient candy rejects all upgrade paths."
	)
	run.candy = -1
	_check(
		not run.upgrade_pipe() and not run.upgrade_net() and not run.upgrade_nest(1),
		"A negative balance rejects every purchase."
	)
	_check(
		(
			run.candy == -1
			and run.pipe_level == 0
			and run.net_level == 0
			and run.get_nest(1).level == 0
		),
		"Rejected purchases preserve balances and independent levels."
	)
	_check(run.can_cast_net() and run.begin_net_cast(), "The first cast begins the net cooldown.")
	_check(
		not run.can_cast_net() and not run.begin_net_cast(), "Cooldown rejects another net cast."
	)
	run.advance(0.2)
	var cooldown_before: float = run.net_cooldown_remaining
	run.advance(-1.0)
	_check(
		is_equal_approx(run.net_cooldown_remaining, cooldown_before),
		"A negative delta cannot extend or consume the net cooldown."
	)
	run.candy = _sum_costs(SETTINGS.pipe_upgrade_costs) + _sum_costs(SETTINGS.net_upgrade_costs)
	var initial_radius: float = run.get_pipe_radius()
	var initial_attraction_radius: float = run.get_pipe_attraction_radius()
	var initial_capture: float = run.get_pipe_capture_seconds()
	var initial_net_radius: float = run.get_net_radius()
	var initial_net_capacity: int = run.get_net_capacity()
	for level: int in range(SETTINGS.pipe_upgrade_costs.size()):
		var balance_before: int = run.candy
		var cost: int = SETTINGS.pipe_upgrade_costs[level]
		var previous_seconds: float = run.get_pipe_capture_seconds()
		_check(
			run.get_pipe_upgrade_cost() == cost and run.upgrade_pipe(),
			"Pipe tiers advertise and charge their price."
		)
		_check(run.candy == balance_before - cost, "A pipe upgrade deducts its price once.")
		_check(
			run.get_pipe_capture_seconds() < previous_seconds,
			"Pipe upgrades speed up single-body processing."
		)
		_check(
			(
				is_equal_approx(run.get_pipe_radius(), initial_radius)
				and is_equal_approx(run.get_pipe_attraction_radius(), initial_attraction_radius)
				and run.net_level == 0
				and run.get_net_capacity() == initial_net_capacity
				and is_equal_approx(run.get_net_radius(), initial_net_radius)
				and is_equal_approx(run.net_cooldown_remaining, cooldown_before)
			),
			"Pipe speed upgrades preserve both radii, net capacity and net cooldown."
		)
	var final_pipe_seconds: float = run.get_pipe_capture_seconds()
	for level: int in range(SETTINGS.net_upgrade_costs.size()):
		var balance_before: int = run.candy
		var cost: int = SETTINGS.net_upgrade_costs[level]
		var previous_capacity: int = run.get_net_capacity()
		_check(
			run.get_net_upgrade_cost() == cost and run.upgrade_net(),
			"Net tiers advertise and charge their price."
		)
		_check(run.candy == balance_before - cost, "A net upgrade deducts its price once.")
		_check(
			run.get_net_capacity() > previous_capacity, "Net upgrades only increase catch capacity."
		)
		_check(
			(
				is_equal_approx(run.get_pipe_capture_seconds(), final_pipe_seconds)
				and is_equal_approx(run.get_pipe_radius(), initial_radius)
				and is_equal_approx(run.get_pipe_attraction_radius(), initial_attraction_radius)
				and is_equal_approx(run.get_net_radius(), initial_net_radius)
				and is_equal_approx(run.net_cooldown_remaining, cooldown_before)
			),
			"Net capacity upgrades preserve pipe speed, both tools' radii and current cooldown."
		)
	_check(
		run.candy == 0 and run.get_pipe_upgrade_cost() == -1 and run.get_net_upgrade_cost() == -1,
		"The independent complete paths cost their configured sums and then stop upgrading."
	)
	_check(
		not run.upgrade_pipe() and not run.upgrade_net(), "Maxed tool paths cannot upgrade again."
	)
	run.advance(cooldown_before)
	_check(
		run.can_cast_net() and is_zero_approx(run.net_cooldown_remaining),
		"Net cooldown reaches zero exactly."
	)
	_check(run.begin_net_cast(), "The net becomes available after its cooldown.")
	_check_net_batches(positions)

	run.advance(1000.0)
	var base_limit: int = SETTINGS.nest_population_limits[0]
	var initial_population: int = SETTINGS.initial_nests * base_limit
	_check(
		(
			run.get_nest_population_limit(1) == base_limit
			and run.get_nest(1).alive_slimes == base_limit
		),
		"Base nests stop at their configured current surface population limit."
	)
	_check(
		_spawn_requests == initial_population, "Initial nests request only their live population."
	)
	run.advance(1000.0)
	_check(_spawn_requests == initial_population, "Full nests stop requesting new monsters.")
	_check(run.collect_slime(1), "A living surface monster can be collected.")
	_check(
		(
			run.get_nest(1).alive_slimes == base_limit - 1
			and run.pending_slime_count == 1
			and run.pending_candy == SETTINGS.slime_reward
			and run.candy == 0
		),
		"Collection frees its surface slot immediately and withholds candy until settlement."
	)
	run.advance(SETTINGS.spawn_intervals[0])
	_check(
		run.get_nest(1).alive_slimes == base_limit and _spawn_requests == initial_population + 1,
		"One released population slot refills before the pending collection is settled."
	)
	for _index: int in range(base_limit + 3):
		_check(run.collect_slime(1), "Continuous collection can use newly replenished monsters.")
		run.advance(SETTINGS.spawn_intervals[0])
	var collected_count: int = base_limit + 4
	var batch_reward: int = collected_count * SETTINGS.slime_reward
	_check(
		(
			run.pending_slime_count == collected_count
			and run.pending_slime_count > base_limit
			and run.pending_candy == batch_reward
			and run.candy == 0
		),
		"A continuous collection batch exceeds the live population limit without a carry cap."
	)
	_check(
		run.settle_collection() == batch_reward, "Releasing collection pays the entire batch once."
	)
	_check(
		run.candy == batch_reward and run.pending_candy == 0 and run.pending_slime_count == 0,
		"Settlement clears the pending reward and collected count."
	)
	_check(run.settle_collection() == 0, "An empty collection cannot pay twice.")
	_check(not run.collect_slime(999), "An unknown source cannot be collected.")
	_check(run.get_nest_population_limit(999) == 0, "An unknown nest has no population allowance.")
	_check(
		run.candy == batch_reward and run.pending_candy == 0,
		"Invalid collection changes no reward."
	)

	# Funding isolates level transitions; the playthrough checks earned-candy reachability.
	run.candy = _sum_costs(SETTINGS.nest_upgrade_costs) * SETTINGS.nest_budget
	for level: int in range(1, SETTINGS.nest_population_limits.size()):
		var previous_population: int = run.get_nest(1).alive_slimes
		var previous_requests: int = _spawn_requests
		var price: int = run.get_nest_upgrade_cost(1)
		var before_purchase: int = run.candy
		_check(run.upgrade_nest(1), "An unfinished nest upgrades with enough candy.")
		_check(
			run.candy == before_purchase - price, "Each nest upgrade deducts its actual price once."
		)
		var population_limit: int = SETTINGS.nest_population_limits[level]
		_check(
			run.get_nest_population_limit(1) == population_limit,
			"The upgraded nest advertises its next current population limit."
		)
		run.advance(1000.0)
		_check(
			(
				run.get_nest(1).alive_slimes == population_limit
				and _spawn_requests == previous_requests + population_limit - previous_population
			),
			"An upgrade replenishes the nest up to the new tier without exceeding it."
		)
		var full_requests: int = _spawn_requests
		run.advance(1000.0)
		_check(_spawn_requests == full_requests, "Every unfinished tier stops spawning when full.")

	_check(run.collect_slime(1), "A collection can remain pending while its nest is tamed.")
	var remaining_population: int = run.get_nest(1).alive_slimes
	_check(run.upgrade_nest(1), "The final nest tier converts the nest to automatic income.")
	_check(
		run.get_nest(1).is_tamed and run.get_nest(1).alive_slimes == remaining_population,
		"Taming preserves the remaining surface monsters."
	)
	_check(
		run.generated_nests == 4 and run.completed_nests == 1,
		"Taming fills the freed active nest slot without refunding its budget."
	)
	_check(
		run.get_nest_upgrade_cost(1) == -1 and not run.upgrade_nest(1),
		"Tamed nests stop upgrading."
	)
	_check(
		is_equal_approx(run.get_passive_income(), SETTINGS.passive_income_per_second),
		"A tamed nest supplies its configured automatic income."
	)
	var candy_before_income: int = run.candy
	run.advance(0.2)
	_check(run.candy == candy_before_income, "Fractional automatic income is retained.")
	var remainder_before_negative: float = run.passive_remainder
	var requests_before_negative: int = _spawn_requests
	run.advance(-1.0)
	_check(
		(
			run.candy == candy_before_income
			and is_equal_approx(run.passive_remainder, remainder_before_negative)
			and _spawn_requests == requests_before_negative
		),
		"A negative delta cannot alter income or spawning."
	)
	run.advance(0.2)
	_check(run.candy == candy_before_income + 1, "Automatic income pays only whole candy.")
	_check(run.collect_slime(1), "Remaining monsters are collectible after their source is tamed.")
	_check(
		run.get_nest(1).alive_slimes == remaining_population - 1 and run.pending_slime_count == 2,
		"Tamed-source collection frees live population and joins the same pending batch."
	)
	_check(_tame(run, 2), "The second nest can be fully tamed.")
	_check(run.generated_nests == SETTINGS.nest_budget, "Replacement nests use the finite budget.")
	_check(_tame(run, 3) and _tame(run, 4) and _tame(run, 5), "All remaining nests can be tamed.")
	_check(
		(
			run.is_complete
			and run.completed_nests == SETTINGS.nest_budget
			and run.generated_nests == SETTINGS.nest_budget
			and _completion_signals == 1
		),
		"Completing the finite nest budget emits the goal exactly once."
	)
	_check(
		run.pending_candy == 0 and run.pending_slime_count == 0,
		"Goal completion settles the last pending collection before ending the run."
	)
	var final_candy: int = run.candy
	var final_requests: int = _spawn_requests
	var final_population: int = run.get_nest(1).alive_slimes
	_check(
		not run.can_cast_net() and not run.begin_net_cast() and run.collect_net_batch([1]) == 0,
		"A completed run rejects net casts and batch rewards."
	)
	_check(
		not run.collect_slime(1) and run.settle_collection() == 0,
		"A completed run rejects collection and cannot repeat its settled reward."
	)
	run.advance(100.0)
	_check(
		(
			run.candy == final_candy
			and run.get_nest(1).alive_slimes == final_population
			and _spawn_requests == final_requests
		),
		"A completed run freezes income, spawning and collection."
	)
	_check(
		not run.upgrade_nest(5) and _completion_signals == 1,
		"Further actions cannot repeat the goal."
	)

	run.start_run(positions)
	run.advance(SETTINGS.spawn_intervals[0])
	_check(run.collect_slime(1), "Restart testing begins with an unsettled new collection.")
	_check(run.begin_net_cast(), "Restart testing also begins with an active net cooldown.")
	_check(
		run.pending_candy > 0 and run.pending_slime_count == 1,
		"A new run can have a pending batch."
	)
	run.start_run(positions)
	_check(
		run.candy == 0 and run.pending_candy == 0 and run.pending_slime_count == 0,
		"Restart discards the unsettled batch and resets the candy balance."
	)
	_check(
		run.settle_collection() == 0, "The previous run's pending batch cannot pay after restart."
	)
	_check(
		(
			run.pipe_level == 0
			and run.net_level == 0
			and is_equal_approx(run.get_pipe_capture_seconds(), initial_capture)
			and is_zero_approx(run.net_cooldown_remaining)
			and run.can_cast_net()
		),
		"Restart resets both technologies, pipe speed and the net cooldown."
	)
	_check(
		(
			run.generated_nests == SETTINGS.initial_nests
			and run.completed_nests == 0
			and not run.is_complete
			and run.get_nest(1).alive_slimes == 0
			and is_zero_approx(run.passive_remainder)
		),
		"Restart clears nest progress, populations and fractional income."
	)
	_check(not run.collect_slime(1), "An empty source cannot add to the collection batch.")
	run.advance(SETTINGS.spawn_intervals[0])
	_check(run.collect_slime(1), "A newly spawned source can be collected once.")
	_check(not run.collect_slime(1), "The same emptied source cannot invent another monster.")
	_check(
		run.pending_slime_count == 1 and run.pending_candy == SETTINGS.slime_reward,
		"Rejected duplicate collection preserves the pending count and reward."
	)
	if _failures.is_empty():
		print("Prototype rules: all boundary checks passed.")
		quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		quit(1)


func _check_net_batches(positions: Array[Vector2]) -> void:
	var net_run: PrototypeRun = PrototypeRun.new()
	net_run.settings = SETTINGS
	root.add_child(net_run)
	net_run.start_run(positions)
	net_run.advance(100.0)
	_check(net_run.collect_slime(1), "A pipe reward can remain pending during a net catch.")
	var population_before: int = _surface_population(net_run)
	var candidates: Array[int] = [999]
	for index: int in range(net_run.get_net_capacity() + 5):
		candidates.append(index % SETTINGS.initial_nests + 1)
	var expected_reward: int = net_run.get_net_capacity() * SETTINGS.slime_reward
	_check(
		net_run.collect_net_batch(candidates) == expected_reward,
		"A multi-source net catch is truncated to its current capacity and pays immediately."
	)
	_check(
		(
			net_run.candy == expected_reward
			and _surface_population(net_run) == population_before - net_run.get_net_capacity()
			and net_run.pending_slime_count == 1
			and net_run.pending_candy == SETTINGS.slime_reward
		),
		"Net catches free their live stock while keeping the pipe batch independent."
	)
	var same_source: Array[int] = []
	for _index: int in range(net_run.get_net_capacity() + 5):
		same_source.append(1)
	var source_population: int = net_run.get_nest(1).alive_slimes
	_check(
		net_run.collect_net_batch(same_source) == source_population * SETTINGS.slime_reward,
		"Repeated source IDs collect only the real monsters left in that source."
	)
	_check(
		net_run.collect_net_batch(same_source) == 0 and net_run.collect_net_batch([999]) == 0,
		"Empty and unknown sources cannot create net rewards."
	)
	var before_pipe_settlement: int = net_run.candy
	_check(
		net_run.settle_collection() == SETTINGS.slime_reward,
		"The independent pipe batch still settles once."
	)
	_check(
		net_run.candy == before_pipe_settlement + SETTINGS.slime_reward,
		"Settling the pipe cannot repeat already paid net income."
	)
	net_run.queue_free()


func _surface_population(run: PrototypeRun) -> int:
	var population: int = 0
	for nest: NestState in run.nests:
		population += nest.alive_slimes
	return population


func _tame(run: PrototypeRun, nest_id: int) -> bool:
	for level: int in range(SETTINGS.nest_upgrade_costs.size()):
		var balance_before: int = run.candy
		var cost: int = SETTINGS.nest_upgrade_costs[level]
		var pending_before: int = run.pending_candy
		_check(run.get_nest_upgrade_cost(nest_id) == cost, "Each nest tier advertises its price.")
		if not run.upgrade_nest(nest_id):
			return false
		var final_reward: int = pending_before if run.is_complete else 0
		_check(
			run.candy == balance_before - cost + final_reward,
			"Each nest tier deducts its price once and only the final goal settles pending candy."
		)
	return true


func _sum_costs(costs: PackedInt32Array) -> int:
	var total: int = 0
	for cost: int in costs:
		total += cost
	return total


func _prices_increase(costs: PackedInt32Array) -> bool:
	for tier: int in range(1, costs.size()):
		if costs[tier] <= costs[tier - 1]:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _on_slime_requested(_nest_id: int) -> void:
	_spawn_requests += 1


func _on_goal_completed(run: PrototypeRun) -> void:
	_completion_signals += 1
	_check(
		run.is_complete and run.pending_candy == 0 and run.pending_slime_count == 0,
		"The goal notification observes a completed run with its pending collection already settled."
	)
