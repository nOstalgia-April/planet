extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const CLUSTER_SIZE: int = 7
const TARGET: Vector2 = Vector2(0.0, -175.0)

var _failures: int = 0


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	await process_frame
	_check_nearest_only(demo)
	_check_overlapping_targets(demo)
	_check_serial_timing(demo)
	_check_independent_technology(demo)
	_check_outside_range(demo)
	for child: Node in demo.get_node("Audio").get_children():
		if child is AudioStreamPlayer:
			child.stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: no peripheral pulling, one stable center target, serial timing and independent technology."
		)
	quit(0 if _failures == 0 else 1)


func _check_nearest_only(demo: DemoScript) -> void:
	var cluster: Array[PrototypeSlime] = _prepare(demo)
	var original_points: Array[Vector2] = []
	for index: int in range(CLUSTER_SIZE):
		_place_body(cluster[index], TARGET + Vector2(4.0 + float(index) * 8.0, 0.0))
		original_points.append(cluster[index].get_capture_point())
	demo._capture_at(0.05, TARGET, true)
	_check(
		_progressing(cluster) == 1 and cluster[0].capture_progress > 0.0,
		"Only the nearest center body receives real pipe progress."
	)
	for index: int in range(1, CLUSTER_SIZE):
		_check(
			(
				(cluster[index].get_capture_point().is_equal_approx(original_points[index]))
				and is_zero_approx(cluster[index].capture_progress)
				and not cluster[index].consumed
			),
			"Unselected neighbors never move or progress from vacuum suction, even inside the center."
		)
	_check(demo.run.candy == 0, "Incomplete center processing creates no wallet income.")
	_place_body(cluster[1], TARGET)
	var progress: float = cluster[0].capture_progress
	demo._capture_at(0.05, TARGET, true)
	_check(
		cluster[0].capture_progress > progress and is_zero_approx(cluster[1].capture_progress),
		"A new closer arrival cannot interrupt the center actor being processed."
	)
	_place_body(cluster[2], TARGET + Vector2.RIGHT * 60.0)
	demo._capture_at(0.05, cluster[2].get_capture_point(), true)
	_check(
		(
			_progressing(cluster) == 1
			and cluster[2].capture_progress > 0.0
			and is_zero_approx(cluster[0].capture_progress)
		),
		"Moving the processing center away cancels the old selection."
	)
	demo._capture_at(0.01, TARGET, false)
	_check(
		_progressing(cluster) == 0 and demo.run.candy == 0,
		"Stopping clears incomplete captures without collecting them."
	)
	for actor: PrototypeSlime in cluster:
		var previous: Vector2 = actor.position
		actor._process(0.01)
		_check(
			actor.position.distance_to(previous) <= actor.wander_speed * 0.03,
			"Stopping capture cannot teleport an actor back to its old launch path."
		)


func _check_overlapping_targets(demo: DemoScript) -> void:
	var cluster: Array[PrototypeSlime] = _prepare(demo)
	for actor: PrototypeSlime in cluster:
		_place_body(actor, TARGET)
	var initial_population: int = demo._slimes.size()
	var seconds: float = demo.run.get_pipe_capture_seconds()
	demo._capture_at(seconds * 20.0, TARGET, true)
	_check(
		(
			demo.run.candy == demo.run.settings.slime_reward
			and demo._slimes.size() == initial_population - 1
		),
		"Even a huge delta can remove only one overlapping body in a single call."
	)
	var surviving_progress: int = 0
	for actor: PrototypeSlime in demo._slimes:
		if actor.capture_progress > 0.0:
			surviving_progress += 1
	_check(
		surviving_progress == 0,
		"Overlapping neighbors remain unprocessed after the selected body is removed."
	)
	demo._capture_at(seconds * 20.0, TARGET, true)
	_check(
		demo.run.candy == 2 * demo.run.settings.slime_reward,
		"The next call processes and pays the next single body while input stays held."
	)


func _check_serial_timing(demo: DemoScript) -> void:
	for pipe_level: int in range(demo.run.settings.pipe_capture_seconds.size()):
		var cluster: Array[PrototypeSlime] = _prepare(demo, pipe_level)
		for actor: PrototypeSlime in cluster:
			_place_body(actor, TARGET)
		var delta: float = 1.0 / 60.0
		var elapsed: float = 0.0
		var seconds: float = demo.run.get_pipe_capture_seconds()
		var deadline: float = float(cluster.size()) * (seconds + delta * 2.0)
		var reward: int = demo.run.settings.slime_reward
		while demo.run.candy < cluster.size() * reward and elapsed < deadline:
			var before: int = demo.run.candy
			demo._capture_at(delta, TARGET, true)
			elapsed += delta
			_check(
				demo.run.candy - before in [0, reward],
				"Each frame advances at most one completed pipe collection."
			)
		_check(
			(
				demo.run.candy == cluster.size() * reward
				and elapsed + 0.001 >= float(cluster.size()) * seconds
				and elapsed <= deadline + delta
			),
			"Level %d captures seven bodies serially in %.3f seconds." % [pipe_level, elapsed]
		)
		_check(
			demo.get_node("%Effects").get_child_count() == cluster.size(),
			"Continuous input creates one separate reward effect for every completed body."
		)
		print("Pipe level %d: seven bodies in %.3f seconds." % [pipe_level, elapsed])


func _check_independent_technology(demo: DemoScript) -> void:
	var cluster: Array[PrototypeSlime] = _prepare(demo)
	var expected_seconds: PackedFloat32Array = demo.run.settings.pipe_capture_seconds
	_check(
		(
			is_equal_approx(demo.run.get_pipe_radius(), 24.0)
			and is_equal_approx(demo.run.get_net_radius(), 84.0)
		),
		"Pipe and net start with their fixed independent radii."
	)
	var initial_capacity: int = demo.run.get_net_capacity()
	var cooldown: float = demo.run.settings.net_cooldown_seconds
	for level: int in range(expected_seconds.size()):
		_check(
			(
				is_equal_approx(demo.run.get_pipe_capture_seconds(), expected_seconds[level])
				and is_equal_approx(demo.run.get_pipe_radius(), 24.0)
				and demo.run.net_level == 0
				and demo.run.get_net_capacity() == initial_capacity
				and is_equal_approx(demo.run.settings.net_cooldown_seconds, cooldown)
			),
			"Pipe technology changes only serial capture speed."
		)
		_place_body(cluster[0], TARGET + Vector2.RIGHT * 25.0)
		demo._capture_at(0.1, TARGET, true)
		_check(
			is_zero_approx(cluster[0].capture_progress) and demo.run.candy == 0,
			"Every pipe level excludes a body just outside the fixed radius."
		)
		if level < expected_seconds.size() - 1:
			_fund_pipe_upgrade(demo)
	var pipe_seconds: float = demo.run.get_pipe_capture_seconds()
	demo.run.candy = demo.run.get_net_upgrade_cost()
	_check(
		demo.run.purchase_technology("net"), "The net must be unlocked before capacity upgrades."
	)
	for level: int in range(3):
		demo.run.candy = demo.run.get_net_upgrade_cost()
		_check(demo.run.upgrade_net(), "The net upgrade uses its own legal purchase.")
		_check(
			(
				demo.run.pipe_level == expected_seconds.size() - 1
				and is_equal_approx(demo.run.get_pipe_capture_seconds(), pipe_seconds)
				and is_equal_approx(demo.run.get_pipe_radius(), 24.0)
				and is_equal_approx(demo.run.get_net_radius(), 84.0)
			),
			"Net technology changes capacity without changing either radius or pipe speed."
		)


func _check_outside_range(demo: DemoScript) -> void:
	var cluster: Array[PrototypeSlime] = _prepare(demo, 6)
	var radius: float = demo.run.get_pipe_radius()
	_place_body(cluster[0], TARGET + Vector2.RIGHT * (radius + 0.01))
	_place_body(cluster[1], TARGET + Vector2.RIGHT * 69.0)
	var original_points: Array[Vector2] = [cluster[0].position, cluster[1].position]
	for frame: int in range(120):
		demo._capture_at(1.0 / 60.0, TARGET, true)
	_check(
		demo.run.candy == 0 and _progressing(cluster) == 0,
		"Actors just outside the center never accumulate capture progress or rewards."
	)
	for index: int in range(2):
		_check(
			cluster[index].position.is_equal_approx(original_points[index]),
			"The removed outer attraction zone never moves an actor toward the pipe."
		)
	_place_body(cluster[0], TARGET + Vector2.RIGHT * (radius - 0.01))
	demo._capture_at(demo.run.get_pipe_capture_seconds(), TARGET, true)
	_check(
		demo.run.candy == demo.run.settings.slime_reward,
		"Only an actor inside the center can be processed and rewarded."
	)


func _prepare(demo: DemoScript, pipe_level: int = 0) -> Array[PrototypeSlime]:
	demo.restart_run()
	for level: int in range(pipe_level):
		_fund_pipe_upgrade(demo)
	demo.run.advance(demo.run.settings.spawn_intervals[0] * 4.0)
	_check(
		demo._slimes.size() >= CLUSTER_SIZE,
		"Spawn signals provide real actors for the range checks."
	)
	var cluster: Array[PrototypeSlime] = []
	for index: int in range(demo._slimes.size()):
		var actor: PrototypeSlime = demo._slimes[index]
		actor._process(actor.launch_seconds)
		actor.set_process(false)
		_place_body(actor, TARGET + Vector2(150.0 + float(index) * 30.0, 0.0))
		if index < CLUSTER_SIZE:
			_check(
				(
					actor.species == PrototypeSlime.Species.SLIME
					and actor.reward == demo.run.settings.slime_reward
				),
				"The serial timing fixture contains only ordinary slimes with the base reward."
			)
			cluster.append(actor)
	return cluster


func _fund_pipe_upgrade(demo: DemoScript) -> void:
	# Funding isolates tool rules; the playthrough checks earned purchases.
	demo.run.candy = demo.run.get_pipe_upgrade_cost()
	_check(demo.run.upgrade_pipe(), "The pipe upgrade uses a legal purchase.")


func _place_body(actor: PrototypeSlime, point: Vector2) -> void:
	actor.position = point
	actor._update_surface_rotation()
	actor.position += point - actor.get_capture_point()


func _progressing(actors: Array[PrototypeSlime]) -> int:
	var count: int = 0
	for actor: PrototypeSlime in actors:
		if actor.capture_progress > 0.0:
			count += 1
	return count


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
