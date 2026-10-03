extends SceneTree

const SlimeScene: PackedScene = preload("res://scenes/world/slime.tscn")
const NestScene: PackedScene = preload("res://scenes/world/nest.tscn")
const PLANET_RADIUS: float = 240.0
const HOME: Vector2 = Vector2(0.0, -225.0)

var _failures: int = 0
var _flight_events: int = 0
var _last_flight_slime: PrototypeSlime


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var slime: PrototypeSlime = SlimeScene.instantiate() as PrototypeSlime
	root.add_child(slime)
	slime.setup(7, HOME, PLANET_RADIUS)
	slime.set_process(false)
	slime._rng.seed = 78143
	_check_local_roaming(slime)
	_check_launch(slime)
	_check_orphan_roaming(slime)
	_check_restoration(slime)
	_check_radial_orientation(slime)
	_check_attraction(slime)
	_check_flight(slime)
	slime.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: roaming, radial orientation, visual attraction, restoration and one-shot flight."
		)
	quit(0 if _failures == 0 else 1)


func _check_local_roaming(slime: PrototypeSlime) -> void:
	var greatest_angle: float = 0.0
	var minimum_radius: float = INF
	var maximum_radius: float = 0.0
	var valid_surface: bool = true
	for _frame: int in range(12000):
		slime._process(1.0 / 30.0)
		var angle: float = absf(angle_difference(HOME.angle(), slime.position.angle()))
		greatest_angle = maxf(greatest_angle, angle)
		minimum_radius = minf(minimum_radius, slime.position.length())
		maximum_radius = maxf(maximum_radius, slime.position.length())
		valid_surface = valid_surface and _is_on_surface(slime)
	_check(valid_surface, "Active-nest wander stays on the traversable surface ring.")
	_check(greatest_angle <= 0.421, "Active-nest wander retains a bounded home territory.")
	_check(greatest_angle > 0.30, "Local roaming uses the expanded angular territory.")
	_check(
		minimum_radius < 195.0 and maximum_radius > 260.0,
		"Local roaming uses both the inner and outer parts of the expanded surface."
	)


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
		shortest_launch >= 29.9 and longest_launch <= 50.1,
		"The configured launch moves approximately 30 to 50 pixels."
	)


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
	var greatest_angle: float = 0.0
	var valid_surface: bool = true
	for _frame: int in range(7200):
		slime._process(1.0 / 30.0)
		greatest_angle = maxf(
			greatest_angle, absf(angle_difference(HOME.angle(), slime.position.angle()))
		)
		valid_surface = valid_surface and _is_on_surface(slime)
	_check(valid_surface, "Orphan roaming follows the ring without crossing the central sea.")
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
	var radial_distance: float = slime.position.length()
	return (
		radial_distance >= PLANET_RADIUS - slime.surface_inner_offset - 0.001
		and radial_distance <= PLANET_RADIUS + slime.surface_outer_offset + 0.001
	)


func _check_radial_orientation(slime: PrototypeSlime) -> void:
	var nest: NestView = NestScene.instantiate() as NestView
	root.add_child(nest)
	var cardinal_points: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for radial: Vector2 in cardinal_points:
		slime.setup(7, radial * 225.0, PLANET_RADIUS)
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
		nest.position = radial * 225.0
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
	slime.setup(7, HOME, PLANET_RADIUS)
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
	slime.setup(7, HOME, PLANET_RADIUS)
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
	slime.setup(7, HOME, PLANET_RADIUS)
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
