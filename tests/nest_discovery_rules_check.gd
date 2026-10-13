extends "res://tests/progressive_rules_check.gd"


func _run_checks() -> void:
	_check_opening_and_net_unlock()
	_check_nest_opening_delay()
	_check_continuous_discovery()
	_check_nest_discovery_cooldown()
	_check_governance_roll_weight()
	_check_existing_nests_completion()
	_check_species_proportions()
	_check_species_limits_and_retry()
	if _failures.is_empty():
		print(
			"PASS: discovery timing, 1000 seeded 4:2:1 runs, species caps, failed placement and reset"
		)
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check_species_proportions() -> void:
	var run: PrototypeRun = _create_run()
	for seed_index: int in range(1000):
		run.start_run(_positions())
		run._random.seed = seed_index
		for total: int in range(3, 35):
			_place_proportional_nest(run)
			var counts: PackedInt32Array = _species_counts(run)
			if total == 4:
				_check(counts == PackedInt32Array([2, 1, 1]), "All species exist by nest four.")
			if total == 7 or total == 14 or total == 28:
				_check(
					counts == PackedInt32Array([total * 4 / 7, total * 2 / 7, total / 7]),
					"Seven-nest multiples exactly match 4:2:1 before the drill cap."
				)
			if total == 10:
				_check(counts == PackedInt32Array([6, 3, 1]), "Ten sites finish at 6:3:1.")
			if total == 34:
				_check(counts == PackedInt32Array([20, 10, 4]), "Capped overflow keeps 2:1.")
			if total <= 28:
				for species: int in range(3):
					_check(
						absf(counts[species] - float(total) * [4.0, 2.0, 1.0][species] / 7.0) < 1.0,
						"Each intermediate count stays within one nest of its target."
					)
	_check(run.get_drill_nest_count() == 4, "Natural discovery reaches the drill cap.")
	run.free()


func _check_species_limits_and_retry() -> void:
	var run: PrototypeRun = _create_run()
	# Automation does not release a site or remove it from the proportion.
	for nest: NestState in run.nests:
		nest.is_tamed = true
	_check(run._choose_spawn_species() == NestState.Species.MUCUS, "Opening counts toward quota.")
	run._pending_nest_species = run._choose_spawn_species()
	_check(not run.resolve_nest_spawn(Vector2.ZERO, false), "Failed site is rejected.")
	_check(run.nests.size() == 2, "A failed placement consumes no quota.")
	_place_proportional_nest(run)
	_check(run._choose_spawn_species() == NestState.Species.DRILL, "The next deficit is drill.")
	run._pending_nest_species = run._choose_spawn_species()
	_check(not run.resolve_nest_spawn(Vector2.ZERO, false), "Failed drill site is rejected.")
	_check(run._choose_spawn_species() == NestState.Species.DRILL, "Failed drill stays due.")
	for disable_by_cap: bool in [true, false]:
		run.settings.drill_nest_limit = 0 if disable_by_cap else 4
		run.settings.drill_discovery_weight = 0.5 if disable_by_cap else 0.0
		run.start_run(_positions())
		while run.nests.size() < 12:
			_place_proportional_nest(run)
		_check(_species_counts(run) == PackedInt32Array([8, 4, 0]), "Disabled drill keeps 2:1.")
	run.settings.drill_nest_limit = 4
	run.settings.drill_discovery_weight = 0.5
	run.start_run(_positions())
	_check(_species_counts(run) == PackedInt32Array([2, 0, 0]), "Restart clears quota history.")
	# Resource weights continue to control the requested proportions.
	run.settings.unlocked_species_weights = PackedFloat32Array([1.0, 1.0])
	run.settings.drill_discovery_weight = 1.0
	while run.nests.size() < 9:
		_place_proportional_nest(run)
	_check(_species_counts(run) == PackedInt32Array([3, 3, 3]), "Custom weights are respected.")
	run.free()


func _place_proportional_nest(run: PrototypeRun) -> void:
	run._pending_nest_species = run._choose_spawn_species()
	_check(
		run.resolve_nest_spawn(Vector2(run.nests.size() * 100.0, 300.0)),
		"Proportional choice resolves through normal placement."
	)


func _species_counts(run: PrototypeRun) -> PackedInt32Array:
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0])
	for nest: NestState in run.nests:
		counts[nest.species] += 1
	return counts
