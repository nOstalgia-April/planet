extends SceneTree

# Run without --headless. --fixed-fps 60 makes gameplay progression reproducible;
# reported frame times still come from wall-clock render completion timestamps.
# User arguments: --large (2560x1600), --capture, --label=before, --phase=near_capture.
const DemoScript = preload("res://scripts/disk_demo.gd")
const BenchmarkDemoScript = preload("res://tests/rendered_benchmark_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const MucusField = preload("res://scripts/mucus_field.gd")
const NEST_COUNT: int = 21
const ACTORS_PER_NEST: int = 10
const WARMUP_FRAMES: int = 60
const SAMPLE_FRAMES: int = 180
const PHASES: Array[String] = ["near_idle", "near_rotating", "overview", "near_capture"]

var _demo: BenchmarkDemoScript
var _capture: bool = false
var _label: String = "run"
var _resolution: Vector2i = Vector2i(1920, 1080)
var _phase_filter: String = ""
var _failed: bool = false


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--large":
			_resolution = Vector2i(2560, 1600)
		elif argument == "--capture":
			_capture = true
		elif argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=").validate_filename()
		elif argument.begins_with("--phase="):
			_phase_filter = argument.trim_prefix("--phase=")
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This benchmark requires rendering; omit --headless.")
		quit(2)
		return
	if not _phase_filter.is_empty() and _phase_filter not in PHASES:
		push_error("Unknown benchmark phase: " + _phase_filter)
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = _resolution
	root.title = "Planet rendered performance benchmark"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print(
		"RENDER_BENCH_BEGIN resolution=%s warmup=%d samples=%d driver=%s"
		% [
			_resolution,
			WARMUP_FRAMES,
			SAMPLE_FRAMES,
			RenderingServer.get_current_rendering_driver_name()
		]
	)
	for phase: String in PHASES:
		if not _phase_filter.is_empty() and phase != _phase_filter:
			continue
		await _prepare_phase(phase)
		await _measure_phase(phase)
		current_scene = null
		_demo.queue_free()
		await process_frame
	print(
		"NOTE: frame_ms measures rendered wall time; process_ms is a periodically updated engine monitor and may include earlier phases."
	)
	quit(1 if _failed else 0)


func _prepare_phase(phase: String) -> void:
	seed(601026)
	var scene_demo: DemoScript = DemoScene.instantiate() as DemoScript
	var slime_scene: PackedScene = scene_demo.slime_scene
	var nest_scene: PackedScene = scene_demo.nest_scene
	var collection_scene: PackedScene = scene_demo.collection_scene
	var net_result_seconds: float = scene_demo.net_result_seconds
	scene_demo.set_script(BenchmarkDemoScript)
	_demo = scene_demo as BenchmarkDemoScript
	_demo.slime_scene = slime_scene
	_demo.nest_scene = nest_scene
	_demo.collection_scene = collection_scene
	_demo.net_result_seconds = net_result_seconds
	var run: PrototypeRun = _demo.get_node("Run") as PrototypeRun
	run.settings = run.settings.duplicate() as PrototypeSettings
	# Keep the population stable outside the explicit capture phase, while normal
	# nest, hover, capture, roaming, mucus and presentation callbacks remain active.
	run.settings.nest_roll_interval = 1000000.0
	run.settings.spawn_intervals = PackedFloat32Array([1000000.0, 1000000.0, 1000000.0])
	root.add_child(_demo)
	current_scene = _demo
	run._random.seed = 601026
	_demo._site_random.seed = 601027
	run.net_unlocked = true
	run.net_level = 2
	run.pipe_level = 3
	for index: int in range(2, NEST_COUNT):
		var offset: float = 0.60 + float(index - 2) * (TAU - 1.20) / 18.0
		var species: NestState.Species = (
			NestState.Species.MUCUS if index % 3 == 2 else NestState.Species.SLIME
		)
		run._add_nest(species, _demo._planet.get_nest_position(-PI * 0.5 + offset))
	for nest: NestState in run.nests:
		for local_index: int in range(ACTORS_PER_NEST):
			nest.alive_slimes += 1
			_demo._on_slime_requested(nest.nest_id)
			_seed_actor(_demo._slimes.back(), (nest.nest_id - 1) * ACTORS_PER_NEST + local_index)
		run.nest_changed.emit(nest)
	for actor: PrototypeSlime in _demo._slimes:
		if actor.species == PrototypeSlime.Species.MUCUS:
			_seed_trail(actor)
	_demo._refresh_hud()
	_demo._refresh_overview()
	assert(_demo._slimes.size() == 210)
	assert(_demo._mucus_trails.size() == 70)
	if phase == "overview":
		_demo._view.zoom_steps(-1.0, false)
	elif phase == "near_rotating":
		_demo._view.begin_drag(Vector2.ZERO)
	for frame: int in range(WARMUP_FRAMES):
		await process_frame
		_drive_phase(phase, frame)
		await RenderingServer.frame_post_draw


func _seed_actor(actor: PrototypeSlime, index: int) -> void:
	actor._rng.seed = 601100 + index
	actor._phase = actor._rng.randf_range(0.0, TAU)
	actor._elapsed = 0.0
	actor._launch_elapsed = actor.launch_seconds
	actor._wander_wait = actor._rng.randf_range(0.0, 0.6)
	actor._speed_variation = actor._rng.randf_range(0.8, 1.2)
	var angle: float = actor._home.angle() + actor._rng.randf_range(-0.36, 0.36)
	var bounds: Vector2 = _demo._planet.get_activity_radius_bounds(angle)
	actor.position = (
		Vector2.from_angle(angle) * lerpf(bounds.x, bounds.y, actor._rng.randf_range(0.25, 0.85))
	)
	actor._wander_target = actor._random_destination()
	actor._update_surface_rotation()


func _seed_trail(actor: PrototypeSlime) -> void:
	var end_point: Vector2 = actor.position
	var radius: float = end_point.length()
	actor.position = Vector2.from_angle(end_point.angle() - 60.0 / radius) * radius
	var trail: MucusField = _demo._start_mucus_trail(actor)
	for sample: int in range(1, 25):
		trail.advance(0.1, false)
		trail.append_ground_point(
			Vector2.from_angle(end_point.angle() - (60.0 - float(sample) * 2.5) / radius)
			* radius,
			false
		)
	actor.position = end_point
	trail.refresh_surface()


func _drive_phase(phase: String, frame: int) -> void:
	_demo._window_has_focus = true
	var pointer: Vector2 = Vector2(24.0, 260.0)
	if phase == "near_rotating":
		_demo._view.drag_to(Vector2(float(frame + 1) * 6.0, 0.0))
	elif phase == "near_capture":
		for actor: PrototypeSlime in _demo._slimes:
			var target: Vector2 = actor.get_capture_point()
			var candidate: Vector2 = (
				_demo._world.get_global_transform_with_canvas() * target
			)
			if (
				not actor.consumed
				and _demo._can_collect(target, _demo.run.get_pipe_radius())
				and not _is_over_nest(candidate)
			):
				pointer = candidate
				break
	_demo.benchmark_pointer = pointer


func _is_over_nest(pointer: Vector2) -> bool:
	for nest: NestView in _demo._nest_views:
		if nest.contains_viewport_point(pointer):
			return true
	return false


func _measure_phase(phase: String) -> void:
	var frame_times: Array[float] = []
	var process_times: Array[float] = []
	var draw_calls: Array[float] = []
	var simulation_deltas: Array[float] = []
	var actor_start: int = _demo._slimes.size()
	var trail_min: int = _demo._mucus_trails.size()
	var trail_max: int = trail_min
	var previous: int = Time.get_ticks_usec()
	for frame: int in range(SAMPLE_FRAMES):
		await process_frame
		_drive_phase(phase, WARMUP_FRAMES + frame)
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		frame_times.append(float(now - previous) / 1000.0)
		previous = now
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		simulation_deltas.append(_demo.observed_process_delta * 1000.0)
		trail_min = mini(trail_min, _demo._mucus_trails.size())
		trail_max = maxi(trail_max, _demo._mucus_trails.size())
	frame_times.sort()
	process_times.sort()
	draw_calls.sort()
	simulation_deltas.sort()
	print(
		"RENDER_BENCH_RESULT "
		+ JSON.stringify(
			{
				"label": _label,
				"phase": phase,
				"resolution": "%dx%d" % [_resolution.x, _resolution.y],
				"window_size": str(root.size),
				"viewport_size": str(root.get_visible_rect().size),
				"samples": SAMPLE_FRAMES,
				"frame_median_ms": _percentile(frame_times, 0.5),
				"frame_p95_ms": _percentile(frame_times, 0.95),
				"process_median_ms": _percentile(process_times, 0.5),
				"process_p95_ms": _percentile(process_times, 0.95),
				"simulation_delta_min_ms": simulation_deltas[0],
				"simulation_delta_median_ms": _percentile(simulation_deltas, 0.5),
				"simulation_delta_max_ms": simulation_deltas[-1],
				"fixed_step_60hz": (
					is_equal_approx(simulation_deltas[0], 1000.0 / 60.0)
					and is_equal_approx(simulation_deltas[-1], 1000.0 / 60.0)
				),
				"draw_calls_min": draw_calls[0],
				"draw_calls_median": _percentile(draw_calls, 0.5),
				"actors_start": actor_start,
				"actors_end": _demo._slimes.size(),
				"captured_during_samples": actor_start - _demo._slimes.size(),
				"captured_total": NEST_COUNT * ACTORS_PER_NEST - _demo._slimes.size(),
				"trails_min": trail_min,
				"trails_max": trail_max,
				"nests": _demo.run.nests.size(),
			}
		)
	)
	if phase == "near_capture" and _demo._slimes.size() >= actor_start:
		push_error("The capture phase did not collect an actor during sampling.")
		_failed = true
	if _capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
		var path: String = "res://artifacts/rendered_%s_%dx%d_%s.png" % [
			_label, _resolution.x, _resolution.y, phase
		]
		var result: Error = root.get_texture().get_image().save_png(path)
		assert(result == OK, "Could not save benchmark screenshot: " + path)
		print("RENDER_BENCH_CAPTURE " + ProjectSettings.globalize_path(path))


func _percentile(sorted_values: Array[float], fraction: float) -> float:
	var index: int = ceili(float(sorted_values.size()) * fraction) - 1
	return sorted_values[clampi(index, 0, sorted_values.size() - 1)]
