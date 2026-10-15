extends "res://tests/nest_discovery_check.gd"


func _run() -> void:
	_game = PLAY.instantiate() as Play
	add_child(_game)
	for node: Node in [
		_game, _game._view, _game._population_palette, _game._nest_discovery, _game._restoration
	]:
		node.set_process(false)
	_game.run.settings = _game.run.settings.duplicate() as PrototypeSettings
	_game.run.settings.nest_initial_delay_seconds = 0.0
	_game.run.settings.nest_spawn_cooldown_seconds = 0.0
	_game.run.settings.nest_roll_chance_min = 1.0
	_game.run.settings.nest_roll_chance_max = 1.0
	var outcomes: Dictionary[Vector3i, bool] = {}
	for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_window().size = dimensions
		_game._apply_layout()
		for seed_index: int in range(12):
			_game.restart_run()
			_game._site_random.seed = seed_index + 5300
			_game.run._random.seed = seed_index
			_game.run.net_unlocked = true
			for attempt: int in range(12):
				_game.run._advance_nest_roll(_game.run.settings.nest_roll_interval)
				_until(Discovery.Phase.IDLE)
			var counts: PackedInt32Array = PackedInt32Array([0, 0, 0])
			for nest: NestState in _game.run.nests:
				counts[nest.species] += 1
			_check(_game.run.nests.size() == 10, "Real map fills all ten sites.")
			_check(counts[0] >= 4 and counts[1] >= 2 and counts[2] >= 1, "Real map meets minima.")
			_check(counts[2] <= 4, "Real map respects drill cap.")
			outcomes[Vector3i(counts[0], counts[1], counts[2])] = true
			_check(_game.run._pending_nest_species == -1, "Full planet clears failed requests.")
			for first: NestState in _game.run.nests:
				for second: NestState in _game.run.nests:
					if first.nest_id < second.nest_id:
						_check(
							(
								first.position.distance_to(second.position)
								>= _game._nest_site_distance
							),
							"Proportional discovery preserves full-growth spacing."
						)
			await get_tree().process_frame
	_check(outcomes.size() > 1, "Real map preserves random variation.")
	print("Real-scene compositions: ", outcomes.keys())
	_game.queue_free()
	await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("PASS: 24 real-scene runs, two resolutions, minima/randomness, discovery and spacing")
	get_tree().quit(0 if _failures.is_empty() else 1)
