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
	_check_nest_opening_delay()
	_check_bursts_and_population_tiers()
	_check_random_spawn_cooldowns()
	_check_automatic_income()
	_check_continuous_pipe_combo()
	_check_tool_tiers()
	_check_continuous_discovery()
	_check_nest_discovery_cooldown()
	_check_governance_roll_weight()
	_check_existing_nests_completion()
	if _failures.is_empty():
		print(
			"PASS: opening protection, burst cooldowns, paced discovery, completion and tool progression"
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
		run.nests.size() == 2 and run.generated_nests == 2, "Net unlock does not introduce a nest."
	)
	run.candy = 1000
	_check(run.upgrade_net() and run.net_level == 1, "Later net purchases upgrade its capacity.")
	_check(run.nests.size() == 2, "Capacity upgrades do not introduce nests.")
	run.start_run(_positions())
	_check(
		not run.net_unlocked and run.nests.size() == 2 and run.completed_nests == 0,
		"Restart restores the two basic nests and relocks the net."
	)
	run.free()


func _check_nest_opening_delay() -> void:
	var run: PrototypeRun = _create_run(SETTINGS.nest_initial_delay_seconds)
	run.settings.nest_roll_chance_min = 1.0
	run.settings.nest_roll_chance_max = 1.0
	_nest_requests = 0
	run.nest_spawn_requested.connect(_place_requested_nest.bind(run))
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_net()
	run.advance(run.settings.nest_initial_delay_seconds - 1.0)
	_check(
		_nest_requests == 0 and run.nests.size() == 2 and run._nest_roll_clock == 0.0,
		"Even immediate net unlock cannot add nests or bank rolls during opening protection."
	)
	_check(
		run.get_nest(1).alive_slimes > 0,
		"The two opening nests keep producing monsters throughout opening protection."
	)
	run.advance(1.0)
	_check(
		_nest_requests == 0 and run._nest_initial_delay_remaining == 0.0,
		"Opening protection expiring does not immediately add a nest."
	)
	run.advance(run.settings.nest_roll_interval - 0.01)
	_check(_nest_requests == 0, "The first opening roll waits for a full check interval.")
	run.advance(0.02)
	_check(
		_nest_requests == 1, "Discovery becomes eligible after opening protection and net unlock."
	)
	run.start_run(_positions())
	_nest_requests = 0
	_check(
		(
			run._nest_initial_delay_remaining == run.settings.nest_initial_delay_seconds
			and run._nest_spawn_cooldown_remaining == 0.0
			and run.nests.size() == 2
		),
		"Restart restores opening protection and clears the previous success cooldown."
	)
	run.advance(run.settings.nest_initial_delay_seconds + 10.0)
	_check(
		_nest_requests == 0 and run._nest_initial_delay_remaining == 0.0,
		"Opening protection counts from game start while the net remains locked."
	)
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_net()
	run.advance(run.settings.nest_roll_interval)
	_check(_nest_requests == 1, "Late net unlock does not restart the opening protection timer.")
	run.start_run(_positions())
	_nest_requests = 0
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_net()
	run.advance(run.settings.nest_initial_delay_seconds + run.settings.nest_roll_interval)
	_check(_nest_requests == 1, "A long update consumes opening protection before its first roll.")
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
		run.advance(run.get_nest_spawn_interval(1))
		_check(nest.alive_slimes == capacity, "The final burst clips to remaining capacity.")
		run.advance(interval * 20.0)
		_check(nest.alive_slimes == capacity, "A full nest cannot overfill during a long update.")
		nest.level = 3
		_check(
			run.get_nest_population_limit(1) == 60,
			"The final automated stage retains the sixty-monster capacity."
		)
		run.free()


func _check_random_spawn_cooldowns() -> void:
	var run: PrototypeRun = _create_run()
	run._random.seed = 72861
	run._add_nest(NestState.Species.MUCUS, Vector2(200, -200))
	run._add_nest(NestState.Species.SLIME, Vector2(300, -200))
	_check(
		not is_equal_approx(run.get_nest_spawn_interval(3), run.get_nest_spawn_interval(4)),
		"New nests of either species receive independent cooldowns."
	)
	for tier: int in range(3):
		var nest: NestState = run.get_nest(1)
		nest.level = tier
		var base_interval: float = run.settings.spawn_intervals[tier]
		for _cycle: int in range(8):
			nest.alive_slimes = 0
			nest.spawn_clock = 0.0
			var interval: float = run.get_nest_spawn_interval(1)
			_check(
				absf(interval - base_interval) <= run.settings.spawn_interval_jitter,
				"Every tier stays within its configured cooldown range."
			)
			run._advance_nest_population(nest, interval - 0.01)
			_check(nest.alive_slimes == 0, "The sampled cooldown gates its entire burst.")
			_check(
				is_equal_approx(run.get_nest_spawn_interval(1), interval),
				"Advancing or querying a running cooldown never rerolls it."
			)
			run._advance_nest_population(nest, 0.02)
			_check(nest.alive_slimes > 0, "The nest spawns when its sampled cooldown expires.")
			_check(
				not is_equal_approx(run.get_nest_spawn_interval(1), interval),
				"Every completed burst samples a fresh cooldown."
			)
	var nest: NestState = run.get_nest(1)
	nest.level = 0
	nest.alive_slimes = run.get_nest_population_limit(1)
	run._advance_nest_population(nest, 100.0)
	_check(nest.spawn_clock == 0.0, "A full nest does not bank cooldown progress.")
	run.collect_slime(1)
	var interval: float = run.get_nest_spawn_interval(1)
	run._advance_nest_population(nest, interval - 0.01)
	_check(nest.alive_slimes == 9, "A reopened slot waits for a full sampled cooldown.")
	run._advance_nest_population(nest, 0.02)
	_check(nest.alive_slimes == 10, "The resumed burst clips to the reopened slot.")
	run.candy = 10000
	_enable_full_governance(run)
	nest.spawn_clock = 1.0
	interval = run.get_nest_spawn_interval(1)
	_check(run.upgrade_nest(1), "Cultivation upgrades the tested nest.")
	_check(
		is_equal_approx(run.get_nest_spawn_interval(1), interval + 1.0) and nest.spawn_clock == 1.0,
		"Cultivation changes the base interval while retaining progress and the sampled offset."
	)
	run.settings = SETTINGS.duplicate() as PrototypeSettings
	run.settings.spawn_interval_jitter = 0.0
	run.start_run(_positions())
	_check(
		run.get_nest_spawn_interval(1) == SETTINGS.spawn_intervals[0],
		"Disabling jitter restores fixed intervals on a new run."
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
			run.combo_count == 8 and run.candy == 8 * SETTINGS.slime_reward + [1, 3, 4][tier - 1],
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
	settings.nest_initial_delay_seconds = 0.0
	settings.nest_roll_chance_min = 1.0
	settings.nest_roll_chance_max = 1.0
	run.settings = settings
	_nest_requests = 0
	run.nest_spawn_requested.connect(_place_requested_nest.bind(run))
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_net()
	_check(_nest_requests == 0, "Net unlock does not request an immediate nest placement.")
	run._random.seed = 72861
	run.advance(settings.nest_roll_interval - 0.01)
	_check(run.nests.size() == 2, "Unlocking starts a fresh interval before any recurring roll.")
	run.advance(0.02)
	_check(
		run.nests.size() == 3 and run.governance_level == 0 and run.completed_nests == 0,
		"Recurring discovery starts after the first full interval following net unlock."
	)
	run.advance((settings.nest_spawn_cooldown_seconds + settings.nest_roll_interval) * 30.0)
	var slime_nests: int = 0
	var mucus_nests: int = 0
	for nest: NestState in run.nests:
		if nest.species == NestState.Species.SLIME:
			slime_nests += 1
		else:
			mucus_nests += 1
	_check(
		run.nests.size() == 33 and _nest_requests == 31 and slime_nests > 3 and mucus_nests > 2,
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
		_nest_requests == 1 and pending_run.nests.size() == 2,
		"A pending placement request cannot duplicate itself while awaiting a site."
	)
	_check(
		pending_run._nest_spawn_cooldown_remaining == 0.0,
		"A request that has not landed does not start the success cooldown."
	)
	_check(
		not pending_run.resolve_nest_spawn(Vector2.ZERO, false),
		"No valid surface site declines the request without inventing a nest."
	)
	_check(
		pending_run._nest_spawn_cooldown_remaining == 0.0,
		"An unavailable site leaves the next recurring roll eligible."
	)
	pending_run.advance(settings.nest_roll_interval)
	_check(
		_nest_requests == 2 and pending_run.resolve_nest_spawn(Vector2(300, 0)),
		"A later successful roll can place a nest after an unavailable site."
	)
	_check(
		not pending_run.resolve_nest_spawn(Vector2(400, 0)) and pending_run.nests.size() == 3,
		"Each placement request can add at most one nest."
	)
	pending_run.free()


func _check_nest_discovery_cooldown() -> void:
	var run: PrototypeRun = _create_run()
	var settings: PrototypeSettings = SETTINGS.duplicate() as PrototypeSettings
	settings.nest_initial_delay_seconds = 0.0
	settings.nest_roll_chance_min = 1.0
	settings.nest_roll_chance_max = 1.0
	run.settings = settings
	_nest_requests = 0
	run.nest_spawn_requested.connect(_place_requested_nest.bind(run))
	_check(
		run._nest_spawn_cooldown_remaining == 0.0,
		"The two fixed opening nests do not impose a discovery cooldown."
	)
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_net()
	run.advance(settings.nest_roll_interval)
	_check(
		(
			_nest_requests == 1
			and run._nest_spawn_cooldown_remaining == settings.nest_spawn_cooldown_seconds
		),
		"A successfully placed nest starts the global cooldown."
	)
	var population: int = run.get_nest(1).alive_slimes
	run.advance(settings.nest_spawn_cooldown_seconds)
	_check(
		_nest_requests == 1 and run._nest_roll_clock == 0.0,
		"Cooldown time cannot bank discovery rolls or spawn immediately on expiry."
	)
	_check(
		run.get_nest(1).alive_slimes > population,
		"Discovery cooldown does not pause existing nests' monster production."
	)
	run.advance(settings.nest_roll_interval - 0.01)
	_check(_nest_requests == 1, "The first post-cooldown roll waits for its full interval.")
	run.advance(0.02)
	_check(_nest_requests == 2, "The next successful roll creates exactly one additional nest.")
	run.start_run(_positions())
	_check(
		run._nest_spawn_cooldown_remaining == 0.0 and run._nest_roll_clock == 0.0,
		"Restart clears success cooldown and recurring roll progress."
	)
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_net()
	_enable_full_governance(run)
	run.advance(settings.nest_roll_interval)
	_check(
		run._nest_spawn_cooldown_remaining > 0.0,
		"The completion fixture begins during an active discovery cooldown."
	)
	for nest: NestState in run.nests:
		for _stage: int in range(3):
			run.upgrade_nest(nest.nest_id)
	_check(
		run.is_complete and run._nest_spawn_cooldown_remaining == 0.0,
		"Completion keeps discovery stopped with no leftover success cooldown."
	)
	run.free()
	var fixed_step_run: PrototypeRun = _create_run()
	fixed_step_run.settings = settings
	fixed_step_run.candy = 10000
	fixed_step_run.upgrade_pipe()
	fixed_step_run.upgrade_net()
	_nest_requests = 0
	fixed_step_run.nest_spawn_requested.connect(_place_requested_nest.bind(fixed_step_run))
	for _step: int in range(750):
		fixed_step_run._advance_nest_roll(0.1)
	_check(
		_nest_requests == 3 and fixed_step_run.nests.size() == 5,
		"Small updates preserve the same three placements over seventy-five seconds."
	)
	var long_step_run: PrototypeRun = _create_run()
	long_step_run.settings = settings
	long_step_run.candy = 10000
	long_step_run.upgrade_pipe()
	long_step_run.upgrade_net()
	_nest_requests = 0
	long_step_run.nest_spawn_requested.connect(_place_requested_nest.bind(long_step_run))
	long_step_run._advance_nest_roll(75.0)
	_check(
		(
			_nest_requests == 3
			and is_equal_approx(
				long_step_run._nest_spawn_cooldown_remaining,
				fixed_step_run._nest_spawn_cooldown_remaining
			)
		),
		"A long update consumes intervening cooldowns instead of granting extra placements."
	)
	fixed_step_run.free()
	long_step_run.start_run(_positions())
	settings.nest_spawn_cooldown_seconds = 0.0
	long_step_run.candy = 10000
	long_step_run.upgrade_pipe()
	long_step_run.upgrade_net()
	_nest_requests = 0
	long_step_run._advance_nest_roll(settings.nest_roll_interval * 3.0)
	_check(_nest_requests == 3, "A zero cooldown restores interval-only discovery.")
	long_step_run.free()


func _check_governance_roll_weight() -> void:
	var run: PrototypeRun = _create_run()
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_net()
	_enable_full_governance(run)
	_check(
		is_equal_approx(run.get_nest_roll_chance(), 0.25),
		"An unmanaged planet starts with twenty-five percent roll chance."
	)
	for _index: int in range(3):
		run.upgrade_nest(1)
	_check(
		is_equal_approx(run.get_nest_roll_chance(), 0.4),
		"One fully governed nest among two raises the chance to forty percent."
	)
	for _index: int in range(3):
		run.upgrade_nest(2)
	_check(
		is_equal_approx(run.get_nest_roll_chance(), 0.55),
		"Average governance scales the configured roll chance up to fifty-five percent."
	)
	run.free()


func _check_existing_nests_completion() -> void:
	var locked_run: PrototypeRun = _create_run(SETTINGS.nest_initial_delay_seconds)
	locked_run.candy = 10000
	_enable_full_governance(locked_run)
	for nest_id: int in [1, 2]:
		for _index: int in range(3):
			locked_run.upgrade_nest(nest_id)
	_check(
		(
			locked_run.is_complete
			and not locked_run.net_unlocked
			and locked_run._nest_initial_delay_remaining == 0.0
		),
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
	settings.nest_initial_delay_seconds = 0.0
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
	for nest_id: int in [1, 2]:
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
		run.nests.size() == 2 and _goal_count == 1,
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


func _create_run(initial_delay_seconds: float = 0.0) -> PrototypeRun:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS.duplicate() as PrototypeSettings
	run.settings.nest_initial_delay_seconds = initial_delay_seconds
	root.add_child(run)
	run.start_run(_positions())
	return run


func _positions() -> Array[Vector2]:
	return [Vector2(-40, -200), Vector2(40, -200)]


func _count_spawn_for_first_nest(nest_id: int) -> void:
	if nest_id == 1:
		_spawn_requests += 1


func _count_goal(run: PrototypeRun) -> void:
	_goal_count += 1
	_check(run.is_complete, "Completion observers receive the committed completed state.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
