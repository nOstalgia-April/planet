extends SceneTree

const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")

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
	await process_frame
	demo.set_process(false)
	for _frame: int in range(5):
		await process_frame
	var layout: DiskDemoLayout = demo.get_node("%Interface") as DiskDemoLayout
	_check_shop_fit(layout, "initial layout settles without a second manual layout")
	demo.run.candy = 1400
	demo.run.pipe_level = 1
	demo.run.net_level = 2
	demo.run.economy_changed.emit()
	for _frame: int in range(5):
		await process_frame
	_check_shop_fit(layout, "updated HUD keeps controls inside their cards")
	var tool_stats: Label = demo.get_node("%ToolStatsLabel") as Label
	tool_stats.text = "处理 0.60 秒 / 只\n本趟 +200000 糖果"
	for _frame: int in range(5):
		await process_frame
	_check_shop_fit(layout, "two-line pending candy display preserves shop layout")
	_check(tool_stats.get_line_count() == 2, "pending candy stays on its own line")
	demo._select_nest(1)
	for _frame: int in range(5):
		await process_frame
	_check_shop_fit(layout, "selected nest stock and two-line upgrade benefit fit their card")
	var nest_benefit: Label = demo.get_node("%NestBenefitLabel") as Label
	_check(nest_benefit.get_line_count() == 2, "spawn rate and stock cap each fit one line")
	var world: Node2D = demo.get_node("World") as Node2D
	_check(world.scale.is_equal_approx(layout.scale), "world follows interface scale")
	_check(not demo.has_node("Flight"), "flight layer has been removed")
	for viewport_size: Vector2 in [Vector2(1920.0, 1080.0), Vector2(1280.0, 800.0)]:
		var is_pipe: bool = viewport_size.x == 1920.0
		demo.get_node("%PipeToolButton" if is_pipe else "%NetToolButton").pressed.emit()
		if not is_pipe:
			demo.run.net_cooldown_remaining = 3.2
			demo.run.economy_changed.emit()
		var level_label: Label = demo.get_node("%ToolLevelLabel") as Label
		var upgrade_button: Button = demo.get_node("%ToolButton") as Button
		_check(
			level_label.text == ("Lv. 2" if is_pipe else "Lv. 3"),
			"current tool displays its own technology level"
		)
		_check(
			upgrade_button.text.begins_with("速度升级" if is_pipe else "容量升级"),
			"upgrade button follows current tool"
		)
		_check(
			tool_stats.text.contains("处理" if is_pipe else "冷却 3.2"),
			"current tool has its own status display"
		)
		demo._drive_tool(0.0, Vector2.LEFT * 240.0, false)
		var viewport_units: Vector2 = viewport_size
		var play_rect: Rect2
		if rendered:
			root.size = Vector2i(viewport_size)
			for _frame: int in range(5):
				await process_frame
			viewport_units = root.get_visible_rect().size
			play_rect = Rect2(
				Vector2(48.0, 112.0) * layout.scale,
				Vector2(layout.size.x - 456.0, layout.size.y - 208.0) * layout.scale
			)
			_check(
				layout.get_global_rect().size.is_equal_approx(viewport_units),
				"automatic resize fits logical viewport"
			)
			_check(
				world.scale.is_equal_approx(layout.scale), "world scale follows automatic resize"
			)
			await RenderingServer.frame_post_draw
			if "--capture" in OS.get_cmdline_user_args():
				root.get_texture().get_image().save_png(
					(
						"res://artifacts/layout_%dx%d.png"
						% [int(viewport_size.x), int(viewport_size.y)]
					)
				)
		else:
			play_rect = layout.apply_layout(viewport_units)
			await process_frame
			await process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, viewport_units)
		var tool_card: Control = layout.get_node("ToolCard") as Control
		var nest_card: Control = layout.get_node("NestCard") as Control
		var restart: Button = demo.get_node("%RestartButton") as Button
		_check(screen.encloses(play_rect), "play area fits viewport " + str(viewport_size))
		_check(
			not play_rect.intersects(tool_card.get_global_rect()),
			"tool card leaves play area clear"
		)
		_check(
			not play_rect.intersects(nest_card.get_global_rect()),
			"nest card leaves play area clear"
		)
		_check(
			not tool_card.get_global_rect().intersects(nest_card.get_global_rect()),
			"shop cards do not overlap"
		)
		_check(
			not nest_card.get_global_rect().intersects(restart.get_global_rect()),
			"restart stays below cards"
		)
		for button_name: String in [
			"PipeToolButton", "NetToolButton", "ToolButton", "NestButton", "RestartButton"
		]:
			var button: Button = demo.get_node("%" + button_name) as Button
			_check(screen.encloses(button.get_global_rect()), button_name + " is inside viewport")
			_check(
				button.get_global_rect().size.x >= 70.0 and button.get_global_rect().size.y >= 40.0,
				button_name + " has a usable click area"
			)
			if button_name != "RestartButton":
				var card: Control = nest_card if button_name == "NestButton" else tool_card
				_check(
					card.get_global_rect().encloses(button.get_global_rect()),
					button_name + " fits inside its shop card"
				)
			_check(
				layout.is_over_ui(button.get_global_rect().get_center()),
				button_name + " blocks world interaction"
			)
		_check(
			not layout.is_over_ui(play_rect.get_center()), "transparent HUD permits play area input"
		)
		var completion: Control = demo.get_node("%Completion") as Control
		completion.show()
		await process_frame
		_check(layout.is_over_ui(play_rect.get_center()), "completion blocks world input")
		_check(
			screen.grow(0.5).encloses(completion.get_global_rect()),
			"completion covers viewport without overflowing"
		)
		_check(
			completion.get_global_rect().size.distance_to(viewport_units) <= 0.5,
			"completion fills the viewport"
		)
		completion.hide()
	if _failures == 0:
		print("PASS: 1920x1080 and 1280x800 layout, tool switching buttons and world input areas")
	quit(0 if _failures == 0 else 1)


func _check_shop_fit(layout: DiskDemoLayout, description: String) -> void:
	var tool_card: Control = layout.get_node("ToolCard") as Control
	var nest_card: Control = layout.get_node("NestCard") as Control
	var restart: Control = layout.get_node("RestartButton") as Control
	_check(not tool_card.get_global_rect().intersects(nest_card.get_global_rect()), description)
	_check(not nest_card.get_global_rect().intersects(restart.get_global_rect()), description)
	for card: Control in [tool_card, nest_card]:
		var button_name: String = "ToolButton" if card == tool_card else "NestButton"
		var button: Control = card.get_node("Content/" + button_name) as Control
		_check(card.get_global_rect().encloses(button.get_global_rect()), description)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
