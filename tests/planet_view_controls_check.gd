extends SceneTree

const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")
const PlanetViewController = preload("res://scripts/planet_view_controller.gd")
const SurfaceProjection = preload("res://scripts/surface_projection.gd")

var _failures: Array[String] = []
var _view_changes: int = 0


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._layout.set_process(false)
	var camera: PlanetViewController = demo._view
	camera.set_process(false)
	camera.view_changed.connect(_on_view_changed)
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		root.size = resolution
		await _settle()
		demo._apply_layout()
		demo.restart_run()
		demo._window_has_focus = true
		demo.run.advance(
			demo.run.settings.spawn_intervals[0] + demo.run.settings.spawn_interval_jitter
		)
		_check(not demo._slimes.is_empty(), "the control fixture contains real living actors")
		for actor: PrototypeSlime in demo._slimes:
			actor._process(actor.launch_seconds)
			actor.set_process(false)
		var nests_before: Array[NestView] = demo._nest_views.duplicate()
		var actors_before: Array[PrototypeSlime] = demo._slimes.duplicate()
		var positions_before: Array[Vector2] = []
		for nest: NestState in demo.run.nests:
			positions_before.append(nest.position)
		var candy_before: int = demo.run.candy
		_check_near_projection(demo)
		_check_body_hits(demo)
		_check_mode_drag_input(demo)
		_check_ui_and_focus_gates(demo)
		await _capture("planet_controls_near", resolution)
		_check_overview_rotation(demo)
		_check_body_hits(demo)
		_check_mode_drag_input(demo)
		_check_ui_and_focus_gates(demo)
		await _capture("planet_controls_overview", resolution)
		var rotation: float = demo._world.rotation
		_mouse_button(_background(demo), MOUSE_BUTTON_WHEEL_UP, true)
		camera._process(camera.transition_seconds)
		_check(
			(
				not camera.is_overview()
				and absf(angle_difference(demo._world.rotation, rotation)) < 0.0001
			),
			"one wheel step returns to the original near projection without changing rotation"
		)
		camera._process(8.0)
		_check(
			absf(angle_difference(demo._world.rotation, rotation)) < 0.0001,
			"returning to near view stops self-rotation"
		)
		_check(
			(
				demo._nest_views == nests_before
				and demo._slimes == actors_before
				and demo.run.candy == candy_before
			),
			"rotation and mode changes preserve the same actors, nests and wallet"
		)
		for index: int in range(demo.run.nests.size()):
			_check(
				demo.run.nests[index].position == positions_before[index],
				"view rotation changes projection without moving world-space nests"
			)
		await _check_overview_top_handoff(demo, resolution)
		_check_restart(demo)
	for child: Node in demo.get_node("Audio").get_children():
		if child is AudioStreamPlayer:
			child.stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print(
			"PASS: overview self-rotation, top-surface handoff to the near horizon, mode-specific drag, switch interruption, UI/focus gates and stable world state at both resolutions."
		)
	quit(0 if _failures.is_empty() else 1)


func _check_near_projection(demo: DemoScript) -> void:
	var camera: PlanetViewController = demo._view
	var screen: Vector2 = root.get_visible_rect().size
	var transform: Transform2D = demo._world.get_global_transform_with_canvas()
	var radius: float = demo._planet.radius * camera.near_surface_radius_ratio
	var center: Vector2 = transform * Vector2.ZERO
	var top: Vector2 = transform * (Vector2.UP * radius)
	var right: Vector2 = transform * (Vector2.RIGHT * radius)
	_check(
		not camera.is_overview() and is_zero_approx(demo._world.rotation),
		"restart begins in the unchanged near view"
	)
	_check(
		(
			is_equal_approx(top.y, screen.y * 0.55)
			and right.x - center.x > screen.x * 0.55
			and center.y > screen.y
		),
		"the foreground retains its 55% horizon and fills a broad band"
	)
	camera._process(10.0)
	_check(
		demo._world.get_global_transform_with_canvas().is_equal_approx(transform),
		"near view does not rotate or change its projection over time"
	)


func _check_body_hits(demo: DemoScript) -> void:
	var camera: PlanetViewController = demo._view
	var transform: Transform2D = demo._world.get_global_transform_with_canvas()
	var planet: PlanetSurface = demo._planet
	_check(
		camera.contains_planet_body(transform * Vector2.ZERO),
		"the displayed solid center is part of the body even though it is not walkable"
	)
	var includes_contours: bool = true
	for index: int in range(96):
		var angle: float = float(index) * TAU / 96.0
		var edge: Vector2 = Vector2.from_angle(angle) * planet.get_outer_radius(angle)
		includes_contours = (
			includes_contours
			and camera.contains_planet_body(transform * edge)
			and camera.contains_planet_body(transform * (edge + PlanetSurface.RIM_OFFSET))
			and camera.contains_planet_body(transform * (edge * 0.45))
		)
	_check(
		includes_contours,
		"inverse projection includes every irregular contour and lower rim in either view"
	)
	var outside: Vector2 = (
		Vector2.UP
		* (
			planet.radius * camera.overview_outer_radius_ratio
			+ camera.overview_shadow_offset
			+ 20.0
		)
	)
	_check(
		not camera.contains_planet_body(transform * outside),
		"clear sky beyond the conservative contour remains background"
	)
	_check(
		not camera.contains_planet_body(_background(demo)),
		"the input fixture uses visible blank background"
	)


func _check_overview_rotation(demo: DemoScript) -> void:
	var camera: PlanetViewController = demo._view
	var world: Node2D = demo._world
	var rotation: float = world.rotation
	_mouse_button(_background(demo), MOUSE_BUTTON_WHEEL_DOWN, true)
	camera._process(camera.transition_seconds)
	_check(
		camera.is_overview() and is_equal_approx(world.rotation, rotation),
		"one wheel step enters overview while preserving the existing rotation"
	)
	_check(
		camera.projection_root.scale.is_equal_approx(Vector2.ONE),
		"overview removes the near-view horizontal stretch"
	)
	var screen: Vector2 = root.get_visible_rect().size
	_check(
		world.get_global_transform_with_canvas().origin.distance_to(screen * 0.5) < 0.01,
		"overview centers the planet in the viewport"
	)
	demo._refresh_overview()
	demo._overview._process(0.0)
	var bubble_before: Vector2 = demo._overview.bubble_centers[0]
	var marker: Vector2 = demo.run.nests[0].position
	var marker_before: Vector2 = world.get_global_transform_with_canvas() * marker
	var world_position: Vector2 = world.position
	var world_scale: Vector2 = world.scale
	var signals_before: int = _view_changes
	var speed: float = camera.overview_rotation_speed
	_check(
		is_equal_approx(speed, 0.035),
		"the default overview rotation is a slow configurable 0.035 radians per second"
	)
	camera._process(4.0)
	demo._overview._process(0.0)
	_check(
		absf(angle_difference(rotation, world.rotation) - speed * 4.0) < 0.0001,
		"overview rotates by speed times elapsed time"
	)
	_check(
		(
			world.position == world_position
			and world.scale == world_scale
			and _view_changes == signals_before
		),
		"automatic rotation preserves placement and scale without firing full presentation refreshes"
	)
	_check(
		(world.get_global_transform_with_canvas() * marker).distance_to(marker_before) > 1.0,
		"the same world-space marker visibly follows the automatic rotation"
	)
	_check(
		demo._overview.bubble_centers[0].distance_to(bubble_before) > 1.0,
		"overview bubbles follow the rotated world using their existing process update"
	)
	rotation = world.rotation
	camera.overview_rotation_speed = 0.0
	camera._process(5.0)
	_check(
		is_equal_approx(world.rotation, rotation),
		"zero configured speed stops overview self-rotation"
	)
	camera.overview_rotation_speed = -speed
	camera._process(2.0)
	_check(
		absf(angle_difference(rotation, world.rotation) + speed * 2.0) < 0.0001,
		"a negative configured speed reverses the automatic rotation"
	)
	camera.overview_rotation_speed = speed
	var pointer: Vector2 = _background(demo)
	camera.begin_drag(pointer)
	rotation = world.rotation
	camera._process(5.0)
	_check(
		is_equal_approx(world.rotation, rotation), "holding a manual drag pauses automatic rotation"
	)
	camera.drag_to(pointer + Vector2(80.0, 0.0))
	_check(
		world.rotation > rotation,
		"rightward manual dragging retains its original positive direction"
	)
	rotation = world.rotation
	camera._process(3.0)
	_check(
		is_equal_approx(world.rotation, rotation),
		"automatic rotation does not fight an active manual movement"
	)
	camera.end_drag()
	camera._process(2.0)
	_check(
		absf(angle_difference(rotation, world.rotation) - speed * 2.0) < 0.0001,
		"releasing a manual drag resumes slow self-rotation"
	)


func _check_mode_drag_input(demo: DemoScript) -> void:
	var camera: PlanetViewController = demo._view
	var world: Node2D = demo._world
	var pointer: Vector2 = _drag_start(demo)
	var rejected: Vector2 = _planet_point(demo) if camera.is_overview() else _background(demo)
	_check(
		not demo._layout.is_over_ui(pointer) and not demo._layout.is_over_ui(rejected),
		"drag fixtures are clear of interface controls"
	)
	var rotation: float = world.rotation
	_mouse_button(rejected, MOUSE_BUTTON_RIGHT, true)
	_check(not camera.is_dragging(), "P1 rejects sky starts and P2 rejects planet starts")
	_mouse_motion(pointer, MOUSE_BUTTON_MASK_RIGHT)
	_check(
		not camera.is_dragging() and is_equal_approx(world.rotation, rotation),
		"moving into the allowed area after a rejected start remains rejected"
	)
	_mouse_button(pointer, MOUSE_BUTTON_RIGHT, false)
	_mouse_button(pointer, MOUSE_BUTTON_RIGHT, true)
	_check(camera.is_dragging(), "right press starts rotation on the P1 planet or P2 background")
	_check(demo._view_blocks_tool_until_release, "starting camera movement gates tool actions")
	_mouse_motion(pointer + Vector2(0.0, 40.0), MOUSE_BUTTON_MASK_RIGHT)
	_check(
		is_equal_approx(world.rotation, rotation),
		"vertical-only mouse movement still leaves rotation unchanged"
	)
	var marker_before: Vector2 = demo._nest_views[0].get_global_transform_with_canvas().origin
	_mouse_motion(pointer + Vector2(80.0, 40.0), MOUSE_BUTTON_MASK_RIGHT)
	_check(world.rotation > rotation, "rightward input rotates in the original direction")
	_check(
		(
			demo._nest_views[0].get_global_transform_with_canvas().origin.distance_to(marker_before)
			> 1.0
		),
		"actual nest projection follows manual rotation"
	)
	_mouse_motion(rejected, MOUSE_BUTTON_MASK_RIGHT)
	_check(camera.is_dragging(), "an accepted drag continues across the other visual region")
	var button: Button = demo._layout.get_node("%QuickPipeButton") as Button
	var button_center: Vector2 = button.get_global_rect().get_center()
	_mouse_motion(button_center, MOUSE_BUTTON_MASK_RIGHT)
	_check(camera.is_dragging(), "an active drag continues across interface controls")
	_mouse_button(button_center, MOUSE_BUTTON_RIGHT, false)
	_check(not camera.is_dragging(), "releasing over interface controls always ends the drag")
	demo._layout._hide_quick_upgrades()


func _check_ui_and_focus_gates(demo: DemoScript) -> void:
	var camera: PlanetViewController = demo._view
	for name: String in ["QuickPipeButton", "QuickNetButton", "TechnologyButton", "RestartButton"]:
		var button: Button = demo._layout.get_node("%" + name) as Button
		_mouse_button(button.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT, true)
		_check(not camera.is_dragging(), "interface button " + name + " rejects drag starts")
		_mouse_button(button.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT, false)
	demo._layout.get_node("%TechnologyButton").pressed.emit()
	_mouse_button(_drag_start(demo), MOUSE_BUTTON_RIGHT, true)
	_check(not camera.is_dragging(), "an open technology panel blocks mode-specific rotation")
	_mouse_button(_drag_start(demo), MOUSE_BUTTON_RIGHT, false)
	demo._layout.close_panels()
	_mouse_button(Vector2(-20.0, -20.0), MOUSE_BUTTON_RIGHT, true)
	_check(not camera.is_dragging(), "points outside the viewport cannot start camera movement")
	_mouse_button(Vector2(-20.0, -20.0), MOUSE_BUTTON_RIGHT, false)
	var background: Vector2 = _drag_start(demo)
	demo.get_window().focus_exited.emit()
	_mouse_button(background, MOUSE_BUTTON_RIGHT, true)
	_check(not camera.is_dragging(), "an unfocused window cannot begin a drag")
	_mouse_button(background, MOUSE_BUTTON_RIGHT, false)
	demo.get_window().focus_entered.emit()
	_mouse_button(background, MOUSE_BUTTON_RIGHT, true)
	_check(camera.is_dragging(), "the focused mode-specific region accepts a fresh drag")
	demo.get_window().focus_exited.emit()
	_check(not camera.is_dragging(), "losing focus releases an existing drag")
	_mouse_button(background, MOUSE_BUTTON_RIGHT, false)
	demo.get_window().focus_entered.emit()


func _check_overview_top_handoff(demo: DemoScript, resolution: Vector2i) -> void:
	var camera: PlanetViewController = demo._view
	var world: Node2D = demo._world
	var planet: PlanetSurface = demo._planet
	var screen: Vector2 = root.get_visible_rect().size
	var actors: Array[PrototypeSlime] = demo._slimes.duplicate()
	var nests: Array[NestView] = demo._nest_views.duplicate()
	var actor_positions: Array[Vector2] = []
	var nest_positions: Array[Vector2] = []
	for actor: PrototypeSlime in actors:
		actor_positions.append(actor.position)
	for nest: NestState in demo.run.nests:
		nest_positions.append(nest.position)
	var headings: Array[float] = [0.0, 0.8, -1.2, PI - 0.04, -PI + 0.04, PI + 0.31, -PI - 0.27]
	for source: String in ["manual", "automatic", "display_transform"]:
		for heading: float in headings:
			camera.zoom_steps(-1.0)
			camera._process(camera.transition_seconds)
			var screen_radius: float = (
				planet.radius * world.scale.x * camera.projection_root.scale.x
			)
			camera.begin_drag(Vector2.ZERO)
			camera.drag_to(Vector2((heading - world.rotation) * screen_radius, 0.0))
			camera.end_drag()
			if source == "automatic":
				var speed: float = camera.overview_rotation_speed
				camera.overview_rotation_speed = -absf(speed) if heading < 0.0 else absf(speed)
				camera._process(4.0)
				camera.overview_rotation_speed = speed
			elif source == "display_transform":
				# A displayed transform ahead of the cached angle must win at handoff.
				world.rotation += 0.41
			var overview_transform: Transform2D = world.get_global_transform_with_canvas()
			var top_direction: Vector2 = (
				(overview_transform.affine_inverse().basis_xform(Vector2.UP)).normalized()
			)
			var top_point: Vector2 = top_direction * planet.get_outer_radius(top_direction.angle())
			var left_direction: Vector2 = top_direction.rotated(-0.12)
			var right_direction: Vector2 = top_direction.rotated(0.12)
			var left_point: Vector2 = (
				left_direction * planet.get_outer_radius(left_direction.angle())
			)
			var right_point: Vector2 = (
				right_direction * planet.get_outer_radius(right_direction.angle())
			)
			var overview_top: Vector2 = overview_transform * top_point
			_check(
				(
					absf(overview_top.x - screen.x * 0.5) < 0.1
					and overview_top.y < overview_transform.origin.y
				),
				"the handoff fixture samples the actual screen-top surface ray"
			)
			_check(
				(
					(overview_transform * left_point).x < overview_top.x
					and (overview_transform * right_point).x > overview_top.x
				),
				"the overview neighbors begin on the expected left and right sides"
			)
			var screenshot_pair: bool = (
				source == "automatic"
				and is_equal_approx(heading, PI - 0.04)
				and OS.get_cmdline_user_args().has("--capture")
				and DisplayServer.get_name() != "headless"
			)
			var marker: Node2D = null
			if screenshot_pair:
				marker = _create_qa_marker(demo, top_point)
				await _capture("top_handoff_overview", resolution)
			camera.begin_drag(_background(demo))
			_mouse_button(_background(demo), MOUSE_BUTTON_WHEEL_UP, true)
			camera._process(camera.transition_seconds)
			_check(
				not camera.is_overview() and not camera.is_dragging(),
				"entering near view ends the previous drag"
			)
			var near_transform: Transform2D = world.get_global_transform_with_canvas()
			var near_top: Vector2 = near_transform * top_point
			var nominal_radius: float = planet.radius * camera.near_surface_radius_ratio
			var near_scale: float = world.scale.y
			var expected_horizon: float = (
				screen.y * camera.near_horizon_ratio
				+ near_scale * (nominal_radius - top_point.length())
			)
			_check(
				(
					absf(near_top.x - screen.x * 0.5) < 0.1
					and absf(near_top.y - expected_horizon) < 0.1
				),
				(
					"the current overview top becomes the near horizontal center on its unchanged irregular horizon: %s %.3f"
					% [source, heading]
				)
			)
			_check(
				absf(near_top.y - screen.y * 0.5) > screen.y * 0.025,
				"handoff preserves the existing horizon instead of centering the ground vertically"
			)
			_check(
				(
					(near_transform * left_point).x < near_top.x
					and (near_transform * right_point).x > near_top.x
				),
				"near-view neighbors retain their left-to-right ordering across the angle wrap"
			)
			_mouse_motion(_background(demo) + Vector2(120.0, 0.0), MOUSE_BUTTON_MASK_RIGHT)
			camera.drag_to(Vector2(400.0, 200.0))
			camera._process(2.0)
			_check(
				world.get_global_transform_with_canvas().is_equal_approx(near_transform),
				"old drag motion and automatic ticks cannot change the chosen near heading"
			)
			_mouse_button(_background(demo), MOUSE_BUTTON_RIGHT, false)
			if screenshot_pair:
				(marker.get_child(0) as Node2D).transform = (
					SurfaceProjection.get_visual_compensation(marker)
				)
				_check(
					marker.position == top_point,
					"the QA marker keeps the same world point in both screenshots"
				)
				await _capture("top_handoff_near", resolution)
				var pixel_scale: Vector2 = Vector2(resolution) / screen
				print(
					"TOP_HANDOFF resolution=",
					resolution,
					" local_point=",
					top_point,
					" overview_pixel=",
					overview_top * pixel_scale,
					" near_pixel=",
					near_top * pixel_scale,
					" marker=A only-in-test"
				)
				marker.free()
	_check(
		demo._slimes == actors and demo._nest_views == nests,
		"every heading preserves the existing entity identities and order"
	)
	for index: int in range(actors.size()):
		_check(
			actors[index].position == actor_positions[index],
			"handoff never rearranges living world-space actors"
		)
	for index: int in range(nest_positions.size()):
		_check(
			demo.run.nests[index].position == nest_positions[index],
			"handoff never rearranges nest positions"
		)


func _create_qa_marker(demo: DemoScript, point: Vector2) -> Node2D:
	# This flag exists only in the test scene and is removed after the image pair.
	var marker: Node2D = Node2D.new()
	marker.name = "QASurfacePointA"
	marker.position = point
	marker.rotation = -demo._world.rotation
	marker.z_index = 100
	demo._world.add_child(marker)
	var visual: Node2D = Node2D.new()
	marker.add_child(visual)
	visual.transform = SurfaceProjection.get_visual_compensation(marker)
	var pole: Line2D = Line2D.new()
	pole.points = PackedVector2Array([Vector2.ZERO, Vector2(0.0, -36.0)])
	pole.width = 3.0
	pole.default_color = Color("3c3324")
	visual.add_child(pole)
	var flag: Polygon2D = Polygon2D.new()
	flag.polygon = PackedVector2Array(
		[Vector2(-1.0, -36.0), Vector2(25.0, -36.0), Vector2(25.0, -12.0), Vector2(-1.0, -12.0)]
	)
	flag.color = Color("ffb541")
	visual.add_child(flag)
	var label: Label = Label.new()
	label.text = "A"
	label.position = Vector2(5.0, -38.0)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("3c3324"))
	visual.add_child(label)
	return marker


func _check_restart(demo: DemoScript) -> void:
	var background: Vector2 = _drag_start(demo)
	_mouse_button(background, MOUSE_BUTTON_RIGHT, true)
	_check(demo._view.is_dragging(), "restart fixture has an active mode-specific drag")
	demo.get_node("%RestartButton").pressed.emit()
	_check(
		(
			not demo._view.is_overview()
			and not demo._view.is_dragging()
			and is_zero_approx(demo._world.rotation)
		),
		"restart returns to the original near view, zero angle and released drag"
	)
	_mouse_button(background, MOUSE_BUTTON_RIGHT, false)


func _background(_demo: DemoScript) -> Vector2:
	return Vector2(16.0, root.get_visible_rect().size.y * 0.3)


func _planet_point(demo: DemoScript) -> Vector2:
	var up: Vector2 = Vector2.UP.rotated(-demo._world.rotation)
	return demo._world.get_global_transform_with_canvas() * (up * demo._planet.radius * 0.8)


func _drag_start(demo: DemoScript) -> Vector2:
	return _background(demo) if demo._view.is_overview() else _planet_point(demo)


func _mouse_button(position: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	if button == MOUSE_BUTTON_RIGHT and pressed:
		event.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(event, true)


func _mouse_motion(position: Vector2, mask: MouseButtonMask) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = mask
	root.push_input(event, true)


func _settle() -> void:
	for frame: int in range(4):
		await process_frame


func _capture(stem: String, resolution: Vector2i) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless":
		return
	var demo: DemoScript = current_scene as DemoScript
	for actor: PrototypeSlime in demo._slimes:
		actor._process(0.0)
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(
		"res://artifacts/%s_%dx%d.png" % [stem, resolution.x, resolution.y]
	)
	_check(result == OK, "saved the current projected view")


func _on_view_changed() -> void:
	_view_changes += 1


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
