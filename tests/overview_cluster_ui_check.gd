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
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._layout.set_process(false)
	await _settle()
	await _check_timers_and_stages(demo)
	for node: Node in demo.get_node("Audio").get_children():
		if node is AudioStreamPlayer:
			node.stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print(
			"PASS: local monster clusters, bounded placement, UI layer order and lightweight timers"
		)
	quit(0 if _failures.is_empty() else 1)


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
	demo.run.settings.nest_spawn_cooldown_seconds = 0.0
	demo._site_random.seed = 41129
	demo.run._random.seed = 7817
	demo.run._advance_nest_roll(demo.run._nest_initial_delay_remaining)
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
		demo._view.zoom_steps(-1.0, false)
		demo._drive_tool(0.0, Vector2.ZERO, false)
		demo._refresh_overview()
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
		demo._view.zoom_steps(1.0, false)
		_check(
			not demo._region_root.visible and demo._nests.visible and demo._slime_root.visible,
			"P1 restores nest and monster models while legacy region patches remain hidden"
		)


func _check_bubble_positions(demo: DemoScript) -> void:
	var overview: OverviewEcology = demo._overview
	_check((demo.get_node("HUD") as CanvasLayer).layer > 0, "HUD layers cover distribution bubbles")
	var screen: Rect2 = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for bubble: Node2D in overview.bubbles:
		var radius: float = bubble.radius
		_check(
			screen.encloses(overview._bubble_rect(bubble.position, radius)),
			"local bubbles stay in the viewport"
		)
		_check(
			absf(bubble.offset.y) <= overview.maximum_nudge_radii + 0.001,
			"bubbles retain their distribution bearing"
		)


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
