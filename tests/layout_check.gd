extends SceneTree

const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")
const PlanetViewController = preload("res://scripts/planet_view_controller.gd")

var _failures: int = 0


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var rendered: bool = DisplayServer.get_name() != "headless"
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1920, 1080)
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	await _wait_for_layout()
	demo.set_process(false)
	var layout: DiskDemoLayout = demo.get_node("%Interface") as DiskDemoLayout
	var camera: PlanetViewController = (
		demo.get_node("%PlanetViewController") as PlanetViewController
	)
	camera.set_process(false)
	var world: Node2D = demo.get_node("World") as Node2D
	var planet: PlanetSurface = demo.get_node("%PlanetSurface") as PlanetSurface
	var overview_texture: Texture2D = planet.overview_texture
	_check(
		(
			overview_texture != null
			and overview_texture.resource_path == "res://assets/planet_overview/gray_planet.png"
		),
		"the demo scene loads its separate gray globe texture for P2"
	)
	var technology: Control = demo.get_node("%Technology") as Control
	var tool_card: Control = demo.get_node("%ToolCard") as Control
	var nest_card: Control = layout.get_node("NestCard") as Control
	for viewport_size: Vector2 in [Vector2(1920.0, 1080.0), Vector2(1280.0, 800.0)]:
		var viewport_units: Vector2 = viewport_size
		if rendered:
			root.size = Vector2i(viewport_size)
			await _wait_for_layout()
			viewport_units = root.get_visible_rect().size
		var play_rect: Rect2 = layout.apply_layout(viewport_units)
		camera.configure(play_rect, planet.radius)
		demo.restart_run()
		var screen: Rect2 = Rect2(Vector2.ZERO, viewport_units)
		_check(
			not technology.visible and not nest_card.visible and not layout.is_technology_open(),
			"new run leaves technology and nest details closed"
		)
		_check(
			(
				screen.encloses(play_rect)
				and play_rect.get_center().distance_to(viewport_units * 0.5) < 0.5
			),
			"play area is symmetric around the screen center at " + str(viewport_size)
		)
		_check(
			(
				(
					absf(world.get_global_transform_with_canvas().origin.x - viewport_units.x * 0.5)
					< 0.5
				)
				and is_equal_approx(camera.zoom_amount, 1.0)
			),
			"P1 planet remains horizontally centered after resize"
		)
		_check(
			is_equal_approx(planet.near_crust_width_ratio, 0.34),
			"the centered P1 scene uses its reference crust proportion"
		)
		_check(
			camera.projection_root == demo,
			"the main scene injects its projection root into the view controller"
		)
		_check_near_projection(camera, world, planet, viewport_units)
		_check(
			(
				not layout.is_over_ui(tool_card.get_global_rect().get_center())
				and not layout.is_over_ui(nest_card.get_global_rect().get_center())
			),
			"hidden panels leave their screen regions available for world input"
		)
		for button_name: String in [
			"QuickPipeButton", "QuickNetButton", "TechnologyButton", "RestartButton"
		]:
			var button: Button = demo.get_node("%" + button_name) as Button
			_check(
				screen.encloses(button.get_global_rect()), button_name + " fits inside the screen"
			)
			_check(
				(
					button.size.x >= 70.0
					and button.size.y >= 40.0
					and layout.is_over_ui(button.get_global_rect().get_center())
				),
				button_name + " has a usable click area that blocks world input"
			)
		demo.get_node("%QuickNetButton").pressed.emit()
		_check(
			demo._active_tool == DemoScript.ToolMode.NET, "quick net works with technology closed"
		)
		demo.get_node("%QuickPipeButton").pressed.emit()
		_check(
			demo._active_tool == DemoScript.ToolMode.PIPE, "quick pipe works with technology closed"
		)
		camera.zoom_steps(-10.0, false)
		_check(
			is_equal_approx(camera.zoom_amount, 0.0) and is_equal_approx(camera.target_zoom, 0.0),
			"overview selection is immediate with no interpolated layout"
		)
		_check(
			world.get_global_transform_with_canvas().origin.distance_to(viewport_units * 0.5) < 0.5,
			"P2 planet is centered on the full screen at " + str(viewport_size)
		)
		_check(
			camera.projection_root.scale.is_equal_approx(Vector2.ONE),
			"P2 restores an unstretched overview projection"
		)
		_check(
			not planet._near_view and planet.overview_texture == overview_texture,
			"switching to P2 retains the configured globe texture on the existing surface"
		)
		for nest: NestView in demo._nest_views:
			_check(
				screen.encloses(nest.get_hover_rect()),
				"P2 includes the outer nest visuals in the screen"
			)
		camera.reset_view()
		_check(
			planet._near_view and planet.overview_texture == overview_texture,
			"returning to P1 retains the overview texture while restoring the near ground"
		)
		var closed_transform: Transform2D = world.get_global_transform_with_canvas()
		demo.run.candy = 1400
		demo.run.pipe_level = 1
		demo.run.net_level = 2
		demo.run.economy_changed.emit()
		demo.get_node("%TechnologyButton").pressed.emit()
		await _wait_for_layout()
		_check(
			(
				technology.visible
				and layout.is_technology_open()
				and technology.get_global_rect().size.distance_to(viewport_units) < 0.5
			),
			"technology entrance opens a full screen upgrade modal"
		)
		_check(
			layout.is_over_ui(play_rect.position + Vector2(10.0, 10.0)),
			"technology blocks camera and tools across the shaded screen"
		)
		_check_card_fit(tool_card, screen, "ToolButton", "CloseTechnologyButton")
		var tool_stats: Label = demo.get_node("%ToolStatsLabel") as Label
		_check(
			tool_stats.get_line_count() == 2,
			"current and next technology effects each fit one line"
		)
		for is_pipe: bool in [true, false]:
			demo.get_node("%PipeToolButton" if is_pipe else "%NetToolButton").pressed.emit()
			var button: Button = demo.get_node("%ToolButton") as Button
			var level: int = demo.run.pipe_level if is_pipe else demo.run.net_level
			var cost: int = (
				demo.run.get_pipe_upgrade_cost() if is_pipe else demo.run.get_net_upgrade_cost()
			)
			var wallet: int = demo.run.candy
			_check(
				(
					(
						tool_stats.text.contains("%.2f" % demo.run.get_pipe_capture_seconds())
						and tool_stats.text.contains(
							"%.2f" % demo.run.settings.pipe_capture_seconds[level + 1]
						)
					)
					if is_pipe
					else (
						tool_stats.text.contains(str(demo.run.get_net_capacity()))
						and tool_stats.text.contains(
							str(demo.run.settings.net_capacities[level + 1])
						)
					)
				),
				"technology shows its current and next rule values"
			)
			_check(not button.disabled and cost > 0, "technology offers a funded legal upgrade")
			button.pressed.emit()
			_check(
				(
					(demo.run.pipe_level if is_pipe else demo.run.net_level) == level + 1
					and demo.run.candy == wallet - cost
				),
				"technology uses the existing tool purchase rules"
			)
		_escape()
		_check(not technology.visible, "Escape closes technology")
		demo.get_node("%TechnologyButton").pressed.emit()
		_click(demo.get_node("%CloseTechnologyButton") as Button)
		_check(not technology.visible, "close button closes technology")
		_check(
			demo._view_blocks_tool_until_release,
			"closing a panel gates the world tool until release"
		)
		_check_shade_close(demo, world, planet)
		demo._select_nest(1)
		await _wait_for_layout()
		_check(
			nest_card.visible and not technology.visible,
			"selecting a nest opens only its local detail panel"
		)
		_check(
			(
				layout.is_over_ui(nest_card.get_global_rect().get_center())
				and not layout.is_over_ui(play_rect.position + Vector2(10.0, 10.0))
			),
			"nest details block their card while allowing background interaction"
		)
		_check_card_fit(nest_card, screen, "NestButton", "CloseNestButton")
		var benefit: Label = demo.get_node("%NestBenefitLabel") as Label
		_check(benefit.get_line_count() == 2, "nest spawn rate and stock limit each fit one line")
		_click(demo.get_node("%CloseNestButton") as Button)
		_check(not nest_card.visible, "close button closes nest details")
		demo._select_nest(1)
		_escape()
		_check(not nest_card.visible, "Escape also closes nest details")
		_check(
			world.get_global_transform_with_canvas().is_equal_approx(closed_transform),
			"opening and closing panels never shifts the planet view"
		)
		var completion: Control = demo.get_node("%Completion") as Control
		completion.show()
		await process_frame
		_check(
			(
				layout.is_over_ui(play_rect.get_center())
				and completion.get_global_rect().size.distance_to(viewport_units) < 0.5
			),
			"completion still fills the screen and blocks world input"
		)
		completion.hide()
	for child: Node in demo.get_node("Audio").get_children():
		if child is AudioStreamPlayer:
			child.stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: centered P1/P2, technology and nest panels, upgrades and quick tools at both sizes"
		)
	quit(0 if _failures == 0 else 1)


func _check_near_projection(
	camera: PlanetViewController, world: Node2D, planet: PlanetSurface, viewport_size: Vector2
) -> void:
	_check(
		(
			camera.projection_root.scale.is_equal_approx(Vector2(1.65, 1.0))
			and is_equal_approx(world.scale.x, world.scale.y)
		),
		"P1 widens the screen projection while retaining a uniform logical world scale"
	)
	var transform: Transform2D = world.get_global_transform_with_canvas()
	var outline: PackedVector2Array = PackedVector2Array()
	var minimum: Vector2 = Vector2(INF, INF)
	var maximum: Vector2 = Vector2(-INF, -INF)
	for index: int in range(1024):
		var angle: float = float(index) * TAU / 1024.0
		var point: Vector2 = (
			transform * (Vector2.from_angle(angle) * planet.get_outer_radius(angle))
		)
		outline.append(point)
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var horizontal_radius: float = (maximum.x - minimum.x) * 0.5
	var vertical_radius: float = (maximum.y - minimum.y) * 0.5
	_check(
		horizontal_radius >= vertical_radius * 1.5,
		"P1 projects a broad ellipse instead of a circular arc"
	)
	_check(
		absf(minimum.y - viewport_size.y * 0.431) < viewport_size.y * 0.015,
		"the rear skyline crown stays at the reference 43.1 percent screen height"
	)
	for width_ratio: float in [0.15, 0.85]:
		var target_x: float = viewport_size.x * width_ratio
		var sample: Vector2 = Vector2(INF, INF)
		var minimum_x_distance: float = INF
		for point: Vector2 in outline:
			if point.y >= transform.origin.y:
				continue
			var x_distance: float = absf(point.x - target_x)
			if x_distance < minimum_x_distance:
				minimum_x_distance = x_distance
				sample = point
		_check(
			(
				minimum_x_distance < viewport_size.x * 0.005
				and sample.y >= minimum.y
				and sample.y - minimum.y < viewport_size.y * 0.25
			),
			(
				"the rear skyline remains shallow at "
				+ str(int(width_ratio * 100.0))
				+ " percent screen width"
			)
		)


func _check_card_fit(
	card: Control, screen: Rect2, upgrade_name: String, close_name: String
) -> void:
	var upgrade: Button = card.get_node("%" + upgrade_name) as Button
	var close: Button = card.get_node("%" + close_name) as Button
	_check(screen.encloses(card.get_global_rect()), str(card.name) + " fits inside the screen")
	_check(
		(
			card.get_global_rect().encloses(upgrade.get_global_rect())
			and card.get_global_rect().encloses(close.get_global_rect())
		),
		str(card.name) + " contains its upgrade and close controls"
	)
	var header: Control = card.get_node("Content/Header") as Control
	for child: Control in header.get_children():
		_check(
			header.get_global_rect().encloses(child.get_global_rect()),
			"header controls fit their row"
		)
	_check(
		not (header.get_child(0) as Control).get_global_rect().intersects(close.get_global_rect()),
		"panel title and close button do not overlap"
	)


func _check_shade_close(demo: DemoScript, world: Node2D, planet: PlanetSurface) -> void:
	demo._select_tool(DemoScript.ToolMode.NET)
	demo.get_node("%TechnologyButton").pressed.emit()
	var pointer: Vector2 = (
		world.get_global_transform_with_canvas() * (Vector2.UP.rotated(-0.55) * planet.radius)
	)
	var card: Control = demo.get_node("%ToolCard") as Control
	_check(
		not card.get_global_rect().has_point(pointer), "shade close clicks outside the tool card"
	)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = pointer
	event.global_position = pointer
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	_check(
		(
			not demo._layout.is_technology_open()
			and demo._view_blocks_tool_until_release
			and demo._net_phase == DemoScript.NetPhase.IDLE
			and demo.run.can_cast_net()
		),
		"shade closing consumes its click and leaves the tool gated"
	)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	root.push_input(event, true)


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func _escape() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)


func _wait_for_layout() -> void:
	for _frame: int in range(5):
		await process_frame


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
