extends Node

const DemoScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")
const NodeScript = preload("res://scripts/ui/technology_node.gd")
const InteractivePageScript = preload("res://scripts/ui/interactive_technology_page.gd")
const OUTPUT: String = "res://artifacts/technology_concise_20261013"

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
	await _check_art_states(demo, page)
	await _check_pointer_placement(page)
	page.select_node("net_unlock")
	await _click(page._nodes[page.selected_key])
	_check(not demo.run.net_unlocked and demo.run.candy == 400, "locked research preserves wallet")
	page.select_node("pipe")
	await _click(page._nodes[page.selected_key])
	_check(
		(
			demo.run.pipe_level == 1
			and demo.run.candy == 400 - demo.run.settings.pipe_upgrade_costs[0]
		),
		"game buys real speed upgrade"
	)
	_check(not page._nodes["net_unlock"].glyph.locked, "prerequisite reveals the real net icon")
	_check(page._detail_level.text == "2/7", "tooltip level updates after purchase")
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
	_check(page._nodes["giant"].price_label.text == "已满级", "completed node replaces its price")
	_check(not page._nodes["giant"].coin.visible, "completed node hides the cost icon")
	_check(page._detail_state.text == "已满级" and not page.get_node("%DetailCost").visible, "completed tooltip replaces its purchase price")
	await _save_art("owned")
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


func _check_layout(page: InteractivePageScript) -> void:
	var canvas: Rect2 = page._canvas.get_global_rect()
	var endpoint: NodeScript = page._nodes["automation"]
	_check(endpoint.glyph.size == page._nodes["pipe"].glyph.size and endpoint._halo.size == page._nodes["pipe"]._halo.size, "automation uses the same icon and halo size as other nodes")
	_check(endpoint.title_label.visible, "automation is emphasized by its name")
	_check(endpoint.position.x == page._nodes["cultivation"].position.x, "automation aligns with the cultivation trunk")
	_check(endpoint.position.y < page._nodes["valuable"].position.y and endpoint.position.y < page._nodes["giant"].position.y, "automation crowns the right-hand branches")
	var screen: Rect2 = root.get_visible_rect()
	var background: Control = page.get_node("Background") as Control
	_check(background.get_global_rect().is_equal_approx(screen), "dark red background fills the screen")
	var close: Rect2 = (page.get_node("%Close") as Control).get_global_rect()
	_check(screen.encloses(close) and close.get_center().x > screen.end.x * 0.9 and close.get_center().y < screen.end.y * 0.15, "exit stays in the top right")
	for node: NodeScript in page._nodes.values():
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
	_check(not page.has_node("%Purchase"), "research is purchased through nodes only")
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
	var balance: int = demo.run.candy
	await _hover(speed)
	_check(speed._focus_ink.visible and not speed._halo.visible, "hover switches the pink halo to black focus ink")
	_check(speed.glyph.ink == Color.WHITE, "technology icons retain their original white ink")
	_check(page._detail.visible, "hover opens the information card")
	_check(page._detail_level.text == "1/7", "tooltip shows current and maximum level beneath title")
	_check(page._detail_gain.get_parsed_text() == "吸取速率 +33.3%", "speed gain compares capture rates as a percentage")
	_check(page._detail_state.text == "购买", "tooltip places the purchase action at the bottom")
	_check(page.get_node("%DetailCoin").modulate == Color.WHITE, "tooltip preserves the candy artwork color")
	_check(demo.run.candy == balance, "hover never spends currency")
	_check(speed.level_label.text == "1/7", "node shows current and maximum level")
	_check(speed.price_label.text == str(demo.run.get_technology_cost("pipe")), "node shows live cost")
	_check(speed.price_label.get_theme_color("font_color") == NodeScript.PRICE_COLORS[1], "affordable price is green")
	await _hover(page._nodes["net_unlock"])
	_check(page._nodes["net_unlock"].state == NodeScript.State.LOCKED, "locked node stays inspectable")
	var locked_node: NodeScript = page._nodes["net_unlock"]
	_check(locked_node.glyph.locked, "locked technology replaces its art with a lock")
	_check(locked_node.glyph.ink == Color.WHITE, "locked nodes keep the white and pink visual language")
	_check(speed._halo.visible and not speed._focus_ink.visible, "moving to another node restores its pink halo")
	_check(not locked_node.level_label.visible and not locked_node.get_node("Price").visible, "locked technology hides its level and price")
	_check(page._detail_title.text == "未解锁" and not page._detail_effect.visible, "locked hover only exposes prerequisites")
	_check(not page._detail_level.visible and not page._detail_gain.visible and not page.get_node("%DetailPurchase").visible, "locked tooltip hides level, gain and price")
	await _save_art("locked")
	demo.run.candy = 0
	demo.run.economy_changed.emit()
	await _hover(speed)
	_check(not speed.glyph.locked, "insufficient funds do not hide an available technology")
	_check(speed.price_label.get_theme_color("font_color") == NodeScript.PRICE_COLORS[2], "unaffordable price turns coral")
	_check(page._detail_state.text == "糖果不足", "tooltip explains insufficient funds beside the cost")
	await _click(speed)
	_check(demo.run.candy == 0 and demo.run.pipe_level == 0, "unaffordable click cannot upgrade")
	await _save_art("unaffordable")
	await _hover(page.get_node("%Wallet") as Control)
	_check(not page._detail.visible, "leaving node hides the information card")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "technology page restores illustrated pointer")
	speed.grab_focus()
	await _settle()
	_check(speed._focus_ink.visible and not speed._halo.visible, "keyboard focus also uses black ink")
	speed.release_focus()
	demo.run.candy = balance
	demo.run.economy_changed.emit()
	await _settle()


func _check_pointer_placement(page: InteractivePageScript) -> void:
	var node: NodeScript = page._nodes["pipe"]
	var original_position: Vector2 = node.position
	for corner: Vector2 in [Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.1, 0.9), Vector2(0.9, 0.9)]:
		var point: Vector2 = root.get_visible_rect().size * corner
		node.position = page.graph.get_global_transform_with_canvas().affine_inverse() * point - node.size * 0.5
		await _hover(node)
		var rect: Rect2 = page._detail.get_global_rect()
		_check(page._detail.visible and root.get_visible_rect().encloses(rect), "mouse tooltip fits each screen corner")
		_check(not rect.has_point(point), "tooltip never covers its mouse anchor")
		_check(rect.position.x > point.x if corner.x < 0.5 else rect.end.x < point.x, "tooltip flips horizontally with screen position")
		_check(rect.position.y > point.y if corner.y < 0.5 else rect.end.y < point.y, "tooltip flips vertically with screen position")
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = point + Vector2(4.0, 4.0)
		motion.global_position = motion.position
		root.push_input(motion, true)
		await _settle()
		_check(page._detail.get_global_rect().position.distance_to(rect.position + Vector2(4.0, 4.0)) < 1.0, "tooltip follows movement within the same node")
	await _save_art("tooltip_bottom_right")
	# Isolate the midpoint fixture from other nodes' overlapping hit areas.
	for other: NodeScript in page._nodes.values():
		if other != node:
			other.hide()
	var screen_center: Vector2 = page._canvas.get_global_rect().get_center()
	var icon_center: Vector2 = screen_center - Vector2(2.0, 2.0)
	node.position = page.graph.get_global_transform_with_canvas().affine_inverse() * icon_center - NodeScript.ICON_CENTER
	for offset: Vector2 in [Vector2(-8.0, -8.0), Vector2(8.0, 8.0)]:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = screen_center + offset
		motion.global_position = motion.position
		root.push_input(motion, true)
		await _settle()
		var rect: Rect2 = page._detail.get_global_rect()
		_check(page._detail.visible and page._hovered_key == "pipe", "center node remains hovered across screen midpoints")
		_check(rect.position.x > motion.position.x and rect.position.y > motion.position.y, "icon position keeps tooltip direction stable across screen midpoints")
	for other: NodeScript in page._nodes.values():
		other.show()
	node.position = original_position
	await _hover(page.get_node("%Wallet") as Control)
	page.graph.queue_redraw()


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
