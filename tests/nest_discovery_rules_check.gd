extends "res://tests/progressive_rules_check.gd"


func _run_checks() -> void:
	_check_opening_and_net_unlock()
	_check_nest_opening_delay()
	_check_continuous_discovery()
	_check_nest_discovery_cooldown()
	_check_governance_roll_weight()
	_check_existing_nests_completion()
	_check_minima_and_variation()
	_check_reserved_sites_and_retry()
	_check_weights_and_limits()
	if _failures.is_empty():
		print(
			"PASS: discovery timing, 1000 seeded minimum/random runs, weights, caps, retry and reset"
		)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check_minima_and_variation() -> void:
	var run: PrototypeRun = _create_run()
	var outcomes: Dictionary[Vector3i, int] = {}
	var extra_mucus: bool = false
	var extra_drill: bool = false
	for seed_index: int in range(1000):
		run.start_run(_positions(), 10)
		run._random.seed = seed_index
		while run.nests.size() < 10:
			_place_random_nest(run)
		var counts: Vector3i = _species_counts(run)
		_check(counts.x >= 4 and counts.y >= 2 and counts.z >= 1, "All minima fit in ten sites.")
		_check(counts.z <= 4, "Random drill discovery respects its cap.")
		outcomes[counts] = outcomes.get(counts, 0) + 1
		extra_mucus = extra_mucus or counts.y > 2
		extra_drill = extra_drill or counts.z > 1
	_check(outcomes.size() >= 6, "Full maps have varied compositions instead of a fixed ratio.")
	_check(extra_mucus and extra_drill, "Both mucus and drill can exceed their minima.")
	print("Seeded full-map compositions: ", outcomes)
	run.start_run(_positions(), 7)
	while run.nests.size() < 7:
		_place_random_nest(run)
	_check(_species_counts(run) == Vector3i(4, 2, 1), "Seven sites reserve the exact minima.")
	run.net_unlocked = true
	run._advance_nest_roll(1000.0)
	_check(run._pending_nest_species == -1, "A full map does not request more nests.")
	run.start_run(_positions(), 10)
	_check(_species_counts(run) == Vector3i(2, 0, 0), "Restart clears counts and site capacity.")
	run.free()


func _check_reserved_sites_and_retry() -> void:
	var run: PrototypeRun = _create_run()
	run.start_run(_positions(), 10)
	# Seven slimes leave precisely the three sites needed for mucus and drill.
	for index: int in range(5):
		run._add_nest(NestState.Species.SLIME, Vector2(200 + index * 100, 300))
	for nest: NestState in run.nests:
		nest.is_tamed = true
	for index: int in range(100):
		_check(
			run._choose_spawn_species() != NestState.Species.SLIME, "Flowers count toward minima."
		)
	run._add_nest(NestState.Species.MUCUS, Vector2(900, 300))
	run._add_nest(NestState.Species.MUCUS, Vector2(1000, 300))
	_check(
		run._choose_spawn_species() == NestState.Species.DRILL, "Last site reserves missing drill."
	)
	run._pending_nest_species = run._choose_spawn_species()
	_check(not run.resolve_nest_spawn(Vector2.ZERO, false), "Failed placement is rejected.")
	_check(run.nests.size() == 9, "Failed placement consumes no site or minimum.")
	_check(run._choose_spawn_species() == NestState.Species.DRILL, "Retry still reserves drill.")
	_place_random_nest(run)
	_check(_species_counts(run) == Vector3i(7, 2, 1), "Successful retry fulfills the guarantee.")
	for disable_by_cap: bool in [true, false]:
		run.settings.drill_nest_limit = 0 if disable_by_cap else 4
		run.settings.drill_discovery_weight = 0.5 if disable_by_cap else 0.0
		run.start_run(_positions(), 6)
		while run.nests.size() < 6:
			_place_random_nest(run)
		_check(_species_counts(run) == Vector3i(4, 2, 0), "Disabled drill reserves no sites.")
	run.settings.drill_nest_limit = 4
	run.settings.drill_discovery_weight = 0.5
	run.settings.nest_minimum_counts = PackedInt32Array([2, 1, 2])
	run.start_run(_positions(), 5)
	while run.nests.size() < 5:
		_place_random_nest(run)
	_check(_species_counts(run) == Vector3i(2, 1, 2), "Custom minima are independent of weights.")
	run.settings.drill_nest_limit = 1
	run.start_run(_positions(), 4)
	while run.nests.size() < 4:
		_place_random_nest(run)
	_check(_species_counts(run) == Vector3i(2, 1, 1), "Drill cap bounds its effective minimum.")
	run.free()


func _check_weights_and_limits() -> void:
	var run: PrototypeRun = _create_run()
	run.start_run(_positions(), 10)
	run._random.seed = 7814
	_check_sample_weights(run, Vector3(4.0 / 7.0, 2.0 / 7.0, 1.0 / 7.0))
	run.settings.unlocked_species_weights = PackedFloat32Array([1.0, 1.0])
	run.settings.drill_discovery_weight = 1.0
	_check_sample_weights(run, Vector3.ONE / 3.0)
	for index: int in range(4):
		run._add_nest(NestState.Species.DRILL, Vector2(200 + index * 100, 300))
	for index: int in range(1000):
		_check(
			run._choose_spawn_species() != NestState.Species.DRILL, "Capped drills leave the pool."
		)
	run.free()


func _check_sample_weights(run: PrototypeRun, expected: Vector3) -> void:
	var samples: Vector3 = Vector3.ZERO
	for index: int in range(14000):
		samples[run._choose_spawn_species()] += 1.0
	for species: int in range(3):
		_check(
			absf(samples[species] / 14000.0 - expected[species]) < 0.02, "Free rolls use weights."
		)


func _place_random_nest(run: PrototypeRun) -> void:
	run._pending_nest_species = run._choose_spawn_species()
	_check(
		run.resolve_nest_spawn(Vector2(run.nests.size() * 100.0, 300.0)),
		"Random choice resolves through normal placement."
	)


func _species_counts(run: PrototypeRun) -> Vector3i:
	var counts: Vector3i = Vector3i.ZERO
	for nest: NestState in run.nests:
		counts[nest.species] += 1
	return counts
