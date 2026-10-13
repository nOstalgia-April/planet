extends Node

const DemoScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")
const NodeScript = preload("res://scripts/ui/technology_node.gd")
const InteractivePageScript = preload("res://scripts/ui/interactive_technology_page.gd")
const OUTPUT: String = "res://artifacts/technology_decision_20261014"

var _failures: int = 0
@onready var root: Window = get_tree().root


func _ready() -> void:
	# Keep desktop mouse events from interleaving with the scripted pointer sequence.
	root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	_check_game.call_deferred()


func _check_game() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	demo.set_process(false)
	await _settle()
	demo.run.candy = 400
	demo.run.economy_changed.emit()
	await _check_game_navigation(demo)
	demo.run.candy = 400
	demo.run.economy_changed.emit()
	await _click(demo._layout._technology_button)
	var page: InteractivePageScript = demo._layout._technology as InteractivePageScript
	await _check_copy_previews(page)
	await _check_art_states(demo, page)
	await _check_pointer_placement(page)
	page.select_node("net_unlock")
	await _click(page._nodes[page.selected_key])
	_check(not demo.run.net_unlocked and demo.run.candy == 400, "locked research preserves wallet")
	page.select_node("pipe")
	await _hover(page._nodes["pipe"])
	await _click(page.get_node("%Purchase") as Control)
	_check(
		(
			demo.run.pipe_level == 1
			and demo.run.candy == 400 - demo.run.settings.pipe_upgrade_costs[0]
		),
		"game buys real speed upgrade"
	)
	_check(not page._nodes["net_unlock"].glyph.locked, "prerequisite reveals the real net icon")
	_check(page._detail_level.text == "Lv.2 → Lv.3", "tooltip level updates after purchase")
	_check(page._detail_gain.get_parsed_text() == "吸取速率 +40.6%", "tooltip percentage follows the purchased upgrade")
	_check(page._nodes["net_unlock"].level_label.visible, "revealed node shows its level")
	_check(page._nodes["net_unlock"].get_node("Price").visible, "revealed node shows its price")
	page.select_node("net_unlock")
	await _click(page._nodes[page.selected_key])
	_check(demo.run.net_unlocked, "game unlocks capture tool")
	page.select_node("cultivation")
	await _click(page._nodes[page.selected_key])
	_check(demo.run.governance_level == 1, "game buys cultivation")
	page.select_node("giant")
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle()
		await _hover(page._nodes["giant"])
		_check_layout(page)
		await RenderingServer.frame_post_draw
		_check(
			(
				root.get_texture().get_image().save_png(
					(
						OUTPUT + "/game_%dx%d.png"
						% [resolution.x, resolution.y]
					)
				)
				== OK
			),
			"game screenshot saved"
		)
		await _hover(page._nodes["base_value"])
		await _save_art("hover_value_%dx%d" % [resolution.x, resolution.y])
		await _hover(page.get_node("%Wallet") as Control)
		await _save_art("overview_%dx%d" % [resolution.x, resolution.y])
		await _hover(page._nodes["automation"])
		await _save_art("automation_hover_%dx%d" % [resolution.x, resolution.y])
		var close: Button = page.get_node("%Close") as Button
		var brush: TextureRect = close.get_node("Brush") as TextureRect
		close.release_focus()
		await _hover(page._wallet)
		_check(not brush.visible, "exit graffiti is hidden without hover or focus")
		await _hover(close)
		_check(brush.visible, "exit hover reveals the shared graffiti background")
		var brush_palette: ShaderMaterial = brush.material as ShaderMaterial
		var background_palette: ShaderMaterial = page.get_node("Background").material as ShaderMaterial
		_check(brush_palette.get_shader_parameter("palette_mid") == background_palette.get_shader_parameter("palette_mid"), "exit graffiti uses the current technology palette")
		await _save_art("exit_hover_%dx%d" % [resolution.x, resolution.y])
		page.set_zoom(1.6)
		await _settle()
		_check_layout(page)
		await _save_art("maximum_zoom_%dx%d" % [resolution.x, resolution.y])
		page.set_zoom(1.0)
		await _settle()
	page.select_node("giant")
	var before: int = demo.run.candy
	var cost: int = demo.run.get_technology_cost("giant")
	await _click(page._nodes[page.selected_key])
	_check(
		demo.run.giant_unlocked and demo.run.candy == before - cost,
		"global giant research applies to game"
	)
	await _click(page._nodes[page.selected_key])
	_check(demo.run.candy == before - cost, "global research cannot charge twice")
	_check(page._nodes["giant"].price_label.text == "✓ MAX", "completed node replaces its price")
	_check(not page._nodes["giant"]._purchase_glow.visible, "completed research stops glowing")
	_check(not page._nodes["giant"].coin.visible, "completed node hides the cost icon")
	_check(page.get_node("%Purchase").text == "✓ 已满级" and page.get_node("%Purchase").disabled, "completed tooltip replaces its purchase price")
	await _save_art("owned")
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		await _hover(page._wallet)
		page._hide_details()
		await _settle()
		await _save_art("decision_states_%dx%d" % [resolution.x, resolution.y])
		await _hover(page._nodes["automation"])
		await _save_art("saving_goal_%dx%d" % [resolution.x, resolution.y])
	var previous_pipe_level: int = demo.run.pipe_level
	demo.run.pipe_level = demo.run.settings.pipe_upgrade_costs.size()
	page.refresh(demo.run)
	await _hover(page._nodes["pipe"])
	_check(page._detail_effect.visible and not page._detail_gain.visible, "maxed upgrades keep their capability text without a fictitious next gain")
	await _save_art("copy_pipe_maxed")
	demo.run.pipe_level = previous_pipe_level
	page.refresh(demo.run)
	await _click(page.get_node("%Close") as Button)
	_check(
		not demo._layout.is_technology_open() and not get_tree().paused, "return resumes gameplay"
	)
	await _check_cursor(demo)
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


func _check_copy_previews(page: InteractivePageScript) -> void:
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle()
		for id: String in page.TECHNOLOGIES:
			await _hover(page._nodes[id])
			_check(page._detail_effect.visible and not page._detail_effect.text.is_empty(), "every node explains its capability: " + id)
			_check(not page._detail_gain.text.contains("inf"), "locked previews have valid quantitative gains: " + id)
			_check(root.get_visible_rect().encloses(page._detail.get_global_rect()), "copy fits the viewport: " + id)
			_check(page._detail.get_global_rect().encloses(page._detail_effect.get_global_rect()), "description fits the tooltip: " + id)
			await _save_art("copy_%s_%dx%d" % [id, resolution.x, resolution.y])


func _check_layout(page: InteractivePageScript) -> void:
	var canvas: Rect2 = page._canvas.get_global_rect()
	var endpoint: NodeScript = page._nodes["automation"]
	_check(endpoint.glyph.size.x > page._nodes["pipe"].glyph.size.x, "key unlock uses a larger original icon")
	_check(endpoint.title_label.visible, "automation is emphasized by its name")
	_check(endpoint.position.x == page._nodes["cultivation"].position.x, "automation aligns with the cultivation trunk")
	_check(endpoint.position.y < page._nodes["valuable"].position.y and endpoint.position.y < page._nodes["giant"].position.y, "automation crowns the right-hand branches")
	var screen: Rect2 = root.get_visible_rect()
	var background: Control = page.get_node("Background") as Control
	_check(background.get_global_rect().is_equal_approx(screen), "dark red background fills the screen")
	var close: Rect2 = (page.get_node("%Close") as Control).get_global_rect()
	_check(screen.encloses(close) and close.get_center().x > screen.end.x * 0.9 and close.get_center().y < screen.end.y * 0.15, "exit stays in the top right")
	for node: NodeScript in page._nodes.values():
		_check(node.title_label.visible and not node.title_label.text.is_empty(), "all technologies have permanent names")
		_check(node.get_global_rect().encloses(node.title_label.get_global_rect()), "name stays inside node bounds")
		_check(node._purchase_glow.visible == (node.state == NodeScript.State.AVAILABLE), "only affordable nodes breathe")
		_check(canvas.encloses(node.get_global_rect()), "node fits game canvas: " + node.name)
		for other: NodeScript in page._nodes.values():
			if node != other:
				_check(
					not node.get_global_rect().intersects(other.get_global_rect()),
					"node hit areas do not overlap"
				)
	_check(
		root.get_visible_rect().encloses(page._detail.get_global_rect()), "hover details fit screen"
	)
	_check(page.has_node("%Purchase"), "fixed detail provides a purchase button")
	_check(
		not page.has_node("Margin/Content/NavigationControls"),
		"zoom toolbar and reset button are removed"
	)


func _check_game_navigation(demo: DemoScript) -> void:
	var page: InteractivePageScript = demo._layout._technology as InteractivePageScript
	_check(page != null, "game uses the interactive upward technology page")
	demo._layout._show_technology()
	await _settle()
	_check(get_tree().paused, "game is paused while researching")
	var balance: int = demo.run.candy
	var node: NodeScript = page._nodes["pipe"]
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
		node.get_global_rect().get_center().distance_to(center) < 1.0,
		"left dragging cannot reposition technology nodes"
	)
	var graph_position: Vector2 = page.graph.position
	var blank: Vector2 = page._canvas.get_global_rect().position + Vector2(240.0, 120.0)
	await _send_mouse(blank, MOUSE_BUTTON_RIGHT, true)
	motion.position = blank + Vector2(120.0, 80.0)
	motion.global_position = motion.position
	motion.relative = Vector2(120.0, 80.0)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(motion, true)
	await _send_mouse(motion.position, MOUSE_BUTTON_RIGHT, false)
	_check(page.graph.position.is_equal_approx(graph_position), "right dragging cannot pan the tree")
	await _send_mouse(page._canvas.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP, true)
	_check(is_equal_approx(page.zoom_factor, 1.1), "wheel continues to zoom without a slider")
	_check(demo.run.candy == balance, "navigation never spends candy")
	_check(demo.run.pipe_level == 0, "dragging an affordable node does not buy it")
	demo._layout.close_panels()
	_check(not get_tree().paused, "closing research resumes game")
	await _send_mouse(center, MOUSE_BUTTON_WHEEL_UP, true)
	_check(is_equal_approx(page.zoom_factor, 1.1), "hidden technology page ignores wheel")
	demo._layout._show_technology()
	await _settle()
	_check(is_equal_approx(page.zoom_factor, 1.1), "reopening retains the previous zoom")
	var page_scene: PackedScene = load("res://scenes/ui/interactive_technology_page.tscn") as PackedScene
	var replacement: InteractivePageScript = page_scene.instantiate() as InteractivePageScript
	root.add_child(replacement)
	_check(is_equal_approx(replacement.zoom_factor, 1.1), "recreated menu retains the session zoom")
	replacement.queue_free()
	await get_tree().process_frame
	# Restore the fixture for the remaining purchase and layout checks.
	page.reset_layout()
	demo._layout.close_panels()
	for link: Vector2i in page.graph.links:
		var parent: NodeScript = page._nodes[page.graph.node_keys[link.x]]
		var child: NodeScript = page._nodes[page.graph.node_keys[link.y]]
		_check(child.position.y < parent.position.y, "research branches grow upward")


func _check_art_states(demo: DemoScript, page: InteractivePageScript) -> void:
	var speed: NodeScript = page._nodes["pipe"]
	_check(speed._purchase_glow.visible, "affordable research glows without hover")
	var balance: int = demo.run.candy
	await _hover(speed)
	_check(speed._focus_ink.visible and speed._halo.visible, "inspection combines original ink and pink accent")
	_check(speed._purchase_glow.visible, "affordable glow remains while inspecting")
	_check(speed.glyph.ink == Color.WHITE, "technology icons retain their original white ink")
	_check(page._detail.visible, "hover opens the information card")
	_check(page._detail_level.text == "Lv.1 → Lv.2", "tooltip shows current and maximum level beneath title")
	_check(page._detail_gain.get_parsed_text() == "吸取速率 +33.3%", "speed gain compares capture rates as a percentage")
	_check(page.get_node("%Purchase").text == "购买 · 10", "tooltip places the purchase action at the bottom")
	_check(demo.run.candy == balance, "hover never spends currency")
	_check(speed.level_label.text == "Lv.1/7", "node shows current and maximum level")
	_check(speed.price_label.text == str(demo.run.get_technology_cost("pipe")), "node shows live cost")
	_check(speed.price_label.get_theme_color("font_color") == NodeScript.PRICE_COLORS[1], "affordable price uses the bright palette")
	await _hover(page._nodes["net_unlock"])
	_check(page._nodes["net_unlock"].state == NodeScript.State.LOCKED, "locked node stays inspectable")
	var locked_node: NodeScript = page._nodes["net_unlock"]
	_check(not locked_node._purchase_glow.visible, "locked research never glows even with funds")
	_check(locked_node.glyph.locked, "locked technology replaces its art with a lock")
	_check(locked_node.glyph.ink == NodeScript.INK_COLORS[NodeScript.State.LOCKED], "locked icon is subdued")
	_check(speed._halo.visible and not speed._focus_ink.visible, "moving to another node restores its pink halo")
	_check(locked_node.title_label.visible and locked_node.level_label.visible and locked_node.price_label.text == "未解锁" and not locked_node.coin.visible, "locked technology keeps identity and level while replacing its price")
	_check(page._detail_title.text == "捕网解锁" and page._detail_effect.visible, "locked hover previews the future capability")
	_check(page._requirements.visible and page._requirements.get_child_count() > 0, "capability preview keeps unmet prerequisites visible")
	_check(not page._detail_level.visible and page._detail_gain.visible and page.get_node("%Purchase").disabled, "locked tooltip previews effects without enabling purchase")
	await _save_art("locked")
	demo.run.candy = 0
	demo.run.economy_changed.emit()
	await _hover(speed)
	_check(not speed._purchase_glow.visible, "spending wallet clears purchase glow")
	_check(not speed.glyph.locked, "insufficient funds do not hide an available technology")
	_check(speed.price_label.get_theme_color("font_color") == NodeScript.PRICE_COLORS[2], "unaffordable price is subdued")
	_check(page.get_node("%Purchase").text == "糖果不足" and page._detail_note.text == "再攒 10 糖果即可升级", "tooltip explains insufficient funds beside the cost")
	await _click(speed)
	_check(demo.run.candy == 0 and demo.run.pipe_level == 0, "unaffordable click cannot upgrade")
	await _save_art("unaffordable")
	await _hover(page.get_node("%Wallet") as Control)
	_check(page._detail.visible, "inspection persists while moving to the purchase button")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "technology page restores illustrated pointer")
	speed.grab_focus()
	await _settle()
	_check(speed._focus_ink.visible and speed._halo.visible, "keyboard focus uses the same selected artwork")
	speed.release_focus()
	var price: int = demo.run.get_technology_cost("pipe")
	for money: int in [price - 1, price, price - 1, price]:
		demo.run.candy = money
		demo.run.economy_changed.emit()
		await _settle()
		_check(speed._purchase_glow.visible == (money >= price), "crossing the exact price updates availability immediately")
	demo.run.candy = balance
	demo.run.economy_changed.emit()
	await _settle()
	_check(speed._purchase_glow.visible, "wallet refill restores purchase glow")


func _check_pointer_placement(page: InteractivePageScript) -> void:
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle()
		for id: String in page.TECHNOLOGIES:
			await _hover(page._nodes[id])
			var rect: Rect2 = page._detail.get_global_rect()
			_check(root.get_visible_rect().encloses(rect), "fixed detail stays inside viewport")
			_check(not rect.intersects(page._canvas.get_global_rect()), "detail never covers the tree or its links")
			var motion: InputEventMouseMotion = InputEventMouseMotion.new()
			motion.position = page._nodes[id].get_global_rect().get_center() + Vector2(3, 3)
			motion.global_position = motion.position
			root.push_input(motion, true)
			await _settle()
			_check(page._detail.get_global_rect().position.is_equal_approx(rect.position), "pointer motion does not move details")
			await _hover(page.get_node("%Purchase") as Control)
			_check(page._detail.visible and page.selected_key == id, "moving to purchase retains inspected technology")
		page._hide_details()
		await _save_art("overview_quiet_%dx%d" % [resolution.x, resolution.y])


func _check_cursor(demo: DemoScript) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = root.get_visible_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)
	demo._pipe.show()
	await _settle()
	_check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "vacuum hides the arrow")
	demo._pipe.hide()
	await _settle()
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "leaving vacuum restores the arrow")


func _hover(control: Control) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)
	await _settle()


func _save_art(label: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK, "art capture saved")


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
