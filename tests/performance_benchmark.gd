extends SceneTree

# Fixed workloads expose CPU regressions without depending on progression or spawning.
# Run with --headless --path . --script res://tests/performance_benchmark.gd.
const MucusField = preload("res://scripts/mucus_field.gd")
const TrailScene: PackedScene = preload("res://scenes/effects/mucus_field.tscn")
const TRAIL_COUNT: int = 40
const ACTOR_COUNT: int = 120
const STEPS: int = 360
const STEP_SECONDS: float = 1.0 / 60.0

var _surface: PlanetSurface
var _trails: Array[MucusField] = []
var _actors: Array[PrototypeSlime] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_surface = PlanetSurface.new()
	root.add_child(_surface)
	_surface.set_near_view(true)
	for index: int in range(TRAIL_COUNT):
		var trail: MucusField = TrailScene.instantiate() as MucusField
		root.add_child(trail)
		trail.source_actor_id = index
		trail.configure(_surface, _point(index, 0.0), index, 7.0, 7.0, 72.0, 2.5)
		for sample: int in range(1, 30):
			trail.advance(0.05, false)
			trail.append_ground_point(_point(index, float(sample) * 2.0), false)
		trail.refresh_surface()
		_trails.append(trail)
	for index: int in range(ACTOR_COUNT):
		var actor: PrototypeSlime = PrototypeSlime.new()
		root.add_child(actor)
		actor.setup(index, _point(index, 0.0), _surface)
		actor._rng.seed = 1000 + index
		actor.set_process(false)
		_actors.append(actor)
	for iteration: int in range(3):
		_benchmark(iteration)
	for trail: MucusField in _trails:
		trail.free()
	for actor: PrototypeSlime in _actors:
		actor.free()
	_surface.free()
	print("NOTE: CPU work per simulated step; headless results are not rendered frame rates.")
	quit()


func _benchmark(iteration: int) -> void:
	var elapsed_us: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0])
	var step_costs: Array[int] = []
	var contact_count: int = 0
	for step: int in range(STEPS):
		var start: int = Time.get_ticks_usec()
		var stamp: int = start
		for trail: MucusField in _trails:
			trail.advance(STEP_SECONDS, false)
		elapsed_us[0] += Time.get_ticks_usec() - stamp
		stamp = Time.get_ticks_usec()
		var distance: float = 58.0 + float(iteration * STEPS + step + 1) * 0.25
		for index: int in range(TRAIL_COUNT):
			_trails[index].append_ground_point(_point(index, distance), false)
		elapsed_us[1] += Time.get_ticks_usec() - stamp
		stamp = Time.get_ticks_usec()
		for trail: MucusField in _trails:
			trail.refresh_surface(false)
		elapsed_us[2] += Time.get_ticks_usec() - stamp
		stamp = Time.get_ticks_usec()
		for index: int in range(ACTOR_COUNT):
			var point: Vector2 = _point(index % TRAIL_COUNT, distance - float(index % 12) * 2.0)
			for trail: MucusField in _trails:
				if trail.contains_ground_point(point):
					contact_count += 1
					break
		elapsed_us[3] += Time.get_ticks_usec() - stamp
		stamp = Time.get_ticks_usec()
		for actor: PrototypeSlime in _actors:
			actor._process(STEP_SECONDS)
		elapsed_us[4] += Time.get_ticks_usec() - stamp
		step_costs.append(Time.get_ticks_usec() - start)
	step_costs.sort()
	var average_ms: PackedFloat64Array = PackedFloat64Array()
	for elapsed: int in elapsed_us:
		average_ms.append(float(elapsed) / float(STEPS) / 1000.0)
	print(
		(
			"CPU_BENCH run=%d trails=%d actors=%d steps=%d "
			+ "advance_append_refresh_contact_actor_ms=%s "
			+ "median_step_ms=%.3f p95_step_ms=%.3f contacts=%d"
		)
		% [
			iteration,
			TRAIL_COUNT,
			ACTOR_COUNT,
			STEPS,
			average_ms,
			float(step_costs[STEPS / 2]) / 1000.0,
			float(step_costs[int(STEPS * 0.95)]) / 1000.0,
			contact_count
		]
	)


func _point(index: int, distance: float) -> Vector2:
	var angle: float = float(index) * TAU / float(TRAIL_COUNT) + distance / 220.0
	var bounds: Vector2 = _surface.get_activity_radius_bounds(angle)
	return Vector2.from_angle(angle) * lerpf(bounds.x, bounds.y, 0.45 + float(index % 3) * 0.05)
