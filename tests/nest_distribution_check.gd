extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const SlimeScene: PackedScene = preload("res://scenes/world/slime.tscn")
const POPULATION: int = 300
const STEP_SECONDS: float = 0.1
const WARMUP_SECONDS: float = 60.0
const SAMPLE_SECONDS: float = 60.0
const SAMPLE_EVERY_STEPS: int = 5

var _failures: int = 0
var _demo: DemoScript
var _surface: PlanetSurface


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	_demo = DemoScene.instantiate() as DemoScript
	root.add_child(_demo)
	current_scene = _demo
	await process_frame
	_demo.set_process(false)
	_demo._view.set_process(false)
	_surface = _demo._planet
	_check_demo_injection()
	_check_population(Vector2(1920.0, 1080.0), -PI / 2.0, 7)
	_check_view_switch()
	_check_population(Vector2(1920.0, 1080.0), PI - 0.12, 11)
	_check_view_switch()
	_check_population(Vector2(1280.0, 800.0), -PI / 2.0, 19)
	_clear_population()
	_demo.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: nest-centered 2D density, full-crust coverage, wrap, source and view preservation."
		)
	quit(0 if _failures == 0 else 1)


func _check_demo_injection() -> void:
	_demo.run.advance(
		_demo.run.settings.spawn_intervals[0] + _demo.run.settings.spawn_interval_jitter
	)
	_check(
		not _demo._slimes.is_empty(),
		"The real run creates a population to check screen-width injection."
	)
	var expected_deviation: float = clampf(
		(
			_demo._view.get_near_screen_half_angle(_get_near_activity_radius())
			/ PrototypeSlime.NORMAL_CENTRAL_75_Z
		),
		0.35,
		0.9
	)
	var spawn_widths_match: bool = true
	for slime: PrototypeSlime in _demo._slimes:
		slime.set_process(false)
		spawn_widths_match = (
			spawn_widths_match and is_equal_approx(slime._roaming_deviation, expected_deviation)
		)
	_check(spawn_widths_match, "Actual demo spawning injects its configured P1 screen width.")
	var original_radius: float = _demo._view.near_radius_ratio
	_demo._view.near_radius_ratio = original_radius + 0.15
	_demo._apply_layout()
	expected_deviation = clampf(
		(
			_demo._view.get_near_screen_half_angle(_get_near_activity_radius())
			/ PrototypeSlime.NORMAL_CENTRAL_75_Z
		),
		0.35,
		0.9
	)
	var resized_widths_match: bool = true
	for slime: PrototypeSlime in _demo._slimes:
		resized_widths_match = (
			resized_widths_match and is_equal_approx(slime._roaming_deviation, expected_deviation)
		)
	_check(resized_widths_match, "Reapplying the demo layout updates existing actors' P1 width.")
	_demo._view.near_radius_ratio = original_radius
	_demo._apply_layout()
	_clear_population()


func _check_population(viewport_size: Vector2, home_angle: float, source_id: int) -> void:
	_clear_population()
	_demo._view.zoom_steps(1.0, false)
	_demo._world.rotation = -PI / 2.0 - home_angle
	var play_rect: Rect2 = _demo._layout.apply_layout(viewport_size)
	_demo._view.configure(play_rect, _surface.radius)
	var home: Vector2 = _surface.get_nest_position(home_angle)
	var half_angle: float = _demo._view.get_near_screen_half_angle(_get_near_activity_radius())
	var deviation: float = clampf(half_angle / PrototypeSlime.NORMAL_CENTRAL_75_Z, 0.35, 0.9)
	var screen: Rect2 = Rect2(Vector2.ZERO, viewport_size)
	var projection: Transform2D = _demo._slime_root.get_global_transform_with_canvas()
	_check(
		absf((projection * home).x - viewport_size.x * 0.5) < 0.01,
		"The measured nest is centered at the P1 arc crest."
	)
	for index: int in range(POPULATION):
		var slime: PrototypeSlime = SlimeScene.instantiate() as PrototypeSlime
		_demo._slime_root.add_child(slime)
		slime.setup(source_id, home, _surface, half_angle)
		slime._rng.seed = 98171 + source_id * 1009 + index * 7919
		slime._speed_variation = slime._rng.randf_range(0.8, 1.2)
		slime.launch(Vector2.from_angle(home_angle + float(index) * 2.399963))
		slime.set_process(false)
		_demo._slimes.append(slime)
	var measurements: int = 0
	var on_screen: int = 0
	var positive_offsets: int = 0
	var negative_offsets: int = 0
	var inner_band: int = 0
	var middle_band: int = 0
	var outer_band: int = 0
	var tail_band: int = 0
	var positive_world_angles: int = 0
	var negative_world_angles: int = 0
	var offset_sum: float = 0.0
	var offset_squared_sum: float = 0.0
	var all_on_surface: bool = true
	var largest_launch_overflow: float = 0.0
	var largest_roaming_overflow: float = 0.0
	var minimum_depth: float = 1.0
	var maximum_depth: float = 0.0
	var all_sources_preserved: bool = true
	var warmup_steps: int = roundi(WARMUP_SECONDS / STEP_SECONDS)
	var total_steps: int = warmup_steps + roundi(SAMPLE_SECONDS / STEP_SECONDS)
	for step_index: int in range(total_steps):
		for slime: PrototypeSlime in _demo._slimes:
			var launching: bool = slime._launch_elapsed < slime.launch_seconds
			slime._process(STEP_SECONDS)
			var bounds: Vector2 = _surface.get_activity_radius_bounds(slime.position.angle())
			var radius: float = slime.position.length()
			var depth: float = (radius - bounds.x) / (bounds.y - bounds.x)
			minimum_depth = minf(minimum_depth, depth)
			maximum_depth = maxf(maximum_depth, depth)
			var overflow: float = maxf(maxf(bounds.x - radius, radius - bounds.y), 0.0)
			if launching:
				largest_launch_overflow = maxf(largest_launch_overflow, overflow)
			else:
				largest_roaming_overflow = maxf(largest_roaming_overflow, overflow)
			all_on_surface = (
				all_on_surface and radius >= bounds.x - 0.001 and radius <= bounds.y + 0.001
			)
			all_sources_preserved = all_sources_preserved and slime.nest_id == source_id
		if step_index < warmup_steps or (step_index - warmup_steps) % SAMPLE_EVERY_STEPS != 0:
			continue
		for slime: PrototypeSlime in _demo._slimes:
			measurements += 1
			if screen.has_point(projection * slime.position):
				on_screen += 1
			var offset: float = angle_difference(home_angle, slime.position.angle())
			offset_sum += offset
			offset_squared_sum += offset * offset
			if offset > 0.0:
				positive_offsets += 1
			elif offset < 0.0:
				negative_offsets += 1
			if slime.position.angle() > 0.0:
				positive_world_angles += 1
			else:
				negative_world_angles += 1
			var normalized_offset: float = absf(offset) / deviation
			if normalized_offset < 1.0:
				inner_band += 1
			elif normalized_offset < 2.0:
				middle_band += 1
			elif normalized_offset < 3.0:
				outer_band += 1
			else:
				tail_band += 1
	var sample_count: float = float(measurements)
	var screen_fraction: float = float(on_screen) / sample_count
	var mean_offset: float = offset_sum / sample_count
	var measured_deviation: float = sqrt(
		offset_squared_sum / sample_count - mean_offset * mean_offset
	)
	var central_fraction: float = float(inner_band) / sample_count
	var outer_fraction: float = float(outer_band + tail_band) / sample_count
	var side_difference: float = float(abs(positive_offsets - negative_offsets)) / sample_count
	var label: String = (
		"%dx%d, nest %.3f rad" % [int(viewport_size.x), int(viewport_size.y), home_angle]
	)
	print(
		(
			"Nest distribution [%s]: screen %.2f%%, mean %.4f rad, sigma %.4f / %.4f, within 1 sigma %.2f%%, beyond 2 sigma %.2f%%, sides %.2f%% apart (%d samples)."
			% [
				label,
				screen_fraction * 100.0,
				mean_offset,
				measured_deviation,
				deviation,
				central_fraction * 100.0,
				outer_fraction * 100.0,
				side_difference * 100.0,
				measurements
			]
		)
	)
	print(
		(
			"Crust overflow [%s]: launch %.6f, roaming %.6f world units."
			% [label, largest_launch_overflow, largest_roaming_overflow]
		)
	)
	# P1 now crops an isotropically enlarged planet; camera framing no longer
	# defines the population's Gaussian width. Keep screen coverage diagnostic.
	_check(on_screen > 0 and on_screen < measurements, label + ": P1 shows part of the population.")
	_check(
		side_difference < 0.10 and absf(mean_offset) < deviation * 0.15,
		label + ": long-term density is centered and symmetric around the nest."
	)
	_check(
		inner_band > middle_band and middle_band > outer_band,
		label + ": density decreases from the nest toward equally wide outer bands."
	)
	_check(
		central_fraction > 0.60 and outer_fraction > 0.0 and outer_fraction < 0.09,
		label + ": the 2D cluster keeps a dense core and a sparse roaming tail."
	)
	# Destinations are sampled in 2D and constrained to the crust. Their angular
	# occupancy need not have the sigma of the retired one-dimensional model.
	_check(
		minimum_depth < 0.15 and maximum_depth > 0.85,
		label + ": roaming reaches both the inner and outer parts of the crust."
	)
	_check(
		all_on_surface, label + ": every simulated step remains inside the actual irregular crust."
	)
	_check(
		all_sources_preserved, label + ": roaming preserves every monster's source nest identifier."
	)
	if home_angle > PI - 0.2:
		_check(
			positive_world_angles > measurements / 4 and negative_world_angles > measurements / 4,
			"The seam-centered population walks on both sides of the world angle wrap."
		)


func _check_view_switch() -> void:
	var original_angles: Array[float] = []
	var original_deviations: Array[float] = []
	var original_sources: Array[int] = []
	for slime: PrototypeSlime in _demo._slimes:
		original_angles.append(slime.position.angle())
		original_deviations.append(slime._roaming_deviation)
		original_sources.append(slime.nest_id)
	var half_angle: float = _demo._view.get_near_screen_half_angle(_get_near_activity_radius())
	_demo._view.zoom_steps(-1.0, false)
	_check(_demo._view.is_overview(), "The real demo view switches to P2.")
	_check(
		is_equal_approx(
			_demo._view.get_near_screen_half_angle(_get_near_activity_radius()), half_angle
		),
		"The P1 screen metric stays unchanged while viewing P2."
	)
	_check_preserved_population(original_angles, original_deviations, original_sources, "P2")
	_demo._view.zoom_steps(1.0, false)
	_check_preserved_population(original_angles, original_deviations, original_sources, "P1 return")


func _check_preserved_population(
	angles: Array[float], deviations: Array[float], sources: Array[int], label: String
) -> void:
	var preserved: bool = true
	for index: int in range(_demo._slimes.size()):
		var slime: PrototypeSlime = _demo._slimes[index]
		var bounds: Vector2 = _surface.get_activity_radius_bounds(slime.position.angle())
		preserved = (
			preserved
			and absf(angle_difference(angles[index], slime.position.angle())) < 0.00001
			and is_equal_approx(slime._roaming_deviation, deviations[index])
			and slime.nest_id == sources[index]
			and slime.position.length() >= bounds.x - 0.001
			and slime.position.length() <= bounds.y + 0.001
		)
	_check(
		preserved,
		(
			label
			+ " preserves nest source, angular distribution and P1 width while reprojecting onto its crust."
		)
	)


func _get_near_activity_radius() -> float:
	var bounds: Vector2 = _surface.get_activity_radius_bounds(-PI / 2.0)
	return (bounds.x + bounds.y) * 0.5


func _clear_population() -> void:
	for slime: PrototypeSlime in _demo._slimes:
		slime.free()
	_demo._slimes.clear()
	_demo._capture_targets.clear()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
