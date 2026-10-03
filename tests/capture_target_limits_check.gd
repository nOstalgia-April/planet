extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const CLUSTER_SIZE: int = 7
const TARGET: Vector2 = Vector2(0.0, -235.0)

var _failures: int = 0


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	await process_frame
	_check_nearest_and_attraction(demo)
	_check_overlapping_targets(demo)
	_check_serial_timing(demo)
	_check_independent_technology(demo)
	_check_outside_range(demo)
	for child: Node in demo.get_node("Audio").get_children():
		(child as AudioStreamPlayer).stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: nearest-only pipe, visual-only neighbors, serial timing, fixed radius and independent technology."
		)
	quit(0 if _failures == 0 else 1)


func _check_nearest_and_attraction(demo: DemoScript) -> void:
	var cluster: Array[PrototypeSlime] = _prepare(demo)
	for index: int in range(CLUSTER_SIZE):
		_place_body(cluster[index], TARGET + Vector2(4.0 + float(index) * 8.0, 0.0))
	var neighbor_foot: Vector2 = cluster[1].position
	var neighbor_body: Vector2 = cluster[1].get_capture_point()
	demo._capture_at(0.05, TARGET, true)
	_check(
		_progressing(cluster) == 1 and cluster[0].capture_progress > 0.0,
		"Only the nearest body receives real pipe progress."
	)
	_check(
		(
			cluster[1]._attraction_offset.length() > 0.0
			and cluster[1].position == neighbor_foot
			and cluster[1].get_capture_point().is_equal_approx(neighbor_body)
			and is_zero_approx(cluster[1].capture_progress)
			and not cluster[1].consumed
		),
		"A nearby body visibly pulls without moving its feet, logical hit point or collection state."
	)
	var pulled: int = 0
	for actor: PrototypeSlime in cluster:
		if actor._attraction_offset.length() > 0.0:
			pulled += 1
	_check(pulled > 0 and pulled <= 4, "At most four nearby actors receive visual attraction.")
	_check(
		demo.run.pending_slime_count == 0 and demo.run.candy == 0,
		"Nearby attraction alone creates neither pending collection nor wallet income."
	)
	demo._capture_at(0.05, cluster[2].get_capture_point(), true)
	_check(
		(
			_progressing(cluster) == 1
			and cluster[2].capture_progress > 0.0
			and is_zero_approx(cluster[0].capture_progress)
		),
		"Changing the nearest target immediately clears progress on the old selection."
	)
	var progress: float = cluster[2].capture_progress
	demo._capture_at(0.01, TARGET, false)
	_check(
		cluster[2].capture_progress < progress and demo.run.pending_slime_count == 0,
		"Releasing a partial capture decays its progress without collecting it."
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
			demo.run.pending_slime_count == 1
			and demo.run.candy == 0
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
		demo.run.pending_slime_count == 2 and demo.run.candy == 0,
		"The next call processes the next single body while preserving the unpaid batch."
	)


func _check_serial_timing(demo: DemoScript) -> void:
	for pipe_level: int in range(4):
		var cluster: Array[PrototypeSlime] = _prepare(demo, pipe_level)
		for actor: PrototypeSlime in cluster:
			_place_body(actor, TARGET)
		var delta: float = 1.0 / 60.0
		var elapsed: float = 0.0
		var seconds: float = demo.run.get_pipe_capture_seconds()
		var deadline: float = float(cluster.size()) * (seconds + delta * 2.0)
		while demo.run.pending_slime_count < cluster.size() and elapsed < deadline:
			var before: int = demo.run.pending_slime_count
			demo._capture_at(delta, TARGET, true)
			elapsed += delta
			_check(
				demo.run.pending_slime_count - before <= 1,
				"Each frame advances at most one completed pipe collection."
			)
		_check(
			(
				demo.run.pending_slime_count == cluster.size()
				and elapsed + 0.001 >= float(cluster.size()) * seconds
				and elapsed <= deadline + delta
			),
			"Level %d captures seven bodies serially in %.3f seconds." % [pipe_level, elapsed]
		)
		_check(demo.run.candy == 0, "Continuous pipe input keeps every completed body unpaid.")
		print("Pipe level %d: seven bodies in %.3f seconds." % [pipe_level, elapsed])


func _check_independent_technology(demo: DemoScript) -> void:
	var cluster: Array[PrototypeSlime] = _prepare(demo)
	var expected_seconds: Array[float] = [0.6, 0.45, 0.32, 0.22]
	_check(
		(
			is_equal_approx(demo.run.get_pipe_radius(), 24.0)
			and is_equal_approx(demo.run.get_net_radius(), 84.0)
		),
		"Pipe and net start with their fixed independent radii."
	)
	var initial_capacity: int = demo.run.get_net_capacity()
	var cooldown: float = demo.run.settings.net_cooldown_seconds
	for level: int in range(4):
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
			is_zero_approx(cluster[0].capture_progress) and demo.run.pending_slime_count == 0,
			"Every pipe level excludes a body just outside the fixed radius."
		)
		if level < 3:
			_fund_pipe_upgrade(demo)
	var pipe_seconds: float = demo.run.get_pipe_capture_seconds()
	for level: int in range(3):
		demo.run.candy = demo.run.get_net_upgrade_cost()
		_check(demo.run.upgrade_net(), "The net upgrade uses its own legal purchase.")
		_check(
			(
				demo.run.pipe_level == 3
				and is_equal_approx(demo.run.get_pipe_capture_seconds(), pipe_seconds)
				and is_equal_approx(demo.run.get_pipe_radius(), 24.0)
				and is_equal_approx(demo.run.get_net_radius(), 84.0)
			),
			"Net technology changes capacity without changing either radius or pipe speed."
		)


func _check_outside_range(demo: DemoScript) -> void:
	var cluster: Array[PrototypeSlime] = _prepare(demo, 3)
	demo._capture_at(demo.run.get_pipe_capture_seconds(), TARGET, true)
	_check(
		demo.run.pending_slime_count == 0 and demo.run.candy == 0 and _progressing(cluster) == 0,
		"Maximum pipe technology never reaches actors outside the physical mouth radius."
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
		actor.set_process(false)
		_place_body(actor, TARGET + Vector2(150.0 + float(index) * 30.0, 0.0))
		if index < CLUSTER_SIZE:
			cluster.append(actor)
	return cluster


func _fund_pipe_upgrade(demo: DemoScript) -> void:
	# Funding isolates tool rules; the playthrough checks earned purchases.
	demo.run.candy = demo.run.get_pipe_upgrade_cost()
	_check(demo.run.upgrade_pipe(), "The pipe upgrade uses a legal purchase.")


func _place_body(actor: PrototypeSlime, point: Vector2) -> void:
	actor.position = point - point.normalized() * actor.body_size * 0.65
	actor.rotation = actor.position.angle() + PI / 2.0


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
