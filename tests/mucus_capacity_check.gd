extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const MucusField = preload("res://scripts/mucus_field.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	demo.run.settings = demo.run.settings.duplicate() as PrototypeSettings
	await process_frame
	var sources: Array[PrototypeSlime] = _prepare_sources(demo, 5, 3)
	_check_continuous_sources(demo, sources, "five sources above a three-history budget")
	await _check_detachment_and_history(demo, sources)
	sources = _prepare_sources(demo, 90, 80)
	_check_continuous_sources(demo, sources, "ninety sources above the default eighty-history budget")
	await process_frame
	_check(
		demo._mucus_root.get_child_count() == demo._nest_mucus_areas.size() + sources.size(),
		"high source pressure retains exactly one ribbon scene per live emitter"
	)
	for audio: Node in demo.get_node("Audio").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	if _failures.is_empty():
		print(
			"PASS: live mucus sources keep continuous ribbons above the history budget; detachment, capture, history eviction and expiry remain bounded."
		)
	else:
		for failure: String in _failures:
			push_error("FAIL: " + failure)
	quit(0 if _failures.is_empty() else 1)


func _prepare_sources(demo: DemoScript, count: int, history_limit: int) -> Array[PrototypeSlime]:
	var per_nest: int = mini(count, 10)
	demo.run.settings.nest_population_limits = PackedInt32Array([per_nest, 30, 60])
	demo.run.settings.mucus_trail_limit = history_limit
	demo.restart_run()
	demo._site_random.seed = 8192
	demo.run.candy = demo.run.settings.net_unlock_cost + demo.run.get_pipe_upgrade_cost()
	_check(demo.run.upgrade_pipe(), "speed level two enables net research")
	_check(demo.run.purchase_technology("net"), "unlocking the net opens the tool")
	for _index: int in range(ceili(float(count) / float(per_nest))):
		demo.run._pending_nest_species = NestState.Species.MUCUS
		demo._on_nest_spawn_requested(NestState.Species.MUCUS)
	for nest: NestState in demo.run.nests:
		if nest.species == NestState.Species.MUCUS:
			demo.run._advance_nest_population(
				nest, demo.run.get_nest_spawn_interval(nest.nest_id) * 20.0
			)
	var sources: Array[PrototypeSlime] = []
	for actor: PrototypeSlime in demo._slimes:
		actor._process(actor.launch_seconds)
		actor.set_process(false)
		if actor.species == PrototypeSlime.Species.MUCUS:
			sources.append(actor)
	_check(sources.size() == count, "the fixture reaches the requested live emitter count")
	_check_population(demo)
	_move_sources(demo, sources, 0)
	demo._advance_ground_mucus(0.0)
	return sources


func _check_continuous_sources(
	demo: DemoScript, sources: Array[PrototypeSlime], label: String
) -> void:
	var original_ids: Dictionary = {}
	for source: PrototypeSlime in sources:
		var actor_id: int = source.get_instance_id()
		var trail: MucusField = demo._active_mucus_trails.get(actor_id) as MucusField
		if trail != null:
			original_ids[actor_id] = trail.get_instance_id()
	_check(original_ids.size() == sources.size(), label + ": every emitter receives a ribbon")
	var stable: bool = true
	var bounded: bool = true
	for frame: int in range(1, 13):
		_move_sources(demo, sources, frame)
		demo._advance_ground_mucus(0.08)
		bounded = bounded and demo._mucus_trails.size() == sources.size()
		for source: PrototypeSlime in sources:
			var actor_id: int = source.get_instance_id()
			var trail: MucusField = demo._active_mucus_trails.get(actor_id) as MucusField
			if trail == null or trail.get_instance_id() != int(original_ids.get(actor_id, 0)):
				stable = false
	_check(stable, label + ": moving sources do not destroy and recreate each other's ribbons")
	_check(bounded, label + ": retained count stays at the live source count")
	var continuous: bool = true
	for source: PrototypeSlime in sources:
		var trail: MucusField = demo._active_mucus_trails.get(source.get_instance_id()) as MucusField
		if trail == null:
			continuous = false
			continue
		var points: PackedVector2Array = trail.get_ground_points()
		continuous = (
			continuous
			and points.size() >= 3
			and points[-1].distance_to(source.position) < 0.005
			and points[0].distance_to(points[-1]) > 10.0
		)
	_check(continuous, label + ": ribbons contain traveled paths instead of single-point stubs")


func _check_detachment_and_history(demo: DemoScript, sources: Array[PrototypeSlime]) -> void:
	if sources.size() != 5 or demo._active_mucus_trails.size() != 5:
		_check(false, "detachment checks require all five source ribbons to survive initial pressure")
		return
	var source_ids: Array[int] = []
	var original_trails: Array[MucusField] = []
	for source: PrototypeSlime in sources:
		source_ids.append(source.get_instance_id())
		original_trails.append(demo._active_mucus_trails[source.get_instance_id()] as MucusField)
	sources[0].detached_remaining = 6.0
	demo._advance_ground_mucus(0.0)
	_check(
		demo._active_mucus_trails.size() == 4
		and demo._mucus_trails.size() == 4
		and not demo._mucus_trails.has(original_trails[0]),
		"detaching above budget removes inactive history before any of the four live ribbons"
	)
	sources[1].detached_remaining = 6.0
	sources[2].detached_remaining = 6.0
	demo._advance_ground_mucus(0.0)
	_check(
		demo._active_mucus_trails.size() == 2
		and demo._mucus_trails.size() == 3
		and not demo._mucus_trails.has(original_trails[1])
		and demo._mucus_trails.has(original_trails[2]),
		"falling below budget preserves recent inactive history and retires the oldest first"
	)
	_check(
		demo._active_mucus_trails.get(source_ids[3]) == original_trails[3]
		and demo._active_mucus_trails.get(source_ids[4]) == original_trails[4],
		"detached-source cleanup preserves both remaining live ribbon instances"
	)
	var captured_point: Vector2 = original_trails[3].get_ground_points()[-2]
	_capture_actor(demo, sources[3])
	demo._advance_ground_mucus(0.0)
	_check(
		not demo._active_mucus_trails.has(source_ids[3])
		and demo._mucus_trails.has(original_trails[3])
		and original_trails[3].contains_ground_point(captured_point),
		"a captured emitter leaves usable history while the history budget has room"
	)
	_check_population(demo)
	var retained_source: PrototypeSlime = sources[4]
	var newest: MucusField = demo._start_mucus_trail(retained_source)
	_check(
		demo._mucus_trails.size() == 3
		and not demo._mucus_trails.has(original_trails[2])
		and demo._mucus_trails.has(original_trails[3])
		and demo._active_mucus_trails.get(source_ids[4]) == newest,
		"a restarted source evicts the oldest inactive history before the newer captured ribbon"
	)
	var historical_count_bounded: bool = true
	for frame: int in range(12):
		retained_source.position = _ground_point(demo, 0.1 + float(frame) * 0.03)
		newest = demo._start_mucus_trail(retained_source)
		newest.append_ground_point(_ground_point(demo, retained_source.position.angle() + 0.012))
		historical_count_bounded = historical_count_bounded and demo._mucus_trails.size() == 3
	_check(historical_count_bounded, "repeated source restarts cannot grow history past its budget")
	await process_frame
	_check(
		demo._mucus_root.get_child_count() == demo._nest_mucus_areas.size() + 3,
		"retired history nodes are freed after the frame"
	)
	retained_source.detached_remaining = 6.0
	demo._advance_ground_mucus(demo.run.settings.mucus_trail_lifetime + 0.1)
	await process_frame
	_check(
		demo._mucus_trails.is_empty()
		and demo._active_mucus_trails.is_empty()
		and demo._mucus_root.get_child_count() == demo._nest_mucus_areas.size(),
		"all stopped histories expire from bookkeeping and scene nodes while nest pools persist"
	)


func _move_sources(demo: DemoScript, sources: Array[PrototypeSlime], frame: int) -> void:
	for index: int in range(sources.size()):
		var angle: float = float(index) * TAU / float(sources.size()) + float(frame) * 0.012
		sources[index].position = _ground_point(demo, angle)


func _ground_point(demo: DemoScript, angle: float) -> Vector2:
	var bounds: Vector2 = demo._planet.get_activity_radius_bounds(angle)
	return Vector2.from_angle(angle) * lerpf(bounds.x, bounds.y, 0.5)


func _capture_actor(demo: DemoScript, actor: PrototypeSlime) -> void:
	demo._capture_at(0.0, actor.get_capture_point(), false)
	var neighbors: Array[PrototypeSlime] = []
	var positions: PackedVector2Array = PackedVector2Array()
	for neighbor: PrototypeSlime in demo._slimes:
		if neighbor != actor:
			neighbors.append(neighbor)
			positions.append(neighbor.position)
			neighbor.position = -actor.position
	demo._capture_at(
		demo._capture_seconds_for(actor) + actor.peel_seconds, actor.get_capture_point(), true
	)
	if demo._slimes.has(actor):
		demo._capture_at(demo._capture_seconds_for(actor), actor.get_capture_point(), true)
	_check(not demo._slimes.has(actor), "the real pipe captures the requested source")
	for index: int in range(neighbors.size()):
		neighbors[index].position = positions[index]


func _check_population(demo: DemoScript) -> void:
	for nest: NestState in demo.run.nests:
		var actual: int = 0
		for actor: PrototypeSlime in demo._slimes:
			if actor.nest_id == nest.nest_id:
				actual += 1
		_check(actual == nest.alive_slimes, "real source actors match their nest population ledger")


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
