extends SceneTree

const MucusField = preload("res://scripts/mucus_field.gd")
const GovernedRegion = preload("res://scripts/governed_region.gd")
const TrailScene: PackedScene = preload("res://scenes/effects/mucus_field.tscn")

var _failures: Array[String] = []
var _surface: PlanetSurface
var _landing_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_surface = PlanetSurface.new()
	root.add_child(_surface)
	_check_surface()
	_check_wide_crust_movement()
	_check_upright_orientation()
	_check_core_landing()
	_check_trails()
	_check_regions()
	_check_peel_duration()
	_surface.queue_free()
	await process_frame
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print(
			"PASS: wide crust excludes core, spans near foreground, routes movement and mucus around core, preserves view coordinates, landing and timed peel."
		)
	quit(0 if _failures.is_empty() else 1)


func _check_surface() -> void:
	_check(not _surface.contains_surface_point(Vector2.ZERO), "the planetary core is not walkable")
	var center_projection: Vector2 = _surface.project_to_surface(Vector2.ZERO)
	_check(
		_surface.contains_surface_point(center_projection),
		"invalid center positions project to the inner crust boundary"
	)
	_check(
		is_equal_approx(center_projection.length(), _surface.get_activity_radius_bounds(0.0).x),
		"center projection stops at the nearby inner boundary instead of the outer rim"
	)
	var correct: bool = true
	for index: int in range(180):
		var angle: float = float(index) * TAU / 180.0
		var bounds: Vector2 = _surface.get_activity_radius_bounds(angle)
		correct = (
			correct
			and is_equal_approx(bounds.x, _surface.radius * 0.60 + _surface.activity_edge_inset)
		)
		for depth: float in [0.01, 0.1, 0.45, 0.8, 0.999]:
			var point: Vector2 = Vector2.from_angle(angle) * lerpf(bounds.x, bounds.y, depth)
			correct = correct and _surface.contains_surface_point(point)
			correct = correct and _surface.project_to_surface(point) == point
		correct = (
			correct
			and not _surface.contains_surface_point(Vector2.from_angle(angle) * (bounds.x - 10.0))
		)
		correct = (
			correct
			and not _surface.contains_surface_point(Vector2.from_angle(angle) * (bounds.y + 20.0))
		)
		_surface.set_near_view(false)
		var overview_bounds: Vector2 = _surface.get_activity_radius_bounds(angle)
		_surface.set_near_view(true)
		correct = correct and overview_bounds == _surface.get_activity_radius_bounds(angle)
	_check(correct, "both views share one wide annular world area with an excluded core")
	_surface.position = Vector2(300.0, 200.0)
	_surface.scale = Vector2(1.65, 1.0)
	_surface.rotation = 0.7
	var transform: Transform2D = _surface.get_global_transform_with_canvas()
	_check(
		not _surface.contains_crust_viewport_point(transform * Vector2.ZERO),
		"viewport hit testing excludes the rotated core"
	)
	_check(
		_surface.contains_crust_viewport_point(transform * Vector2(0.0, -160.0)),
		"viewport hit testing includes deep foreground crust"
	)
	_surface.transform = Transform2D.IDENTITY


func _check_wide_crust_movement() -> void:
	var actor: PrototypeSlime = PrototypeSlime.new()
	root.add_child(actor)
	actor.setup(1, Vector2(-150.0, 0.0), _surface, PI / 2.0)
	actor.set_process(false)
	actor._rng.seed = 7045
	actor.position = Vector2(-150.0, 0.0)
	var target: Vector2 = Vector2(150.0, 0.0)
	var valid: bool = true
	var furthest_side: float = 0.0
	for step: int in range(1200):
		actor._move_on_surface(target, 0.75)
		valid = valid and _surface.contains_surface_point(actor.position)
		furthest_side = maxf(furthest_side, absf(actor.position.y))
		if actor.position.distance_to(target) < 0.01:
			break
	_check(
		valid and actor.position.distance_to(target) < 0.01,
		"opposite-side movement reaches its goal without crossing the core"
	)
	_check(
		furthest_side > _surface.get_inner_radius(0.0),
		"movement visibly goes around the inner boundary"
	)
	actor.setup(1, Vector2(0.0, -210.0), _surface, PI / 2.0)
	actor.set_process(false)
	actor._rng.seed = 7045
	var nearest: float = INF
	var farthest: float = 0.0
	for frame: int in range(9000):
		actor._process(1.0 / 30.0)
		valid = valid and _surface.contains_surface_point(actor.position)
		nearest = minf(nearest, actor.position.length())
		farthest = maxf(farthest, actor.position.length())
	_check(
		valid and nearest < 165.0 and farthest > 220.0,
		"natural two-dimensional roaming covers deep foreground and the outer crust"
	)
	actor.release_from_nest()
	var orphan_targets_valid: bool = true
	for sample: int in range(100):
		orphan_targets_valid = (
			orphan_targets_valid and _surface.contains_surface_point(actor._random_destination())
		)
	_check(
		orphan_targets_valid,
		"orphan roaming samples the wide crust instead of targeting the inaccessible core"
	)
	for home: Vector2 in [Vector2(0.0, -150.0), Vector2(55.0, -145.0), Vector2(-180.0, 15.0)]:
		actor.setup(1, home, _surface, PI / 2.0)
		actor.set_process(false)
		actor.launch(-home.normalized())
		_check(actor.position == home, "a crust nest launches from its actual position")
		for frame: int in range(20):
			actor._process(1.0 / 30.0)
			_check(
				_surface.contains_surface_point(actor.position),
				"inward launch never lands inside the core"
			)
	var held: Vector2 = actor.position
	_surface.set_near_view(false)
	actor.refresh_surface_bounds()
	_check(actor.position.distance_to(held) < 0.001, "view changes do not remap crust positions")
	_surface.set_near_view(true)
	actor.free()


func _check_upright_orientation() -> void:
	var frame: Node2D = Node2D.new()
	root.add_child(frame)
	frame.scale = Vector2(1.65, 1.0)
	frame.rotation = 1.2
	var actor: PrototypeSlime = PrototypeSlime.new()
	frame.add_child(actor)
	actor.setup(1, Vector2(0.0, -150.0), _surface)
	actor.set_process(false)
	for at: Vector2 in [Vector2(-150.0, 0.0), Vector2(0.0, -100.0), Vector2(150.0, 0.0)]:
		actor.position = at
		actor._update_surface_rotation()
		_check(
			(
				actor.get_global_transform_with_canvas().x.normalized().distance_to(Vector2.RIGHT)
				< 0.0001
			),
			"actors remain upright across the wide foreground"
		)
	frame.free()


func _check_core_landing() -> void:
	var actor: PrototypeSlime = PrototypeSlime.new()
	root.add_child(actor)
	actor.setup(1, Vector2(0.0, -150.0), _surface)
	actor.set_process(false)
	actor.position = Vector2.ZERO
	actor.landed.connect(_on_landed)
	actor.begin_fall(Vector2.ZERO, Rect2(-700.0, -700.0, 1400.0, 1400.0), DropSettings.new())
	actor.set_process(false)
	actor._process(0.03)
	_check(_landing_count == 0, "released monsters retain their brief visible fall")
	actor._process(1.0)
	_check(_landing_count == 1 and actor._flight_complete, "a release over the core resolves once")
	_check(
		_surface.contains_surface_point(actor.position) and actor.position.length() < 150.0,
		"core release settles onto the nearest inner crust instead of leaving an inaccessible actor"
	)
	var landing_position: Vector2 = actor.position
	actor.restore_to_surface(landing_position)
	actor.set_process(false)
	_check(
		actor.position.distance_to(landing_position) < 0.001,
		"landing restoration preserves the valid crust point"
	)
	actor.free()


func _on_landed(_actor: PrototypeSlime) -> void:
	_landing_count += 1


func _check_trails() -> void:
	var trail: MucusField = TrailScene.instantiate() as MucusField
	root.add_child(trail)
	trail.configure(_surface, Vector2(-30.0, -150.0), 1, 7.0, 7.0)
	trail.append_ground_point(Vector2(-25.0, -150.0))
	trail.append_ground_point(Vector2(25.0, -150.0))
	_check(
		trail.contains_ground_point(Vector2(0.0, -150.0)),
		"deep foreground mucus remains walkable and sticky"
	)
	_check(
		not trail.contains_ground_point(Vector2.ZERO),
		"mucus contact cannot make the planetary core playable"
	)
	var before: PackedVector2Array = trail.get_ground_points().duplicate()
	_surface.set_near_view(false)
	trail.refresh_surface()
	_check(trail.get_ground_points() == before, "overview keeps mucus world coordinates unchanged")
	_surface.set_near_view(true)
	trail.configure(_surface, Vector2(-153.0, 0.0), 1, 7.0, 7.0, 400.0)
	trail.append_ground_point(Vector2(152.0, 0.0))
	var avoids_core: bool = true
	for point: Vector2 in trail.get_ground_points():
		avoids_core = avoids_core and _surface.contains_surface_point(point)
	_check(
		(
			avoids_core
			and trail.get_ground_points().size() > 20
			and not trail.contains_ground_point(Vector2.ZERO)
		),
		"even a first long path segment follows the core boundary instead of painting across it"
	)
	trail.free()


func _check_regions() -> void:
	for home: Vector2 in [Vector2(0.0, -150.0), Vector2(140.0, -65.0), Vector2(215.0, 0.0)]:
		var region: GovernedRegion = GovernedRegion.new()
		root.add_child(region)
		region.configure(_surface, home)
		var valid: bool = not region._patches.is_empty()
		var covers_home: bool = false
		for patch: PackedVector2Array in region._patches:
			covers_home = covers_home or Geometry2D.is_point_in_polygon(home, patch)
			valid = valid and not Geometry2D.is_point_in_polygon(Vector2.ZERO, patch)
			for point: Vector2 in patch:
				valid = valid and _surface.contains_surface_point(point, -0.1)
		_check(
			valid and covers_home,
			"nest-colored regions are clipped to both edges of the wide crust"
		)
		region.free()


func _check_peel_duration() -> void:
	var actor: PrototypeSlime = PrototypeSlime.new()
	root.add_child(actor)
	actor.setup(1, Vector2(0.0, -150.0), _surface)
	actor.configure_species(PrototypeSlime.Species.MUCUS, false, 2)
	actor.set_process(false)
	actor.position = Vector2(0.0, -150.0)
	actor.on_mucus = true
	_check(
		not actor.pull_off_mucus(0.39, Vector2(10.0, -170.0), 0.4),
		"injected first-stage duration stays unchanged"
	)
	_check(
		actor.capture_progress == 0.0 and actor.position == Vector2(0.0, -150.0),
		"peeling does not translate or consume the anchored monster"
	)
	actor.release_capture(0.0)
	_check(actor.peel_progress == 0.0, "leaving a target clears partial peeling")
	_check(
		actor.pull_off_mucus(0.4, Vector2(10.0, -170.0), 0.4),
		"a complete first stage enables normal suction"
	)
	actor.free()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
