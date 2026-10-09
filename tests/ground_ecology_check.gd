extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const MucusField = preload("res://scripts/mucus_field.gd")
const NestMucusArea = preload("res://scripts/nest_mucus_area.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")

var _failures: Array[String] = []
var _capture: bool = false


func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_run_checks.call_deferred()


func _run_checks() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	await _settle_layout()
	_check_outer_nest_sites(demo)
	await _check_distinct_species_and_counts(demo)
	_check_nest_mucus_coverage(demo)
	_check_ground_contact_and_capture(demo)
	_check_surface_attachment(demo)
	await _check_trail_lifetime_and_limit(demo)
	await _check_partial_mucus_automation(demo)
	if _capture:
		await _capture_scenes(demo)
	demo.restart_run()
	await process_frame
	_check(
		(
			demo._mucus_trails.is_empty()
			and demo._active_mucus_trails.is_empty()
			and demo._nest_mucus_areas.is_empty()
			and demo._mucus_root.get_child_count() == 0
		),
		"restart clears every historical trail, active source, and scene node"
	)
	_check(
		demo._overview.population_counts == Vector2i.ZERO,
		"restart clears the overview's live species populations"
	)
	for audio: Node in demo.get_node("Audio").get_children():
		(audio as AudioStreamPlayer).stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	if _failures.is_empty():
		print(
			"PASS: pure-species nests, persistent nest mucus, moving ribbons, ground contact, crust clipping, lifetime/cap, automation and reset"
		)
	else:
		for failure: String in _failures:
			push_error("FAIL: " + failure)
	quit(0 if _failures.is_empty() else 1)


func _check_outer_nest_sites(demo: DemoScript) -> void:
	demo.restart_run()
	_unlock_net(demo)
	demo._site_random.seed = 7264
	for index: int in range(18):
		var species: NestState.Species = (index % 2) as NestState.Species
		demo.run._pending_nest_species = species
		demo._on_nest_spawn_requested(species)
	_check(demo.run.nests.size() > 3, "later discoveries create additional nests on the outer line")
	var on_edge: bool = true
	var spaced: bool = true
	for nest: NestState in demo.run.nests:
		on_edge = (
			on_edge
			and absf(nest.position.length() - demo._planet.get_outer_radius(nest.position.angle())) < 0.005
		)
		for other: NestState in demo.run.nests:
			if other.nest_id == nest.nest_id:
				continue
			spaced = (
				spaced
				and nest.position.distance_to(other.position) >= demo.run.settings.nest_min_distance - 0.005
			)
	_check(on_edge, "opening, first mucus and later nests all stand on the actual outer contour")
	_check(spaced, "outer-line sampling preserves hard spacing even when the perimeter fills")


func _check_distinct_species_and_counts(demo: DemoScript) -> void:
	_prepare_ecology(demo)
	_check_actor_species(demo)
	_check(
		(
			demo.run.get_nest(1).species == NestState.Species.SLIME
			and demo.run.get_nest(3).species == NestState.Species.MUCUS
		),
		"ordinary and newly unlocked mucus populations retain distinct nest types"
	)
	demo._view.zoom_steps(-1.0)
	demo._overview._process(2.0)
	await _check_overview_counts(demo)
	_check(
		demo._overview.bubble_radii.x > demo._overview.bubble_radii.y,
		"the initially larger ordinary population produces the larger overview bubble"
	)
	var ordinary_actors: Array[PrototypeSlime] = demo._slimes.duplicate()
	for actor: PrototypeSlime in ordinary_actors:
		if actor.species == PrototypeSlime.Species.SLIME:
			_capture_actor(demo, actor)
	demo._refresh_overview()
	demo._overview._process(2.0)
	await _check_overview_counts(demo)
	_check(
		(
			demo._overview.population_counts.x == 0
			and demo._overview.population_counts.y > 0
			and demo._overview.bubble_radii.y > demo._overview.bubble_radii.x
		),
		"the overview switches bubble dominance after real ordinary captures"
	)
	demo.run.candy = 10000
	demo.run.upgrade_pipe()
	demo.run.upgrade_pipe()
	for _level: int in range(2):
		demo.run.purchase_technology("governance")
		demo.run.upgrade_nest(3)
	demo.run.purchase_nest_technology(3, "valuable")
	demo.run.advance(demo.run.get_nest_spawn_interval(3) * 4.0)
	_freeze_actors(demo)
	_check_actor_species(demo)
	var valuable_mucus: int = 0
	for actor: PrototypeSlime in demo._slimes:
		if actor.high_value:
			_check(
				actor.nest_id == 3, "high-value spawning stays scoped to the researched mucus nest"
			)
			if actor.species == PrototypeSlime.Species.MUCUS:
				valuable_mucus += 1
	_check(
		valuable_mucus > 0,
		"upgraded mucus nests still produce mucus when a valuable individual appears"
	)
	await _check_overview_counts(demo)
	demo._view.zoom_steps(1.0)


func _check_nest_mucus_coverage(demo: DemoScript) -> void:
	_prepare_ecology(demo)
	_check(demo._nest_mucus_areas.size() == 1, "only mucus nests create persistent coverage")
	var area: NestMucusArea = demo._nest_mucus_areas[0]
	var nest: NestState = demo.run.get_nest(3)
	_check(
		is_equal_approx(area.coverage_radius, demo._regions[2].region_radius * 2.0),
		"nest coverage uses twice the small region circle radius, default 112 world units"
	)
	var covered: Vector2 = nest.position - nest.position.normalized() * area.coverage_radius * 0.5
	_check(area.contains_ground_point(covered), "the inland half of the nest pool is real ground mucus")
	_check(
		not area.contains_ground_point(nest.position + nest.position.normalized() * 12.0)
		and not area.contains_ground_point(Vector2.ZERO),
		"nest mucus cannot affect space outside the crust or inside the hollow core"
	)
	var clipped: bool = true
	for point: Vector2 in area._outline.polygon:
		clipped = clipped and point.length() >= demo._planet.get_inner_radius(point.angle()) - 0.1
		clipped = clipped and point.length() <= demo._planet.get_outer_radius(point.angle()) + 0.1
	_check(
		clipped and not area._outline.polygons.is_empty(),
		"visible pool geometry is clipped to the crust"
	)
	var normal: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.SLIME)
	var mucus: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.MUCUS)
	normal.position = covered
	mucus.position = covered
	demo._advance_ground_mucus(0.0)
	_check(
		normal.is_anchored() and mucus.is_anchored(),
		"persistent mucus slows normal collection and anchors a mucus monster even before it leaves a trail"
	)
	_check(
		not mucus.pull_off_mucus(mucus.peel_seconds * 0.5, mucus.get_capture_point()),
		"an anchored monster first enters the detachment stage"
	)
	_check(
		mucus.pull_off_mucus(mucus.peel_seconds * 0.5, mucus.get_capture_point())
		and not mucus.is_anchored(),
		"completed detachment allows ordinary suction while still above the persistent pool"
	)
	_capture_actor(demo, mucus)
	for actor: PrototypeSlime in demo._slimes:
		actor.detached_remaining = 1000.0
	demo._advance_ground_mucus(100.0)
	_check(
		area.contains_ground_point(covered),
		"capturing the source and expiring all trails does not clear nest mucus"
	)
	demo.run.candy = 10000
	demo.run.upgrade_pipe()
	demo.run.upgrade_pipe()
	for _level: int in range(3):
		demo.run.purchase_technology("governance")
		demo.run.upgrade_nest(3)
	_check(
		nest.is_tamed and area.contains_ground_point(covered),
		"full governance retains the living nest's mucus coverage"
	)
	demo._view.zoom_steps(-1.0)
	demo._view.zoom_steps(1.0)
	_check(area.contains_ground_point(covered), "view switching preserves the pool's ground contact")


func _check_ground_contact_and_capture(demo: DemoScript) -> void:
	_prepare_ecology(demo)
	var mucus: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.MUCUS)
	var normal: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.SLIME)
	var walked_path: PackedVector2Array = PackedVector2Array()
	var away_angle: float = demo.run.get_nest(3).position.angle() + PI
	var ground_radius: float = _ground_point(demo, away_angle, 0.5).length()
	for index: int in range(33):
		var progress: float = float(index) / 32.0
		walked_path.append(
			Vector2(lerpf(-26.0, 26.0, progress), -ground_radius + sin(progress * TAU) * 4.0)
			. rotated(away_angle + PI / 2.0)
		)
	mucus.position = walked_path[0]
	demo._advance_ground_mucus(0.0)
	var trail: MucusField = demo._active_mucus_trails[mucus.get_instance_id()] as MucusField
	_check(
		trail.get_ground_points().size() == 1 and not trail.contains_ground_point(mucus.position),
		"standing still starts only a source point, not a large circular pool"
	)
	for index: int in range(1, walked_path.size()):
		mucus.position = walked_path[index]
		demo._advance_ground_mucus(0.08)
	_check(
		(
			demo._active_mucus_trails[mucus.get_instance_id()] == trail
			and trail.get_ground_points()[-1].distance_to(mucus.position) < 0.005
		),
		"one continuous trail stays connected to its moving source's feet"
	)
	var gap_count: int = 0
	for index: int in range(2, walked_path.size() - 3):
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var sample: Vector2 = walked_path[index].lerp(walked_path[index + 1], fraction)
			if not trail.contains_ground_point(sample):
				gap_count += 1
	_check(gap_count == 0, "continuous walking leaves no gaps along the recorded centerline")
	var follows_path: bool = true
	for point: Vector2 in trail.get_ground_points():
		var closest: float = INF
		for index: int in range(walked_path.size() - 1):
			var projected: Vector2 = Geometry2D.get_closest_point_to_segment(
				point, walked_path[index], walked_path[index + 1]
			)
			closest = minf(closest, point.distance_to(projected))
		if closest > 0.5:
			follows_path = false
	_check(
		follows_path,
		"the centerline follows the traveled curve instead of chasing the monster as a rigid shape"
	)
	# Visual assertions request visible detail; offscreen uploads are deferred.
	trail.refresh_surface(false, true)
	var edge: PackedVector2Array = trail._edge.polygon
	_check(
		edge[0].distance_to(edge[1]) < edge[-2].distance_to(edge[-1]) * 0.5,
		"the historical tail is visibly narrower than the fresh band near the source"
	)
	var painted_point: Vector2 = walked_path[16]
	var clear_point: Vector2 = (
		painted_point.normalized() * (painted_point.length() + trail.half_width * 3.0)
	)
	normal.position = painted_point
	_check(
		demo._capture_seconds_for(normal) > demo.run.get_pipe_capture_seconds(),
		"ordinary capture slows only while the feet stand on the actual ribbon"
	)
	normal.position = clear_point
	_check(
		(
			not trail.contains_ground_point(clear_point)
			and is_equal_approx(
				demo._capture_seconds_for(normal), demo.run.get_pipe_capture_seconds()
			)
		),
		"unpainted ground beside the narrow ribbon has no mucus slowdown"
	)
	_check(mucus.is_anchored(), "a mucus monster touching the fresh ribbon needs detachment")
	var historical_anchors: PackedVector2Array = trail.anchors.duplicate()
	mucus.detached_remaining = 6.0
	mucus.position = _ground_point(demo, away_angle + 0.65, 0.5)
	demo._advance_ground_mucus(0.0)
	_check(
		(
			not mucus.on_mucus
			and not mucus.is_anchored()
			and not demo._active_mucus_trails.has(mucus.get_instance_id())
		),
		"detaching and leaving the ribbon stops both contact and further trail emission"
	)
	_check(
		trail.anchors == historical_anchors and trail.contains_ground_point(painted_point),
		"historical trail samples stay on their original ground when the source moves away"
	)
	_capture_actor(demo, mucus)
	demo._advance_ground_mucus(0.0)
	_check(
		(
			not demo._slimes.has(mucus)
			and demo._mucus_trails.has(trail)
			and trail.contains_ground_point(painted_point)
		),
		"capturing the source leaves its historical ribbon on the planet for its remaining lifetime"
	)
	normal.position = painted_point
	_check(
		demo._capture_seconds_for(normal) > demo.run.get_pipe_capture_seconds(),
		"another monster still encounters the old ribbon after its source is captured"
	)


func _check_surface_attachment(demo: DemoScript) -> void:
	_prepare_ecology(demo)
	var mucus: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.MUCUS)
	var trails: Array[MucusField] = []
	var snapshots: Array[PackedVector2Array] = []
	for angle: float in [-PI / 2.0, -0.37, PI - 0.01]:
		for depth: float in [0.05, 0.5, 1.0]:
			mucus.position = _ground_point(demo, angle - 0.075, depth)
			var trail: MucusField = demo._start_mucus_trail(mucus)
			for offset: float in [-0.04, 0.0, 0.04, 0.075]:
				mucus.position = _ground_point(demo, angle + offset, depth)
				trail.append_ground_point(mucus.position)
			trails.append(trail)
			snapshots.append(trail.anchors.duplicate())
	_check_trail_geometry(demo, trails, snapshots, "P1")
	demo._view.zoom_steps(-1.0)
	_check_trail_geometry(demo, trails, snapshots, "P2")
	_check(
		trails[-1].get_ground_points()[-1].distance_to(mucus.position) < 0.005,
		"switching to overview keeps the active ribbon head at the monster's feet"
	)
	var before_rotation: Vector2 = (
		trails[1].get_global_transform_with_canvas() * trails[1].get_ground_points()[0]
	)
	demo._view.begin_drag(Vector2.ZERO)
	demo._view.drag_to(Vector2(230.0, 0.0))
	demo._view.end_drag()
	var after_rotation: Vector2 = (
		trails[1].get_global_transform_with_canvas() * trails[1].get_ground_points()[0]
	)
	_check(
		before_rotation.distance_to(after_rotation) > 10.0,
		"historical ribbons visibly rotate with the planet"
	)
	_check_trail_geometry(demo, trails, snapshots, "rotated P2")
	demo._view.zoom_steps(1.0)
	_check_trail_geometry(demo, trails, snapshots, "rotated P1")
	_check(
		trails[-1].get_ground_points()[-1].distance_to(mucus.position) < 0.005,
		"returning to near view keeps the ribbon head and feet aligned without a fake connecting segment"
	)


func _check_trail_geometry(
	demo: DemoScript, trails: Array[MucusField], snapshots: Array[PackedVector2Array], label: String
) -> void:
	for index: int in range(trails.size()):
		var trail: MucusField = trails[index]
		_check(
			trail.anchors == snapshots[index],
			"%s preserves every historical angle/depth sample of trail %d" % [label, index]
		)
		var points: PackedVector2Array = trail.get_ground_points()
		var correct_depth: bool = points.size() == trail.anchors.size()
		for sample: int in range(points.size()):
			var anchor: Vector2 = trail.anchors[sample]
			var bounds: Vector2 = demo._planet.get_activity_radius_bounds(anchor.x)
			var expected: Vector2 = (
				Vector2.from_angle(anchor.x) * lerpf(bounds.x, bounds.y, anchor.y)
			)
			if points[sample].distance_to(expected) > 0.005:
				correct_depth = false
		_check(
			correct_depth,
			"%s keeps every trail %d sample at its recorded surface depth" % [label, index]
		)
		var within_surface: bool = true
		for layer: Polygon2D in [trail._edge, trail._ground, trail._highlight]:
			for vertex: Vector2 in layer.polygon:
				var bounds: Vector2 = demo._planet.get_activity_radius_bounds(vertex.angle())
				if vertex.length() < bounds.x - 0.005 or vertex.length() > bounds.y + 0.005:
					within_surface = false
		_check(
			within_surface and not trail._edge.polygons.is_empty(),
			(
				"%s clips all visible ribbon layers to the irregular crust for trail %d"
				% [label, index]
			)
		)


func _check_trail_lifetime_and_limit(demo: DemoScript) -> void:
	_prepare_ecology(demo)
	var mucus: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.MUCUS)
	for actor: PrototypeSlime in demo._slimes:
		actor.detached_remaining = 1000.0
	var first_trail: MucusField = null
	for index: int in range(demo.run.settings.mucus_trail_limit + 5):
		mucus.position = _ground_point(demo, -PI / 2.0 + float(index) * 0.075, 0.5)
		var trail: MucusField = demo._start_mucus_trail(mucus)
		trail.append_ground_point(_ground_point(demo, mucus.position.angle() + 0.05, 0.5))
		if index == 0:
			first_trail = trail
	_check(
		(
			demo._mucus_trails.size() == demo.run.settings.mucus_trail_limit
			and not demo._mucus_trails.has(first_trail)
			and first_trail.is_queued_for_deletion()
		),
		"the global trail cap retires the oldest histories without unbounded growth"
	)
	var last_trail: MucusField = demo._mucus_trails.back()
	var start_angle: float = last_trail.get_ground_points()[-1].angle()
	for index: int in range(1, 81):
		last_trail.append_ground_point(_ground_point(demo, start_angle + float(index) * 0.02, 0.5))
	var length: float = 0.0
	var points: PackedVector2Array = last_trail.get_ground_points()
	for index: int in range(1, points.size()):
		length += points[index].distance_to(points[index - 1])
	_check(
		length <= demo.run.settings.mucus_trail_max_length + 0.01,
		"a long walk trims the old tail to the configured maximum path length"
	)
	var fresh_opacity: float = last_trail._edge.vertex_colors[-1].a
	demo._advance_ground_mucus(demo.run.settings.mucus_trail_lifetime - 0.8)
	# Visual assertions request visible detail after hidden history simulation.
	last_trail.refresh_surface(false, true)
	_check(
		demo._mucus_trails.has(last_trail) and last_trail._edge.vertex_colors[-1].a < fresh_opacity,
		"stopped historical trails visibly fade before their lifetime ends"
	)
	var last_center: Vector2 = last_trail.get_ground_points()[-2]
	demo._advance_ground_mucus(0.9)
	_check(
		(
			demo._mucus_trails.is_empty()
			and demo._active_mucus_trails.is_empty()
			and not last_trail.contains_ground_point(last_center)
		),
		"expired ribbons leave the visual history, active registry, and ground contact map"
	)
	await process_frame
	_check(
		demo._mucus_root.get_child_count() == demo._nest_mucus_areas.size(),
		"expired ribbon scene nodes are released while nest coverage persists"
	)


func _check_partial_mucus_automation(demo: DemoScript) -> void:
	_prepare_ecology(demo)
	demo.run.candy = 10000
	demo.run.upgrade_pipe()
	demo.run.purchase_technology("governance")
	demo.run.purchase_technology("governance")
	demo.run.upgrade_nest(3)
	demo.run.upgrade_nest(3)
	var population: int = demo.run.get_nest(3).alive_slimes
	var before: int = demo.run.candy
	demo.run.advance(1.0)
	_check(
		demo.run.get_nest(3).alive_slimes == population and demo.run.candy == before,
		"Intermediate mucus cultivation has no automatic collection or income."
	)
	demo.run.upgrade_nest(3)
	before = demo.run.candy
	demo.run.advance(6.0)
	_check(
		demo.run.get_nest(3).alive_slimes == population and demo.run.candy == before + 18,
		"Full mucus automation stops spawning and pays passive candy without consuming actors."
	)
	_check_actor_species(demo)
	await _check_overview_counts(demo)


func _capture_scenes(demo: DemoScript) -> void:
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		root.size = resolution
		await _settle_layout()
		demo.restart_run()
		_unlock_net(demo)
		_look_at_nest(demo, 3)
		_warm_ecology(demo, 8.0)
		demo._pipe.hide()
		demo._net.hide()
		await _settle_layout()
		await _save_frame("ribbon_mucus_small_%dx%d.png" % [resolution.x, resolution.y])
		await _save_frame("crust_mucus_p1_%dx%d.png" % [resolution.x, resolution.y])
		demo.run.candy = 1000
		demo.run.purchase_technology("governance")
		demo.run.upgrade_nest(3)
		_warm_ecology(demo, 0.5)
		await _settle_layout()
		await _save_frame("ribbon_mucus_cave_%dx%d.png" % [resolution.x, resolution.y])
		demo._view.zoom_steps(-1.0)
		demo._overview._process(2.0)
		await _settle_layout()
		await _save_frame("ribbon_overview_%dx%d.png" % [resolution.x, resolution.y])


func _prepare_ecology(demo: DemoScript) -> void:
	demo.restart_run()
	_unlock_net(demo)
	demo.run.advance(demo.run.settings.spawn_intervals[0] * 4.0)
	_freeze_actors(demo)


func _unlock_net(demo: DemoScript) -> void:
	demo.run.candy = demo.run.settings.net_unlock_cost + demo.run.get_pipe_upgrade_cost()
	_check(demo.run.upgrade_pipe(), "speed level two enables net research")
	_check(demo.run.purchase_technology("net"), "unlocking the net discovers the first mucus nest")
	demo.run.candy = 0


func _freeze_actors(demo: DemoScript) -> void:
	for actor: PrototypeSlime in demo._slimes:
		actor._process(actor.launch_seconds)
		actor.set_process(false)


func _warm_ecology(demo: DemoScript, seconds: float) -> void:
	for _step: int in range(int(seconds * 10.0)):
		demo.run.advance(0.1)
		for actor: PrototypeSlime in demo._slimes:
			actor._process(0.1)
			actor.set_process(false)
		demo._advance_ground_mucus(0.1)


func _capture_actor(demo: DemoScript, actor: PrototypeSlime) -> void:
	if not demo._slimes.has(actor):
		return
	# Isolate this species-ledger fixture from the pipe's new all-neighbor gathering.
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
	_check(not demo._slimes.has(actor), "the pipe captures the requested real individual")
	for index: int in range(neighbors.size()):
		neighbors[index].position = positions[index]


func _ground_point(demo: DemoScript, angle: float, depth: float) -> Vector2:
	var bounds: Vector2 = demo._planet.get_activity_radius_bounds(angle)
	return Vector2.from_angle(angle) * lerpf(bounds.x, bounds.y, depth)


func _check_actor_species(demo: DemoScript) -> void:
	for nest: NestState in demo.run.nests:
		var actual: int = 0
		for actor: PrototypeSlime in demo._slimes:
			if actor.nest_id == nest.nest_id:
				actual += 1
				_check(
					int(actor.species) == int(nest.species),
					"every actor matches its nest's fixed species"
				)
		_check(
			actual == nest.alive_slimes,
			"each pure-species actor population matches its region ledger"
		)


func _check_overview_counts(demo: DemoScript) -> void:
	await process_frame
	var actual: Vector2i = Vector2i.ZERO
	for actor: PrototypeSlime in demo._slimes:
		if actor.species == PrototypeSlime.Species.SLIME:
			actual.x += 1
		else:
			actual.y += 1
	_check(
		demo._overview.population_counts == actual,
		"overview counts equal living actors, including valuable individuals once"
	)


func _first_species(demo: DemoScript, species: PrototypeSlime.Species) -> PrototypeSlime:
	for actor: PrototypeSlime in demo._slimes:
		if actor.species == species:
			return actor
	return null


func _look_at_nest(demo: DemoScript, nest_id: int) -> void:
	var target_rotation: float = -PI / 2.0 - demo.run.get_nest(nest_id).position.angle()
	var difference: float = angle_difference(demo._world.rotation, target_rotation)
	var screen_radius: float = (
		demo._planet.radius * demo._world.scale.x * demo._view.projection_root.scale.x
	)
	demo._view.begin_drag(Vector2.ZERO)
	demo._view.drag_to(Vector2(difference * screen_radius, 0.0))
	demo._view.end_drag()


func _settle_layout() -> void:
	for _frame: int in range(4):
		await process_frame


func _save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png("res://artifacts/" + filename)
	_check(result == OK, "saved " + filename)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
