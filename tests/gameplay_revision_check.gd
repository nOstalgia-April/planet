extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const MucusField = preload("res://scripts/mucus_field.gd")
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
	demo._layout.set_process(false)
	demo._view.set_process(false)
	await _settle()
	_check_opening(demo)
	await _check_overview(demo)
	_check_foreground_capture(demo)
	_check_peel_time_budget(demo)
	_check_mucus_outside_center(demo)
	if _capture:
		await _capture_views(demo)
	for node: Node in demo.get_node("Audio").get_children():
		(node as AudioStreamPlayer).stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print(
			"PASS: two visible opening nests, locked net, overview isolation/data retention and exact mucus time budget"
		)
	quit(0 if _failures.is_empty() else 1)


func _check_opening(demo: DemoScript) -> void:
	_check(demo.run.nests.size() == 2, "exactly two nests exist at the opening")
	var screen: Rect2 = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for index: int in range(2):
		_check(
			demo.run.nests[index].species == NestState.Species.SLIME,
			"both opening nests are basic slimes"
		)
		_check(
			screen.encloses(demo._nest_views[index].get_hover_rect()),
			"both opening nest bodies fit on screen"
		)
		_check(
			not demo._regions[index]._patches.is_empty(),
			"each opening nest has a clipped land patch on the full planet"
		)
	_check(not demo.run.net_unlocked and not demo.run.can_cast_net(), "the net starts locked")
	demo._select_tool(DemoScript.ToolMode.NET)
	_check(
		demo._active_tool == DemoScript.ToolMode.PIPE, "a locked net cannot become the active tool"
	)
	demo._layout.close_panels()
	demo.run.advance(demo.run.settings.spawn_intervals[0] - 0.01)
	_check(demo._slimes.is_empty(), "no actor appears before the first burst interval")
	demo.run.advance(0.01)
	_freeze(demo)
	for nest: NestState in demo.run.nests:
		_check(
			nest.alive_slimes in [2, 3],
			"a basic nest emits 20 to 30 percent of its capacity at once"
		)


func _check_overview(demo: DemoScript) -> void:
	var actors: Array[PrototypeSlime] = demo._slimes.duplicate()
	var candy: int = demo.run.candy
	var counts: Vector2i = Vector2i(demo._slimes.size(), 0)
	demo._view.zoom_steps(-1.0)
	await _settle()
	_check(
		(
			not demo._slime_root.visible
			and not demo._nests.visible
			and not demo._mucus_root.visible
			and not demo._effects.visible
		),
		"the overview hides individual monsters, nests, mucus and collection effects"
	)
	_check(
		not demo._region_root.visible and demo._overview.visible,
		"the overview hides actual crust regions and uses abstract surface statistics"
	)
	_check(
		not demo._pipe.visible and not demo._net.visible,
		"switching to overview immediately hides both tools"
	)
	_check(
		demo._overview.population_counts == counts,
		"species bubbles display the actual living count"
	)
	var point: Vector2 = actors[0].get_capture_point()
	_check(
		not demo._can_collect(point, demo.run.get_pipe_radius()),
		"the overview disables world collection"
	)
	demo._drive_tool(10.0, point, true)
	_check(
		demo._slimes == actors and demo.run.candy == candy,
		"overview input cannot consume invisible monsters"
	)
	demo._view.zoom_steps(1.0)
	await _settle()
	_check(
		demo._slime_root.visible and demo._nests.visible and demo._region_root.visible,
		"near view restores the individual actors, nests and actual crust regions"
	)
	_check(
		demo._slimes == actors and demo._overview.population_counts == counts,
		"switching views retains every actor and population ledger"
	)


func _check_peel_time_budget(demo: DemoScript) -> void:
	demo.run.candy = demo.run.settings.net_unlock_cost
	_check(demo.run.purchase_technology("net"), "a legal purchase unlocks the net")
	_check(
		demo.run.nests.size() == 3 and demo.run.get_nest(3).species == NestState.Species.MUCUS,
		"net unlock adds one mucus nest"
	)
	for level: int in range(demo.run.settings.pipe_capture_seconds.size()):
		demo.run.pipe_level = level
		_check_peel_at_level(demo)


func _check_peel_at_level(demo: DemoScript) -> void:
	demo.run.advance(demo.run.settings.spawn_intervals[0] * 2.0)
	_freeze(demo)
	var mucus: Array[PrototypeSlime] = []
	for actor: PrototypeSlime in demo._slimes:
		actor.position = Vector2(700.0, 700.0)
		if actor.species == PrototypeSlime.Species.MUCUS:
			mucus.append(actor)
	_check(mucus.size() >= 2, "two real mucus actors are available for detachment boundaries")
	if mucus.size() < 2:
		return
	var ground: Vector2 = Vector2(24.0, -160.0)
	mucus[0].position = ground - Vector2(15.0, 0.0)
	var trail: MucusField = demo._start_mucus_trail(mucus[0])
	mucus[0].position = ground
	trail.append_ground_point(ground)
	var before: int = demo.run.candy
	var capture_seconds: float = demo.run.get_pipe_capture_seconds()
	demo._capture_at(capture_seconds, mucus[0].get_capture_point(), true)
	_check(
		not mucus[0].is_anchored() and is_zero_approx(mucus[0].capture_progress),
		"one current pipe interval only detaches mucus and never counts twice toward suction"
	)
	_check(
		demo.run.candy == before and demo._slimes.has(mucus[0]),
		"detachment itself creates no reward"
	)
	demo._capture_at(capture_seconds, mucus[0].get_capture_point(), true)
	_check(
		not demo._slimes.has(mucus[0]) and demo.run.candy == before + mucus[0].reward,
		"normal suction time is still required after detachment"
	)
	mucus[1].position = ground
	before = demo.run.candy
	demo._capture_at(capture_seconds * 1.5, mucus[1].get_capture_point(), true)
	_check(
		demo._slimes.has(mucus[1]) and is_equal_approx(mucus[1].capture_progress, 0.5),
		"a coarse frame spends one pipe interval peeling and only its remainder on suction"
	)
	_check(demo.run.candy == before, "a half-finished coarse-frame suction pays nothing")
	demo._capture_at(capture_seconds * 0.5 + 0.0001, mucus[1].get_capture_point(), true)
	_check(
		not demo._slimes.has(mucus[1]), "the remaining normal suction time completes the capture"
	)


func _check_mucus_outside_center(demo: DemoScript) -> void:
	demo.run.pipe_level = 0
	demo.run.advance(demo.run.settings.spawn_intervals[0] * 2.0)
	_freeze(demo)
	var actor: PrototypeSlime = null
	for candidate: PrototypeSlime in demo._slimes:
		candidate.position = Vector2(700.0, 700.0)
		if candidate.species == PrototypeSlime.Species.MUCUS:
			actor = candidate
	_check(actor != null, "a real mucus actor is available outside the center")
	if actor == null:
		return
	actor.detached_remaining = 0.0
	actor.peel_progress = 0.0
	actor.position = Vector2(-70.0, -185.0)
	var trail: MucusField = demo._start_mucus_trail(actor)
	actor.position = Vector2(-55.0, -185.0)
	trail.append_ground_point(actor.position)
	actor.on_mucus = demo._is_on_ground_mucus(actor.position)
	_check(actor.is_anchored(), "the mucus fixture starts attached to a real trail")
	var target: Vector2 = actor.get_capture_point() + Vector2.RIGHT * 60.0
	var before: int = demo.run.candy
	var original: Vector2 = actor.position
	demo._capture_at(1.0, target, true)
	_check(
		(
			actor.position.is_equal_approx(original)
			and is_zero_approx(actor.capture_progress)
			and is_zero_approx(actor.peel_progress)
			and actor.is_anchored()
			and demo.run.candy == before
		),
		"A mucus actor outside the center remains in place with no peeling or collection."
	)
	target = actor.get_capture_point()
	var seconds: float = demo.run.get_pipe_capture_seconds()
	demo._capture_at(seconds * 0.5, target, true)
	_check(
		is_equal_approx(actor.peel_progress, 0.5) and is_zero_approx(actor.capture_progress),
		"Direct center targeting starts peeling before intake."
	)
	demo._capture_at(seconds * 0.5, target, true)
	_check(
		not actor.is_anchored() and is_zero_approx(actor.capture_progress),
		"Finishing peel cannot simultaneously finish intake."
	)
	demo._capture_at(seconds, target, true)
	_check(
		not demo._slimes.has(actor) and demo.run.candy == before + actor.reward,
		"Direct center targeting pays once after both mucus stages."
	)


func _check_foreground_capture(demo: DemoScript) -> void:
	var viewport_size: Vector2 = root.get_visible_rect().size
	var surface_transform: Transform2D = demo._world.get_global_transform_with_canvas()
	var horizon: Vector2 = (
		surface_transform * (Vector2.UP * demo._planet.get_outer_radius(-PI / 2.0))
	)
	_check(
		absf(horizon.y / viewport_size.y - 0.55) < 0.02,
		"near view matches the reference horizon near the middle of the screen"
	)
	_check(
		surface_transform.origin.y > viewport_size.y,
		"the planet continues below the foreground instead of appearing as a full disk"
	)
	for normalized_point: Vector2 in [Vector2(0.35, 0.70), Vector2(0.5, 0.78), Vector2(0.7, 0.82)]:
		var actor: PrototypeSlime = demo._slimes[0]
		for other: PrototypeSlime in demo._slimes:
			other.position = Vector2(700.0, 700.0)
		actor.position = surface_transform.affine_inverse() * (viewport_size * normalized_point)
		var target: Vector2 = actor.get_capture_point()
		_check(
			demo._planet.contains_surface_point(actor.position),
			"visible foreground is playable ground"
		)
		_check(
			demo._can_collect(target, demo.run.get_pipe_radius()),
			"foreground collection passes input gates"
		)
		var before: int = demo.run.candy
		demo._drive_tool(demo.run.get_pipe_capture_seconds(), target, true)
		_check(
			not demo._slimes.has(actor) and demo.run.candy == before + actor.reward,
			"the real tool captures actors across the ground from horizon to foreground"
		)


func _capture_views(demo: DemoScript) -> void:
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		root.size = resolution
		await _settle()
		demo.restart_run()
		demo.run.advance(4.0)
		_freeze(demo)
		demo._pipe.hide()
		await _save("gameplay_opening_%dx%d.png" % [resolution.x, resolution.y])
		demo.run.candy = demo.run.settings.net_unlock_cost
		demo.run.purchase_technology("net")
		demo.run.advance(8.0)
		_freeze(demo)
		demo._view.zoom_steps(-1.0)
		demo._overview._process(2.0)
		await _settle()
		await _save("gameplay_overview_%dx%d.png" % [resolution.x, resolution.y])
		demo._view.zoom_steps(1.0)


func _freeze(demo: DemoScript) -> void:
	for actor: PrototypeSlime in demo._slimes:
		actor._process(actor.launch_seconds)
		actor.set_process(false)


func _settle() -> void:
	for _frame: int in range(4):
		await process_frame


func _save(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check(
		root.get_texture().get_image().save_png("res://artifacts/" + filename) == OK,
		"saved " + filename
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
