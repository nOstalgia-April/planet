extends SceneTree

const SlimeScene: PackedScene = preload("res://scenes/world/slime.tscn")
const Settings: DropSettings = preload("res://resources/drop_settings.tres")
const PLANET_RADIUS: float = 240.0
const TEST_BOUNDS: Rect2 = Rect2(-700.0, -700.0, 1400.0, 1400.0)

var _failures: int = 0
var _landed_count: int = 0
var _left_count: int = 0
var _last_reported: PrototypeSlime


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var surface: PlanetSurface = PlanetSurface.new()
	surface.radius = PLANET_RADIUS
	root.add_child(surface)
	var slime: PrototypeSlime = SlimeScene.instantiate() as PrototypeSlime
	root.add_child(slime)
	slime.setup(9, Vector2.UP * 225.0, surface)
	slime.landed.connect(_on_landed)
	slime.left_screen.connect(_on_left_screen)
	_check_near_landing(slime)
	_check_inside_surface_release(slime)
	_check_far_departure(slime)
	_check_upper_return(slime)
	_check_large_delta(slime)
	_check_orphan_landing(slime)
	_check_bounds_update(slime)
	_check_capture_point(slime)
	slime.queue_free()
	surface.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: downward drop, inverse-square return, offscreen exit, swept landing, resize bounds and body capture."
		)
	quit(0 if _failures == 0 else 1)


func _prepare_drop(slime: PrototypeSlime, release_position: Vector2) -> void:
	_landed_count = 0
	_left_count = 0
	_last_reported = null
	slime.restore_to_surface(Vector2.UP * PLANET_RADIUS)
	slime.position = release_position
	slime.begin_fall(Vector2.ZERO, TEST_BOUNDS, Settings)
	slime.set_process(false)


func _advance_until_result(slime: PrototypeSlime) -> void:
	for _step: int in range(500):
		if _landed_count + _left_count > 0:
			return
		slime._process(0.02)
	_check(false, "A released actor reaches a landing or offscreen result within ten seconds.")


func _check_near_landing(slime: PrototypeSlime) -> void:
	_prepare_drop(slime, Vector2(260.0, 0.0))
	var release_position: Vector2 = slime.position
	slime._process(0.02)
	_check(
		slime.position.y > release_position.y and _landed_count == 0 and _left_count == 0,
		"A nearby release first moves downward instead of immediately snapping to the surface."
	)
	_check(
		slime.consumed and not slime.apply_capture(0.6, 0.6, slime.get_capture_point()),
		"A falling actor remains unavailable for collection before its result."
	)
	_advance_until_result(slime)
	_check(
		_landed_count == 1 and _left_count == 0 and _last_reported == slime,
		"Planet gravity returns a nearby side release to the surface exactly once."
	)
	_check(
		is_equal_approx(slime.position.length(), PLANET_RADIUS),
		"A landed actor rests at the planet surface instead of inside the central sea."
	)
	var landed_position: Vector2 = slime.position
	slime._process(1.0)
	_check(
		_landed_count == 1 and slime.position == landed_position,
		"A completed landing does not emit again or continue falling."
	)
	_check(
		not slime.is_queued_for_deletion(),
		"Landing leaves reparenting and settlement to the coordinator."
	)


func _check_inside_surface_release(slime: PrototypeSlime) -> void:
	_prepare_drop(slime, Vector2.UP * 200.0)
	var initial_y: float = slime.position.y
	slime._process(0.03)
	_check(
		slime.position.y > initial_y and _landed_count == 0,
		"A release born inside the walkable disk still has a brief visible fall."
	)
	slime._process(2.0)
	_check(
		(
			_landed_count == 1
			and _left_count == 0
			and slime.position.distance_to(Vector2.UP * 200.0) < 40.0
		),
		"An interior release settles near its actual position without being sent to the outer ring."
	)


func _check_far_departure(slime: PrototypeSlime) -> void:
	var distant_positions: Array[Vector2] = [Vector2(550.0, 0.0), Vector2(0.0, 520.0)]
	for release_position: Vector2 in distant_positions:
		_prepare_drop(slime, release_position)
		_advance_until_result(slime)
		_check(
			_left_count == 1 and _landed_count == 0,
			"Distant side and bottom releases fall offscreen under weaker planet attraction."
		)
		_check(
			not TEST_BOUNDS.grow(slime.body_size * 2.0).has_point(slime.position),
			"The departure waits until the whole actor passes the padded viewport edge."
		)
		var departure_position: Vector2 = slime.position
		slime._process(1.0)
		_check(
			_left_count == 1 and slime.position == departure_position,
			"An offscreen result emits once and stops further movement."
		)


func _check_upper_return(slime: PrototypeSlime) -> void:
	_prepare_drop(slime, Vector2.UP * 500.0)
	_advance_until_result(slime)
	_check(
		_landed_count == 1 and _left_count == 0 and slime.position.y < 0.0,
		"A distant upper release can still be pulled back onto the planet by real gravity."
	)


func _check_large_delta(slime: PrototypeSlime) -> void:
	_prepare_drop(slime, Vector2.UP * 360.0)
	slime._process(3.0)
	_check(
		_landed_count == 1 and _left_count == 0 and slime.position.y < 0.0,
		"Fixed substeps stop a large frame at the first surface contact."
	)
	_check(
		is_equal_approx(slime.position.length(), PLANET_RADIUS),
		"The large frame cannot tunnel through the planet."
	)


func _check_orphan_landing(slime: PrototypeSlime) -> void:
	slime.release_from_nest()
	_prepare_drop(slime, Vector2(260.0, 0.0))
	_advance_until_result(slime)
	_check(_landed_count == 1, "A monster without a nest may still land on the surface.")
	slime.restore_to_surface(slime.position)
	_check(
		(
			slime.nest_id == 9
			and not slime._has_active_nest
			and not slime.consumed
			and not slime._flying
		),
		"Landing restoration keeps the source and orphan state while clearing the fall state."
	)
	slime.set_process(false)


func _check_bounds_update(slime: PrototypeSlime) -> void:
	_prepare_drop(slime, Vector2(0.0, 520.0))
	slime._process(0.02)
	_check(_left_count == 0, "A resized viewport test starts inside its original local bounds.")
	var resized_bounds: Rect2 = Rect2(-700.0, -700.0, 1400.0, 1000.0)
	slime.update_fall_bounds(resized_bounds)
	slime._process(0.02)
	_check(
		_left_count == 1 and _landed_count == 0,
		"Updated World-local viewport bounds take effect on the next fall step."
	)


func _check_capture_point(slime: PrototypeSlime) -> void:
	var cardinal_points: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for radial: Vector2 in cardinal_points:
		slime.restore_to_surface(radial * PLANET_RADIUS)
		slime.set_process(false)
		var target: Vector2 = slime.get_capture_point()
		_check(
			target.distance_to(slime.position + Vector2.UP * slime.body_size * 0.65) < 0.001,
			"The capture point stays above the upright body at every position on the disk."
		)
		slime.apply_capture(0.1, 0.6, target)
		_check(
			slime.get_capture_point().distance_to(target) < 0.001,
			"A direct body-center hit does not jump outward and lose its narrow capture lock."
		)
		var nearby_target: Vector2 = target + radial.orthogonal() * 8.0
		var initial_distance: float = slime.get_capture_point().distance_to(nearby_target)
		slime.apply_capture(0.1, 0.6, nearby_target)
		_check(
			slime.get_capture_point().distance_to(nearby_target) < initial_distance,
			"Capture traction pulls the body toward the mouth while preserving foot orientation."
		)


func _on_landed(slime: PrototypeSlime) -> void:
	_landed_count += 1
	_last_reported = slime


func _on_left_screen(slime: PrototypeSlime) -> void:
	_left_count += 1
	_last_reported = slime


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
