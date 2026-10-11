extends Node

const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")
const NodeScript = preload("res://scripts/ui/technology_node.gd")
const InteractivePageScript = preload("res://scripts/ui/interactive_technology_page.gd")

var _failures: int = 0
@onready var root: Window = get_tree().root


func _ready() -> void:
	_check_game.call_deferred()


func _check_game() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	demo.set_process(false)
	await _settle()
	await _check_game_navigation(demo)
	demo.run.candy = 400
	demo.run.economy_changed.emit()
	await _click(demo._layout._technology_button)
	var page: InteractivePageScript = demo._layout._technology as InteractivePageScript
	page.select_node("net_unlock")
	await _click(page.purchase)
	_check(not demo.run.net_unlocked and demo.run.candy == 400, "locked research preserves wallet")
	page.select_node("pipe")
	await _click(page.purchase)
	_check(
		(
			demo.run.pipe_level == 1
			and demo.run.candy == 400 - demo.run.settings.pipe_upgrade_costs[0]
		),
		"game buys real speed upgrade"
	)
	page.select_node("net_unlock")
	await _click(page.purchase)
	_check(demo.run.net_unlocked, "game unlocks capture tool")
	page.select_node("cultivation")
	await _click(page.purchase)
	_check(demo.run.governance_level == 1, "game buys cultivation")
	page.select_node("giant")
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle()
		_check_layout(page)
		await RenderingServer.frame_post_draw
		_check(
			(
				root.get_texture().get_image().save_png(
					(
						"res://artifacts/game_upward_technology_%dx%d.png"
						% [resolution.x, resolution.y]
					)
				)
				== OK
			),
			"game screenshot saved"
		)
	var before: int = demo.run.candy
	var cost: int = demo.run.get_technology_cost("giant")
	await _click(page.purchase)
	_check(
		demo.run.giant_unlocked and demo.run.candy == before - cost,
		"global giant research applies to game"
	)
	await _click(page.purchase)
	_check(demo.run.candy == before - cost, "global research cannot charge twice")
	await _click(page.get_node("%Close") as Button)
	_check(
		not demo._layout.is_technology_open() and not get_tree().paused, "return resumes gameplay"
	)
	await _click(demo._layout._technology_button)
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await get_tree().process_frame
	_check(
		not demo._layout.is_technology_open() and not get_tree().paused, "Escape resumes gameplay"
	)
	demo.restart_run()
	_check(
		not demo.run.giant_unlocked and not demo.run.net_unlocked and demo.run.pipe_level == 0,
		"new game resets research"
	)
	demo.queue_free()
	await get_tree().process_frame
	print("Game upward technology: %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_layout(page: InteractivePageScript) -> void:
	var canvas: Rect2 = page._canvas.get_global_rect()
	for node: NodeScript in page._nodes.values():
		_check(canvas.encloses(node.get_global_rect()), "node fits game canvas: " + node.name)
		for other: NodeScript in page._nodes.values():
			if node != other:
				_check(
					not node.get_global_rect().intersects(other.get_global_rect()),
					"node hit areas do not overlap"
				)
	_check(
		root.get_visible_rect().encloses(page.purchase.get_global_rect()), "research button visible"
	)
	_check(
		root.get_visible_rect().encloses(
			page.get_node("Margin/Content/NavigationControls").get_global_rect()
		),
		"navigation controls visible"
	)


func _check_game_navigation(demo: DemoScript) -> void:
	var page: InteractivePageScript = demo._layout._technology as InteractivePageScript
	_check(page != null, "game uses the interactive upward technology page")
	demo._layout._show_technology()
	await _settle()
	_check(get_tree().paused, "game is paused while researching")
	var balance: int = demo.run.candy
	var node: NodeScript = page._nodes["pipe"]
	var original: Vector2 = node.position
	var center: Vector2 = node.get_global_rect().get_center()
	await _send_mouse(center, MOUSE_BUTTON_LEFT, true)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center + Vector2(32.0, 24.0)
	motion.global_position = motion.position
	motion.relative = Vector2(32.0, 24.0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await get_tree().process_frame
	await _send_mouse(motion.position, MOUSE_BUTTON_LEFT, false)
	_check(
		node.get_global_rect().get_center().distance_to(center + Vector2(32.0, 24.0)) < 1.0,
		"drag tracks the pointer through the scaled game HUD"
	)
	await _send_mouse(page._canvas.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP, true)
	_check(is_equal_approx(page.zoom_slider.value, 1.1), "in-game wheel updates zoom control")
	await _click(page.get_node("Margin/Content/NavigationControls/Reset") as Button)
	await _settle()
	_check(node.position.is_equal_approx(original), "game reset button restores upward layout")
	_check(is_equal_approx(page.zoom_factor, 1.0), "game reset button restores zoom")
	_check(demo.run.candy == balance, "navigation never spends candy")
	demo._layout.close_panels()
	_check(not get_tree().paused, "closing research resumes game")
	await _send_mouse(center, MOUSE_BUTTON_WHEEL_UP, true)
	_check(is_equal_approx(page.zoom_factor, 1.0), "hidden technology page ignores wheel")
	for link: Vector2i in page.graph.links:
		var parent: NodeScript = page._nodes[page.graph.node_keys[link.x]]
		var child: NodeScript = page._nodes[page.graph.node_keys[link.y]]
		_check(child.position.y < parent.position.y, "research branches grow upward")


func _send_mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)
	await get_tree().process_frame


func _settle() -> void:
	for frame: int in range(6):
		await get_tree().process_frame


func _click(control: Control) -> void:
	await _settle()
	var point: Vector2 = control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await _send_mouse(point, MOUSE_BUTTON_LEFT, true)
	await _send_mouse(point, MOUSE_BUTTON_LEFT, false)
	await _settle()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
