extends SceneTree

const SlimeScene: PackedScene = preload("res://scenes/world/slime.tscn")
const NestScene: PackedScene = preload("res://scenes/world/nest.tscn")
const PLANET_RADIUS: float = 240.0
const HOME: Vector2 = Vector2(0.0, -PLANET_RADIUS)

var _failures: int = 0
var _flight_events: int = 0
var _last_flight_slime: PrototypeSlime
var _surface: PlanetSurface


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	_surface = PlanetSurface.new()
	_surface.radius = PLANET_RADIUS
	_surface.set_near_view(true)
	root.add_child(_surface)
	var slime: PrototypeSlime = SlimeScene.instantiate() as PrototypeSlime
	root.add_child(slime)
	slime.setup(7, HOME, _surface)
	slime.set_process(false)
	slime._rng.seed = 78143
	_check_active_nest_roaming(slime)
	_check_launch(slime)
	_check_edge_launch(slime)
	_check_full_contour_roaming(slime)
	_check_orphan_roaming(slime)
	_check_restoration(slime)
	_check_radial_orientation(slime)
	_check_attraction(slime)
	_check_flight(slime)
	slime.queue_free()
	_surface.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: nest-centered roaming, full crust and orphan reach, radial orientation, attraction, restoration and one-shot flight."
		)
	quit(0 if _failures == 0 else 1)


func _check_active_nest_roaming(slime: PrototypeSlime) -> void:
	var greatest_angle: float = 0.0
	var minimum_depth: float = INF
	var maximum_depth: float = 0.0
	var valid_surface: bool = true
	for _frame: int in range(12000):
		slime._process(1.0 / 30.0)
		var angle: float = absf(angle_difference(HOME.angle(), slime.position.angle()))
		greatest_angle = maxf(greatest_angle, angle)
		var depth: float = _get_surface_depth(slime.position)
		minimum_depth = minf(minimum_depth, depth)
		maximum_depth = maxf(maximum_depth, depth)
		valid_surface = valid_surface and _is_on_surface(slime)
	_check(valid_surface, "Active-nest wander stays between the actual irregular crust edges.")
	_check(
		greatest_angle > slime._roaming_deviation,
		"An active-nest monster explores the Gaussian outskirts of its local group."
	)
	_check(
		minimum_depth < 0.10 and maximum_depth > 0.90,
		"Active-nest roaming reaches the front and rear of the full visible crust."
	)
	print("Near-view roaming crust depth: %.3f to %.3f." % [minimum_depth, maximum_depth])


func _check_launch(slime: PrototypeSlime) -> void:
	var valid_surface: bool = true
	var shortest_launch: float = INF
	var longest_launch: float = 0.0
	for direction_index: int in range(16):
		slime.launch(Vector2.from_angle(float(direction_index) * TAU / 16.0))
		_check(
			slime.position.distance_to(HOME) < 0.001, "A launch starts at the nest ground point."
		)
		for _frame: int in range(12):
			slime._process(1.0 / 30.0)
			valid_surface = valid_surface and _is_on_surface(slime)
		var distance: float = slime.position.distance_to(HOME)
		shortest_launch = minf(shortest_launch, distance)
		longest_launch = maxf(longest_launch, distance)
		_check(
			is_equal_approx(slime._launch_elapsed, slime.launch_seconds),
			"The spawn bounce completes and lands within 0.4 seconds."
		)
	_check(valid_surface, "Every launch direction remains inside the surface ring.")
	_check(
		(
			shortest_launch > 0.0
			and longest_launch >= slime.launch_distance - 10.1
			and longest_launch <= slime.launch_distance + 10.1
		),
		"The full crust clips outward launches while preserving inward and tangential travel."
	)
	print("Scene launch displacement: %.3f to %.3f." % [shortest_launch, longest_launch])


func _check_edge_launch(slime: PrototypeSlime) -> void:
	var edge_home: Vector2 = _surface.get_nest_position(-PI / 2.0)
	slime.setup(7, edge_home, _surface)
	slime.set_process(false)
	slime.launch(Vector2.DOWN)
	slime.set_process(false)
	_check(
		slime.position.is_equal_approx(edge_home) and _faces_outward(slime),
		"An edge nest launches from its actual ground root before entering the roaming band."
	)
	slime._process(slime.launch_seconds)
	_check(
		_is_on_surface(slime) and _faces_outward(slime),
		"The edge launch finishes inside the full crust with outward orientation."
	)
	slime.setup(7, HOME, _surface)
	slime.set_process(false)


func _check_full_contour_roaming(slime: PrototypeSlime) -> void:
	for near_view: bool in [true, false]:
		_surface.set_near_view(near_view)
		slime.refresh_surface_bounds()
		var all_positions_on_crust: bool = true
		var closest_front: float = INF
		var closest_rear: float = 0.0
		for angle_index: int in range(48):
			var angle: float = float(angle_index) * TAU / 48.0
			var radial: Vector2 = Vector2.from_angle(angle)
			slime.restore_to_surface(radial * PLANET_RADIUS * 0.2)
			slime.set_process(false)
			closest_front = minf(closest_front, _get_surface_depth(slime.position))
			all_positions_on_crust = all_positions_on_crust and _is_on_surface(slime)
			slime.restore_to_surface(radial * PLANET_RADIUS * 2.0)
			slime.set_process(false)
			closest_rear = maxf(closest_rear, _get_surface_depth(slime.position))
			all_positions_on_crust = all_positions_on_crust and _is_on_surface(slime)
			# Cross an angular shelf while walking from the rear to the opposite front.
			var destination_angle: float = angle + 0.75
			slime._wander_target = (
				Vector2.from_angle(destination_angle)
				* (_surface.get_inner_radius(destination_angle) + 2.0)
			)
			slime._wander_wait = 100.0
			for _step: int in range(120):
				slime._move_on_surface(slime._wander_target, slime.wander_speed / 15.0)
				all_positions_on_crust = all_positions_on_crust and _is_on_surface(slime)
		_check(
			all_positions_on_crust,
			"Drops and diagonal walking stay inside every irregular crust sector in both views."
		)
		_check(
			closest_front < 0.05 and closest_rear > 0.95,
			"Both views allow feet to reach within a small inset of either visible edge."
		)
		print(
			(
				"%s projected crust depths: %.3f to %.3f."
				% ["Near" if near_view else "Overview", closest_front, closest_rear]
			)
		)
	# A near-view front-edge actor and destination must follow the narrower overview shore.
	_surface.set_near_view(true)
	slime.restore_to_surface(Vector2.UP * PLANET_RADIUS * 0.2)
	slime.set_process(false)
	slime._wander_target = slime.position
	var near_position: Vector2 = slime.position
	_surface.set_near_view(false)
	slime.refresh_surface_bounds()
	_check(
		(
			_is_on_surface(slime)
			and slime.position.length() > near_position.length()
			and _point_is_on_surface(slime._wander_target)
		),
		"Changing to overview reprojects feet and their destination onto its visible shore."
	)
	_surface.set_near_view(true)
	slime.refresh_surface_bounds()
	slime.setup(7, HOME, _surface)
	slime.set_process(false)


func _check_orphan_roaming(slime: PrototypeSlime) -> void:
	slime.release_from_nest()
	_check(slime.nest_id == 7, "Losing an active nest preserves the spawn source identifier.")
	_check(not slime._has_active_nest, "Losing a nest releases the local home constraint.")
	var target_angle: float = absf(angle_difference(HOME.angle(), slime._wander_target.angle()))
	_check(target_angle >= 1.19, "Losing a nest immediately chooses a distant surface target.")
	var first_orphan_target: Vector2 = slime._wander_target
	slime.release_from_nest()
	_check(
		slime._wander_target == first_orphan_target,
		"Repeated nest updates preserve an orphan's current destination."
	)
	# Verify far-side reachability independently of the random wandering schedule.
	slime._wander_target = Vector2.from_angle(HOME.angle() + PI) * PLANET_RADIUS
	slime._wander_wait = 0.0
	var greatest_angle: float = 0.0
	var valid_surface: bool = true
	for _frame: int in range(7200):
		slime._process(1.0 / 30.0)
		greatest_angle = maxf(
			greatest_angle, absf(angle_difference(HOME.angle(), slime.position.angle()))
		)
		valid_surface = valid_surface and _is_on_surface(slime)
	_check(valid_surface, "Orphan roaming follows the full crust without crossing the rock face.")
	_check(greatest_angle > 2.5, "An orphan can travel around the planet beyond its former nest.")


func _check_restoration(slime: PrototypeSlime) -> void:
	slime.consumed = true
	slime.capture_progress = 1.0
	slime.visible = false
	slime.set_process(false)
	slime.restore_to_surface(Vector2(600.0, 20.0))
	_check(
		not slime.consumed and is_zero_approx(slime.capture_progress),
		"Dropping a carried slime resets its collection state."
	)
	_check(slime.visible and slime.is_processing(), "A dropped slime becomes visible and active.")
	_check(_is_on_surface(slime), "An outside drop projects back to the surface ring.")
	_check(not slime._has_active_nest, "Dropping preserves a slime's orphan state.")
	slime.restore_to_surface(Vector2.ZERO)
	_check(_is_on_surface(slime), "A drop over the central sea projects to the inner shore.")
	var drop_position: Vector2 = slime.position
	slime._process(0.2)
	_check(slime.position != drop_position, "The restored actor resumes its surface wandering.")
	slime.set_process(false)


func _is_on_surface(slime: PrototypeSlime) -> bool:
	return _point_is_on_surface(slime.position)


func _point_is_on_surface(point: Vector2) -> bool:
	var angle: float = point.angle()
	var radial_distance: float = point.length()
	return (
		radial_distance >= _surface.get_inner_radius(angle) + 1.999
		and radial_distance <= _surface.get_outer_radius(angle) - 1.999
	)


func _get_surface_depth(point: Vector2) -> float:
	var inner: float = _surface.get_inner_radius(point.angle())
	var outer: float = _surface.get_outer_radius(point.angle())
	return inverse_lerp(inner, outer, point.length())


func _check_radial_orientation(slime: PrototypeSlime) -> void:
	var nest: NestView = NestScene.instantiate() as NestView
	root.add_child(nest)
	var cardinal_points: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for radial: Vector2 in cardinal_points:
		slime.setup(7, radial * PLANET_RADIUS, _surface)
		slime.set_process(false)
		_check(_faces_outward(slime), "A configured slime stands outward around its foot pivot.")
		slime.launch(radial.orthogonal())
		slime.set_process(false)
		_check(_faces_outward(slime), "Launch initialization keeps the slime's foot orientation.")
		slime._process(0.1)
		_check(_faces_outward(slime), "An airborne spawn bounce follows the current radial angle.")
		slime.restore_to_surface(radial * 240.0)
		slime.set_process(false)
		_check(_faces_outward(slime), "A dropped slime immediately faces outward.")
		slime._wander_target = radial.rotated(0.4) * 240.0
		slime._wander_wait = 0.0
		var old_rotation: float = slime.rotation
		slime._process(0.5)
		_check(
			_faces_outward(slime) and not is_equal_approx(slime.rotation, old_rotation),
			"A walking slime continuously turns with its changing surface position."
		)
		slime.apply_capture(0.1, 0.6, radial.rotated(0.3) * 240.0)
		_check(_faces_outward(slime), "Capture traction updates the slime's radial orientation.")
		nest.position = radial * PLANET_RADIUS
		nest.setup(7)
		_check(
			_faces_outward(nest), "Each cardinal nest stands radially outward at its ground root."
		)
		var nest_position: Vector2 = nest.position
		var nest_rotation: float = nest.rotation
		nest.update_state(3, true, 3)
		_check(
			nest.position == nest_position and is_equal_approx(nest.rotation, nest_rotation),
			"Taming preserves the flower bouquet's original ground root and orientation."
		)
		nest.update_state(0, false, 3)
	nest.queue_free()


func _check_attraction(slime: PrototypeSlime) -> void:
	slime.setup(7, HOME, _surface)
	slime.set_process(false)
	slime.restore_to_surface(HOME)
	slime.set_process(false)
	slime.capture_progress = 0.23
	var foot: Vector2 = slime.position
	var logical_body: Vector2 = slime.get_capture_point()
	var source: int = slime.nest_id
	slime._wander_target = Vector2.RIGHT * 240.0
	for frame: int in range(20):
		slime.apply_attraction(1.0 / 60.0, logical_body + Vector2.RIGHT * 80.0, 1.0)
		slime._process(1.0 / 60.0)
	_check(
		slime._attraction_offset.length() > 1.0 and slime._attraction_offset.length() <= 7.001,
		"Nearby suction adds a bounded visible pull."
	)
	_check(
		slime.position == foot and slime.get_capture_point().is_equal_approx(logical_body),
		"Visual attraction holds roaming without changing feet or the logical capture point."
	)
	_check(
		(
			is_equal_approx(slime.capture_progress, 0.23)
			and not slime.consumed
			and slime.nest_id == source
		),
		"Nearby attraction never advances capture or changes collection ownership."
	)
	slime._wander_target = foot
	slime._wander_wait = 10.0
	slime._process(1.0)
	_check(
		slime._attraction_offset.length() < 0.001 and slime._attraction_strength < 0.001,
		"Attraction smoothly returns to rest after its short hold expires."
	)
	slime.apply_attraction(0.1, logical_body + Vector2.RIGHT * 80.0, 1.0)
	slime.apply_capture(0.01, 0.6, logical_body)
	_check(
		slime._attraction_offset.is_zero_approx() and is_zero_approx(slime._attraction_strength),
		"Real capture clears nearby suction distortion instead of stacking both effects."
	)
	slime.apply_attraction(0.1, logical_body + Vector2.RIGHT * 80.0, 1.0)
	slime.restore_to_surface(HOME)
	_check(slime._attraction_offset.is_zero_approx(), "Restoring the actor clears attraction.")
	slime.apply_attraction(0.1, logical_body + Vector2.RIGHT * 80.0, 1.0)
	slime.setup(7, HOME, _surface)
	_check(slime._attraction_offset.is_zero_approx(), "Actor setup clears prior attraction.")
	slime.set_process(false)


func _check_flight(slime: PrototypeSlime) -> void:
	slime.left_screen.connect(_on_left_screen)
	var drop_settings: DropSettings = DropSettings.new()
	drop_settings.down_gravity = 0.0
	drop_settings.planet_gravity = 0.0
	drop_settings.release_down_speed = 0.0
	var bounds: Rect2 = Rect2(-300.0, -250.0, 600.0, 500.0)
	slime.position = Vector2(300.0, 0.0)
	slime.begin_fall(Vector2.RIGHT * 100.0, bounds, drop_settings)
	_check(
		slime.consumed and slime.visible and slime.is_processing(),
		"An ejected slime is visible and moving while unavailable for capture."
	)
	_check(slime.nest_id == 7, "Ejection keeps the slime's source nest identifier.")
	_check(
		not slime.apply_capture(1.0, 0.1, Vector2.ZERO),
		"A flying slime cannot be captured again during its exit."
	)
	var initial_rotation: float = slime.rotation
	slime._process(0.1)
	_check(
		slime.position.is_equal_approx(Vector2(310.0, 0.0)) and _flight_events == 0,
		"Flight advances in World coordinates before the consumed guard and retains edge padding."
	)
	_check(
		not is_equal_approx(slime.rotation, initial_rotation),
		"A flying slime may spin without being forced back to the ground-facing angle."
	)
	slime._process(0.19)
	_check(_flight_events == 0, "A slime touching the padded screen edge has not fully left.")
	slime._process(0.02)
	_check(
		_flight_events == 1 and _last_flight_slime == slime and not slime.is_processing(),
		"A fully off-screen slime reports itself once and stops processing."
	)
	var exit_position: Vector2 = slime.position
	slime._process(1.0)
	_check(
		_flight_events == 1 and slime.position == exit_position,
		"Repeated processing after flight completion cannot emit another departure."
	)
	_check(not slime.is_queued_for_deletion(), "Flight reports departure without freeing itself.")
	slime.restore_to_surface(Vector2.UP * 240.0)
	_check(
		(
			not slime._flying
			and not slime.consumed
			and slime.is_processing()
			and _faces_outward(slime)
		),
		"Restoring an ejected slime clears flight and resumes radial ground movement."
	)
	slime.begin_fall(Vector2.RIGHT * 100.0, bounds, drop_settings)
	slime.setup(7, HOME, _surface)
	_check(
		not slime._flying and not slime.consumed and _faces_outward(slime),
		"Reconfiguring a slime clears its previous flight state."
	)
	slime.set_process(false)


func _faces_outward(actor: Node2D) -> bool:
	return Vector2.UP.rotated(actor.rotation).dot(actor.position.normalized()) > 0.99999


func _on_left_screen(slime: PrototypeSlime) -> void:
	_flight_events += 1
	_last_flight_slime = slime


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
