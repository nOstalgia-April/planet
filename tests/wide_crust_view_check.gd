extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	root.mode = Window.MODE_WINDOWED
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		var demo: DemoScript = DemoScene.instantiate() as DemoScript
		root.add_child(demo)
		current_scene = demo
		demo.set_process(false)
		demo._layout.set_process(false)
		demo._window_has_focus = true
		await _settle()
		_check_foreground(demo)
		_seed_nests(demo)
		await _settle()
		_check_overview(demo)
		await _check_nest_access(demo)
		print("Checked %d nests at %s" % [demo.run.nests.size(), str(resolution)])
		for audio: Node in demo.get_node("Audio").get_children():
			if audio is AudioStreamPlayer:
				audio.stop()
		current_scene = null
		demo.queue_free()
		await process_frame
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print("PASS: wide foreground, overview isolation and rotated access to every sampled nest")
	quit(0 if _failures.is_empty() else 1)


func _check_foreground(demo: DemoScript) -> void:
	var screen: Vector2 = root.get_visible_rect().size
	var projection: Transform2D = demo._world.get_global_transform_with_canvas()
	var nominal_radius: float = demo._planet.radius * PlanetSurface.SURFACE_RADIUS_RATIO
	var center: Vector2 = projection * Vector2.ZERO
	var crest: Vector2 = projection * (Vector2.UP * nominal_radius)
	var right: Vector2 = projection * (Vector2.RIGHT * nominal_radius)
	_check(right.x - center.x > screen.x * 0.55, "P1 still fills a broad foreground band")
	_check(is_equal_approx(crest.y, screen.y * 0.55), "P1 arc crest is at 55% of height")
	_check(center.y > screen.y, "P1 foreground extends beyond the bottom edge")
	_check(
		is_equal_approx(demo._planet.get_inner_radius(0.0), demo._planet.radius * 0.60),
		"the wide crust retains its interior boundary"
	)
	_check(
		(
			is_equal_approx(projection.x.length(), projection.y.length())
			and demo._view.projection_root.scale.is_equal_approx(Vector2.ONE)
		),
		"the foreground is a cropped magnified circle without horizontal flattening"
	)
	_check(
		(
			not demo._planet.contains_surface_point(Vector2.ZERO)
			and not demo._can_collect(Vector2.ZERO, 0.1)
		),
		"the empty center remains outside the gameplay crust when cropped out of view"
	)
	for ratio: Vector2 in [
		Vector2(0.25, 0.78),
		Vector2(0.5, 0.78),
		Vector2(0.75, 0.78),
		Vector2(0.2, 0.95),
		Vector2(0.8, 0.95)
	]:
		var point: Vector2 = projection.affine_inverse() * (screen * ratio)
		_check(demo._planet.contains_surface_point(point), "foreground belongs to the active crust")
		_check(
			demo._can_collect(point, demo.run.get_pipe_radius()),
			"foreground accepts pipe interaction"
		)


func _seed_nests(demo: DemoScript) -> void:
	demo.run.settings = demo.run.settings.duplicate(true) as PrototypeSettings
	demo.run.settings.nest_roll_chance_min = 1.0
	demo.run.settings.nest_roll_chance_max = 1.0
	demo.run.settings.nest_spawn_cooldown_seconds = 0.0
	demo.run._random.seed = 7817
	demo._site_random.seed = 41129
	demo.run.candy = 100000
	_check(demo.run.upgrade_pipe(), "pipe level two opens the net research branch")
	_check(demo.run.purchase_technology("net"), "net unlock enables the legal spawn sampler")
	_check(demo.run.purchase_technology("governance"), "governance research enables nest upgrades")
	demo.run._advance_nest_roll(demo.run._nest_initial_delay_remaining)
	var scripted_count: int = demo.run.nests.size()
	for _roll: int in range(24):
		demo.run._advance_nest_roll(demo.run.settings.nest_roll_interval)
	_check(
		demo.run.nests.size() == demo._nest_site_angles.size(),
		"the legal sampler fills the perimeter's full-growth sites"
	)
	for index: int in range(scripted_count, demo.run.nests.size()):
		var point: Vector2 = demo.run.nests[index].position
		_check(
			point.distance_to(demo._planet.get_nest_position(point.angle())) < 0.001,
			"sampled nest stays on the outer crust line"
		)
	_check(demo._slimes.is_empty(), "spawn rolls do not advance population timers")


func _check_overview(demo: DemoScript) -> void:
	demo._view.zoom_steps(-1.0, false)
	_check(
		not demo._nests.visible and not demo._slime_root.visible,
		"P2 hides individual nests and monsters"
	)
	var candy: int = demo.run.candy
	for nest: NestState in demo.run.nests:
		var point: Vector2 = demo._world.get_global_transform_with_canvas() * nest.position
		demo._update_nest_hover(point)
		_check(
			demo.selected_nest_id == -1 and not demo._layout._nest_card.visible,
			"P2 hovering cannot open governance"
		)
		_check(
			not demo._can_collect(nest.position, demo.run.get_pipe_radius()), "P2 cannot collect"
		)
	demo._select_tool(DemoScript.ToolMode.NET)
	demo._drive_tool(1.0, demo.run.nests[0].position, true)
	_check(demo._net_phase == DemoScript.NetPhase.IDLE, "P2 cannot cast a net")
	_check(demo.run.candy == candy, "P2 interaction leaves the economy unchanged")
	demo._select_tool(DemoScript.ToolMode.PIPE)
	demo._view.zoom_steps(1.0, false)


func _check_nest_access(demo: DemoScript) -> void:
	var screen: Rect2 = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for nest: NestState in demo.run.nests:
		var rotation_delta: float = wrapf(
			-PI * 0.5 - nest.position.angle() - demo._world.rotation, -PI, PI
		)
		var screen_radius: float = (
			demo._planet.radius * demo._world.scale.x * demo._view.projection_root.scale.x
		)
		demo._view.begin_drag(Vector2.ZERO)
		demo._view.drag_to(Vector2(rotation_delta * screen_radius, 0.0))
		demo._view.end_drag()
		await _settle()
		var view: NestView = demo._nest_views[nest.nest_id - 1]
		var bounds: Rect2 = view.get_hover_rect()
		_check(screen.encloses(bounds), "rotated nest %d is fully on screen" % nest.nest_id)
		demo._update_nest_hover(bounds.get_center())
		_check(
			demo.selected_nest_id == nest.nest_id,
			"rotated nest %d can be selected in P1" % nest.nest_id
		)
		_check(
			demo._layout._nest_card.visible and not demo._nest_button.disabled,
			"P1 exposes its enabled governance button"
		)
		if demo.selected_nest_id == nest.nest_id and not demo._nest_button.disabled:
			demo._nest_button.pressed.emit()
			_check(nest.level == 1, "the selected nest receives its actual governance upgrade")
		demo._clear_nest_selection()
		await _settle()


func _settle() -> void:
	for _frame: int in range(3):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
