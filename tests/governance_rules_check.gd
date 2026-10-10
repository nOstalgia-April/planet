extends SceneTree

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")

var _failures: Array[String] = []
var _spawn_requests: int = 0
var _auto_requests: int = 0
var _milestones: int = 0


func _init() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	_check_species_identity()
	_check_research_gates()
	_check_manual_combo()
	_check_automatic_accounting()
	_check_persistent_regions_and_restart()
	if _failures.is_empty():
		print(
			"PASS: distinct species regions, population counts, governance, combos, automation, and restart"
		)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check_species_identity() -> void:
	var run: PrototypeRun = _create_run()
	_check(
		(
			run.get_nest(1).species == NestState.Species.SLIME
			and run.get_nest(2).species == NestState.Species.MUCUS
			and run.get_nest(3).species == NestState.Species.SLIME
		),
		"The first three configured regions contain two slime nests and one separate mucus nest."
	)
	run.advance(SETTINGS.spawn_intervals[0])
	_check(
		(
			run.get_species_population(NestState.Species.SLIME) == 2
			and run.get_species_population(NestState.Species.MUCUS) == 1
		),
		"Species totals count actual spawned individuals from their source regions."
	)
	_check(run.get_species_population(-1) == 0, "An unknown species has no live population.")
	run.collect_slime(2)
	_check(
		(
			run.get_species_population(NestState.Species.SLIME) == 2
			and run.get_species_population(NestState.Species.MUCUS) == 0
		),
		"Collecting a mucus individual changes only the mucus population."
	)
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_pipe()
	for _tier: int in range(3):
		run.purchase_technology("governance")
		run.upgrade_nest(2)
		_check(
			run.get_nest(2).species == NestState.Species.MUCUS,
			"Governance preserves the identity of a mucus region at every stage."
		)
	run.purchase_technology("valuable")
	_check(
		(
			run.get_nest(2).species == NestState.Species.MUCUS
			and run.valuable_level == 1
			and run.get_nest(4).species == NestState.Species.MUCUS
		),
		"High-value research preserves species and expansion uses the next configured region identity."
	)
	run.get_nest(2).alive_slimes = 5
	run.get_nest(4).alive_slimes = 7
	_check(
		run.get_species_population(NestState.Species.MUCUS) == 12,
		"The mucus population includes both governed and newly discovered regions."
	)
	run.collect_automatic(2, 4)
	var net_sources: Array[int] = [4, 1]
	run.collect_net_batch(net_sources)
	_check(
		(
			run.get_species_population(NestState.Species.MUCUS) == 10
			and run.get_species_population(NestState.Species.SLIME) == 1
		),
		"Automatic and net capture update each source species independently."
	)
	run.start_run(_positions())
	_check(
		(
			run.get_nest(2).species == NestState.Species.MUCUS
			and run.get_species_population(NestState.Species.SLIME) == 0
			and run.get_species_population(NestState.Species.MUCUS) == 0
		),
		"Restart restores the configured region identities and clears all live populations."
	)
	var alternate_settings: PrototypeSettings = SETTINGS.duplicate() as PrototypeSettings
	alternate_settings.nest_species = PackedInt32Array([1, 0, 1, 0, 1])
	run.settings = alternate_settings
	run.start_run(_positions())
	_check(
		(
			run.get_nest(1).species == NestState.Species.MUCUS
			and run.get_nest(2).species == NestState.Species.SLIME
		),
		"Region identity follows the settings resource rather than a fixed spawn pattern."
	)
	run.free()


func _check_research_gates() -> void:
	var run: PrototypeRun = _create_run()
	_check(not run.purchase_technology("pipe"), "Research needs sufficient candy.")
	run.candy = 10000
	var balance: int = run.candy
	_check(not run.upgrade_nest(1), "A region cannot skip governance research.")
	_check(not run.purchase_technology("unknown"), "Unknown research is rejected.")
	_check(not run.purchase_technology("valuable"), "High-value branch needs partial governance.")
	_check(run.candy == balance, "Rejected purchases do not charge candy.")
	_check(run.purchase_technology("governance"), "The first governance research is available.")
	_check(
		run.upgrade_nest(1) and run.get_nest(1).level == 1,
		"Research permits matching region construction."
	)
	balance = run.candy
	_check(not run.upgrade_nest(1), "One research tier cannot construct the next stage.")
	_check(
		not run.purchase_technology("governance"),
		"Partial governance requires the first pipe tier."
	)
	_check(not run.purchase_technology("combo"), "Combo branch requires the first pipe tier.")
	_check(run.candy == balance, "Prerequisite failure preserves the balance.")
	_check(
		run.upgrade_pipe() and run.purchase_technology("governance"),
		"Tool research opens partial governance."
	)
	_check(run.upgrade_nest(1), "Partial automation can be installed after its research.")
	var valuable_cost: int = run.get_technology_cost("valuable")
	balance = run.candy
	_check(run.purchase_technology("valuable"), "High-value research is purchased for a region.")
	_check(
		run.candy == balance - valuable_cost,
		"High-value branch charges exactly its displayed cost."
	)
	_check(run.valuable_level == 1, "High-value research is stored once for all regions.")
	balance = run.candy
	_check(not run.purchase_technology("valuable"), "A maxed branch cannot be purchased twice.")
	_check(not run.purchase_technology("unknown"), "An invalid research ID cannot buy research.")
	_check(run.candy == balance, "Maxed and invalid branches never charge candy.")
	_check(
		not run.purchase_technology("governance"),
		"Stable governance requires the second pipe tier."
	)
	_check(
		run.upgrade_pipe() and run.purchase_technology("governance"),
		"The final governance tier is reachable."
	)
	_check(run.get_technology_cost("governance") == -1, "Maxed research reports no next cost.")
	_check(not run.purchase_technology("governance"), "Maxed governance cannot charge again.")
	run.free()


func _check_manual_combo() -> void:
	for tier: int in range(1, 4):
		var run: PrototypeRun = _create_run()
		run.combo_level = tier
		run.get_nest(1).alive_slimes = 30
		for _index: int in range(4):
			run.collect_slime(1)
		_check(
			run.combo_count == 4 and run.candy == 4 * SETTINGS.slime_reward,
			"The first four captures only pay ordinary rewards."
		)
		run.collect_slime(1)
		_check(
			run.combo_count == 0 and run.candy == 5 * SETTINGS.slime_reward + tier,
			"Every fifth manual capture pays the researched +1/+2/+3 bonus."
		)
		var balance: int = run.candy
		_check(
			not run.collect_slime(999) and run.combo_count == 0 and run.candy == balance,
			"Rejected captures cannot advance or pay a combo."
		)
		run.collect_slime(1)
		run.collect_slime(1)
		var ids: Array[int] = [1, 1, 1]
		var reward: int = run.collect_net_batch(ids)
		_check(
			reward == 3 * SETTINGS.slime_reward + tier and run.combo_count == 0,
			"Pipe and net share the same manual combo progress."
		)
		run.collect_slime(1)
		run.advance(SETTINGS.combo_window_seconds + 0.1)
		_check(
			run.combo_count == 0 and is_zero_approx(run.combo_remaining),
			"An idle combo expires without removing earned candy."
		)
		run.free()
	var run: PrototypeRun = _create_run()
	run.combo_level = 2
	run.get_nest(1).alive_slimes = 20
	var ids: Array[int] = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
	_check(
		run.collect_net_batch(ids) == SETTINGS.net_capacities[0] * SETTINGS.slime_reward + 4,
		"A large net pays bonuses only for captures inside capacity."
	)
	_check(
		run.get_nest(1).alive_slimes == 10 and run.combo_count == 0,
		"Net overflow neither removes bodies nor advances the combo."
	)
	var mixed_ids: Array[int] = [999, 1, 1]
	var mixed_rewards: Array[int] = [99, 6, 2]
	_check(
		run.collect_net_batch(mixed_ids, mixed_rewards) == 8,
		"Per-individual rewards remain aligned when invalid targets are skipped."
	)
	_check(run.combo_count == 2, "Only valid net targets count toward the next combo.")
	run.free()


func _check_automatic_accounting() -> void:
	var run: PrototypeRun = _create_run()
	var nest: NestState = run.get_nest(1)
	nest.level = 1
	nest.alive_slimes = 10
	_auto_requests = 0
	run.auto_collect_requested.connect(_count_auto)
	run.advance(1.0)
	_check(
		_auto_requests == 0 and not run.collect_automatic(1),
		"Guided regions do not automate collection."
	)
	nest.level = 2
	run.advance(3.0)
	_check(
		_auto_requests > 0 and run.candy == 0,
		"An automation request alone never creates passive candy."
	)
	run.combo_level = 3
	run.combo_count = 3
	run.combo_remaining = SETTINGS.combo_window_seconds
	var population: int = nest.alive_slimes
	_check(run.collect_automatic(1, 6), "An actual automatic capture can pay an explicit reward.")
	_check(
		nest.alive_slimes == population - 1 and run.candy == 6,
		"Automatic capture decrements a real population slot and pays once."
	)
	_check(run.combo_count == 3, "Automatic captures do not advance the manual combo.")
	run.auto_collect_requested.connect(_complete_automatic_capture.bind(run))
	var balance: int = run.candy
	run.advance(1.2)
	_check(
		run.candy > balance and run.combo_count == 3,
		"The request-to-actor callback can collect without generating combo rewards."
	)
	_check(
		run.get_passive_income() > 0.0, "Installed automation advertises theoretical throughput."
	)
	nest.alive_slimes = 0
	balance = run.candy
	_check(
		not run.collect_automatic(1) and run.candy == balance,
		"An empty region cannot pay an automatic reward."
	)
	run.free()


func _check_persistent_regions_and_restart() -> void:
	var run: PrototypeRun = _create_run()
	run.candy = 10000
	run.upgrade_pipe()
	run.upgrade_pipe()
	for _tier: int in range(3):
		run.purchase_technology("governance")
	var nest: NestState = run.get_nest(1)
	nest.alive_slimes = 7
	var starting_regions: int = run.nests.size()
	for _tier: int in range(3):
		run.upgrade_nest(1)
	_check(
		nest.is_tamed and nest.alive_slimes == 7,
		"Stable governance preserves the region and its existing population."
	)
	_check(
		run.nests.size() == starting_regions + 1 and run.get_nest(1) == nest,
		"A stable region frees attention for a new region without disappearing."
	)
	_spawn_requests = 0
	run.slime_requested.connect(_count_spawn)
	run.advance(1.0)
	_check(
		_spawn_requests > 0 and nest.alive_slimes > 7,
		"Stable ecosystems continue creating real individuals."
	)
	_check(
		nest.alive_slimes <= run.get_nest_population_limit(1),
		"Stable ecosystems use a valid population cap."
	)
	_milestones = 0
	run.goal_completed.connect(_on_milestone.bind(run))
	for nest_id: int in range(2, SETTINGS.nest_budget + 1):
		for _tier: int in range(3):
			_check(run.upgrade_nest(nest_id), "Every generated region can reach stable governance.")
	_check(
		run.is_complete and _milestones == 1 and run.nests.size() == SETTINGS.nest_budget,
		"All regions trigger one milestone while remaining on the planet."
	)
	_check(
		run.collect_slime(1) and run.begin_net_cast(),
		"Manual tools continue after the governance milestone."
	)
	_check(run.upgrade_pipe(), "Remaining tool research continues after the milestone.")
	_check(run.purchase_technology("valuable"), "Regional research continues after the milestone.")
	run.advance(SETTINGS.net_cooldown_seconds)
	_check(
		run.can_cast_net() and _milestones == 1,
		"Time and cooldowns continue without repeating the milestone."
	)
	run.start_run(_positions())
	_check(
		not run.is_complete and run.completed_nests == 0 and run.candy == 0,
		"Restart clears completion and economy."
	)
	_check(
		run.governance_level == 0 and run.combo_level == 0 and run.combo_count == 0,
		"Restart clears all new research and combo state."
	)
	_check(
		run.nests.size() == SETTINGS.initial_nests and run.valuable_level == 0,
		"Restart rebuilds fresh regional research state."
	)
	_check(
		run.can_cast_net() and is_zero_approx(run.get_nest(1).automatic_clock),
		"Restart clears automatic and manual tool timers."
	)
	run.free()


func _create_run() -> PrototypeRun:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS
	root.add_child(run)
	run.start_run(_positions())
	return run


func _positions() -> Array[Vector2]:
	return [
		Vector2(0, -200),
		Vector2(190, -60),
		Vector2(118, 162),
		Vector2(-118, 162),
		Vector2(-190, -60)
	]


func _count_spawn(_nest_id: int) -> void:
	_spawn_requests += 1


func _count_auto(_nest_id: int) -> void:
	_auto_requests += 1


func _complete_automatic_capture(nest_id: int, run: PrototypeRun) -> void:
	run.collect_automatic(nest_id)


func _on_milestone(run: PrototypeRun) -> void:
	_milestones += 1
	_check(run.is_complete, "Milestone listeners observe completed state before their callback.")
	_check(not run.upgrade_nest(1), "A reentrant upgrade cannot complete the same region twice.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
