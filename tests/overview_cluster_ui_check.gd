extends SceneTree

const PageScript = preload("res://scripts/ui/technology_page.gd")
const DemoScript = preload("res://scripts/disk_demo.gd")
const NodeScript = preload("res://scripts/ui/technology_node.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const OverviewScene: PackedScene = preload("res://scenes/world/overview_ecology.tscn")
const PlanetScene: PackedScene = preload("res://scenes/world/planet_surface.tscn")

var _failures: Array[String] = []
var _capture: bool = false


func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_run_checks.call_deferred()


func _run_checks() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	await _check_clusters()
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._layout.set_process(false)
	await _settle()
	await _check_timers_and_stages(demo)
	for node: Node in demo.get_node("Audio").get_children():
		(node as AudioStreamPlayer).stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print(
			"PASS: surface summaries, exterior species bubbles, stable clusters, HUD avoidance and lightweight timers"
		)
	quit(0 if _failures.is_empty() else 1)


func _check_clusters() -> void:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var world: Node2D = Node2D.new()
	container.add_child(world)
	world.position = root.get_visible_rect().size * 0.5
	var surface: PlanetSurface = PlanetScene.instantiate() as PlanetSurface
	world.add_child(surface)
	var overview: OverviewEcology = OverviewScene.instantiate() as OverviewEcology
	container.add_child(overview)
	overview.configure(surface, world)
	var nests: Array[NestState] = [
		_nest(Vector2(-160, -150), NestState.Species.SLIME, 1),
		_nest(Vector2(-130, -140), NestState.Species.SLIME, 1),
		_nest(Vector2(120, 110), NestState.Species.SLIME, 90),
		_nest(Vector2(20, 0), NestState.Species.MUCUS, 3),
		_nest(Vector2(50, 20), NestState.Species.MUCUS, 4)
	]
	overview.update_nest_clusters(nests)
	overview.update_ecology(92, 7, true, root.get_visible_rect().size)
	overview.set_process(false)
	overview._process(2.0)
	_check(
		overview.cluster_regions == Vector2i(0, 4),
		"the busiest nest regions include a real center region"
	)
	_check(
		(
			overview.cluster_anchors[0].normalized().is_equal_approx(Vector2(-1, -1).normalized())
			and is_equal_approx(
				overview.cluster_anchors[0].length(), surface.get_outer_radius(-PI * 0.75)
			)
		),
		"the busiest group projects its mean direction to the outer surface"
	)
	_check(
		overview.population_counts == Vector2i(92, 7),
		"bubble labels retain global individual counts"
	)
	nests.append(_nest(Vector2(130, 140), NestState.Species.SLIME, 100))
	overview.update_nest_clusters(nests)
	_check(overview.cluster_regions.x == 0, "equal nest counts retain the previous region")
	nests[1].position = Vector2(140, 160)
	overview.update_nest_clusters(nests)
	_check(
		overview.cluster_regions.x == 8, "a strictly larger group moves the bubble to its region"
	)
	var anchor: Vector2 = overview.cluster_anchors[0]
	world.rotation = 0.4
	overview._process(0.0)
	var projected: Vector2 = world.get_global_transform_with_canvas() * anchor
	_check(
		(
			(projected - overview._planet_center).normalized().dot(
				(overview.bubble_centers[0] - overview._planet_center).normalized()
			)
			> 0.7
		),
		"the bubble stays near its rotated cluster direction"
	)
	_check(
		overview._bubble_is_outside_surface(overview.bubble_centers[0], overview.bubble_radii[0]),
		"the bubble and count sit outside the planet surface"
	)
	overview.update_ecology(150, 2, true, root.get_visible_rect().size)
	_check(
		overview.cluster_anchors[0] == anchor,
		"individual population changes do not choose another region"
	)
	current_scene = null
	container.queue_free()
	await process_frame


func _check_timers_and_stages(demo: DemoScript) -> void:
	demo.run.candy = 100000
	demo.run.upgrade_pipe()
	demo.run.purchase_technology("combo")
	demo.run.purchase_technology("net")
	demo._layout.refresh_progression(demo.run)
	await _settle()
	var page: PageScript = demo._layout._technology
	_check(
		page._max_level("pipe") == 7, "the single speed node includes all seven configured levels"
	)
	demo.run.pipe_level = 4
	page.select_node("pipe")
	_check(
		page._detail_effect.text.contains("0.135"),
		"precision tier preserves the actual capture time"
	)
	var first_stage: NodeScript = page._nodes["pipe"]
	var style: StyleBox = first_stage.get_theme_stylebox("normal")
	demo.run.combo_count = demo.run.settings.combo_target
	demo.run.combo_remaining = 3.0
	demo.run.net_cooldown_remaining = 6.0
	demo._layout.refresh_timers(demo.run)
	_check(
		demo._layout._combo_label.text.contains("3.0 秒") and demo._layout._combo_timer.value == 3.0,
		"the combo buff exposes its actual remaining seconds and full timer bar"
	)
	for tick: int in range(36):
		demo.run.combo_remaining = maxf(0.0, 3.0 - float(tick) * 0.1)
		demo.run.net_cooldown_remaining = 6.0 - float(tick) * 0.1
		demo._layout.refresh_timers(demo.run)
	_check(
		page._nodes["pipe"] == first_stage and first_stage.get_theme_stylebox("normal") == style,
		"timer ticks preserve technology nodes and style resources"
	)
	_check(
		not demo._layout._shop_layout_queued, "timer ticks do not schedule full technology layout"
	)
	_check(
		demo._layout._net_timer_label.text == "冷却 2.5 秒",
		"the net shows its live remaining cooldown"
	)
	demo.run.combo_count = 0
	demo.run.combo_remaining = 0.0
	demo.run.net_cooldown_remaining = 0.0
	demo._layout.refresh_timers(demo.run)
	_check(demo._layout._combo_timer.value == 0.0, "an expired streak empties its decay bar")
	_check(
		demo._layout._net_timer_label.text == "就绪 · 5 只",
		"a ready net shows its capacity and availability"
	)
	demo.run.settings = demo.run.settings.duplicate(true) as PrototypeSettings
	demo.run.settings.nest_roll_chance_min = 1.0
	demo.run.settings.nest_roll_chance_max = 1.0
	demo._site_random.seed = 41129
	demo.run._random.seed = 7817
	for _roll: int in range(8):
		demo.run._advance_nest_roll(demo.run.settings.nest_roll_interval)
	demo.run.advance(4.0)
	for actor: PrototypeSlime in demo._slimes:
		actor.set_process(false)
	demo._refresh_hud()
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle()
		demo._layout._show_technology()
		await _settle()
		var card: Control = demo._layout._technology
		var screen: Rect2 = Rect2(Vector2.ZERO, root.get_visible_rect().size)
		_check(screen.encloses(card.get_global_rect()), "the technology page fits the viewport")
		for stage: NodeScript in page._nodes.values():
			_check(
				card.get_global_rect().encloses(stage.get_global_rect()),
				"every pipe upgrade remains inside the technology card"
			)
		if _capture:
			await _save("ui_seven_tiers_%dx%d.png" % [resolution.x, resolution.y])
		demo._layout.close_panels()
		demo.run.combo_count = 5
		demo.run.combo_remaining = 2.3
		demo.run.net_cooldown_remaining = 4.7
		demo._layout.refresh_timers(demo.run)
		demo._view.zoom_steps(-1.0)
		demo._drive_tool(0.0, Vector2.ZERO, false)
		demo._overview.update_nest_clusters(demo.run.nests)
		demo._overview.update_ecology(
			demo.run.get_species_population(NestState.Species.SLIME),
			demo.run.get_species_population(NestState.Species.MUCUS),
			true,
			root.get_visible_rect().size
		)
		demo._overview._process(2.0)
		await _settle()
		_check(
			not demo._region_root.visible and not demo._pipe.visible,
			"P2 hides real nest patches and collection tools"
		)
		for _step: int in range(16):
			_check_bubble_positions(demo)
			var screen_radius: float = demo._planet.radius * demo._world.scale.x
			demo._view.begin_drag(Vector2.ZERO)
			demo._view.drag_to(Vector2(screen_radius * TAU / 16.0, 0.0))
			demo._view.end_drag()
			demo._overview._process(0.0)
		if _capture:
			await _save("overview_surface_summary_%dx%d.png" % [resolution.x, resolution.y])
		demo._view.zoom_steps(1.0)
		_check(demo._region_root.visible, "P1 restores the real wide-crust nest patches")


func _check_bubble_positions(demo: DemoScript) -> void:
	var screen: Rect2 = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for species: int in range(2):
		var center: Vector2 = demo._overview.bubble_centers[species]
		var radius: float = demo._overview.bubble_radii[species]
		var footprint: Rect2 = demo._overview._bubble_rect(center, radius)
		_check(screen.encloses(footprint), "cluster bubbles and counts remain inside the viewport")
		_check(
			demo._overview._bubble_is_outside_surface(center, radius),
			"cluster bubbles and counts remain outside the planet"
		)
		for obstacle: Rect2 in demo._layout.get_overview_obstacles():
			_check(
				not footprint.intersects(obstacle), "cluster bubbles avoid the current HUD panels"
			)
		if species == 1:
			var first: Rect2 = demo._overview._bubble_rect(
				demo._overview.bubble_centers[0], demo._overview.bubble_radii[0]
			)
			_check(not footprint.intersects(first), "the two species summaries stay separate")


func _nest(position: Vector2, species: NestState.Species, alive: int) -> NestState:
	var nest: NestState = NestState.new()
	nest.position = position
	nest.species = species
	nest.alive_slimes = alive
	return nest


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
