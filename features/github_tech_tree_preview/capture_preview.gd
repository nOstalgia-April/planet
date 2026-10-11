extends SceneTree

const PreviewScene: PackedScene = preload(
	"res://features/github_tech_tree_preview/github_tech_tree_preview.tscn"
)
const PreviewScript = preload("res://features/github_tech_tree_preview/github_tech_tree_preview.gd")
const NodeScript = preload("res://scripts/ui/technology_node.gd")

var _failures: int = 0


func _initialize() -> void:
	_check_preview.call_deferred()


func _check_preview() -> void:
	root.mode = Window.MODE_WINDOWED
	var preview: PreviewScript = PreviewScene.instantiate() as PreviewScript
	root.add_child(preview)
	current_scene = preview
	await _settle()
	_check(preview.page.graph.links.size() == 8, "only actual prerequisites have edges")
	preview.page.select_node("giant")
	await _click(preview.page.purchase)
	_check(not preview.run.giant_unlocked, "locked research cannot be bought")
	preview.page.select_node("pipe")
	await _click(preview.page.purchase)
	_check(preview.run.pipe_level == 1 and preview.run.candy == 390, "real speed purchase")
	_check(
		preview.page._nodes["net_unlock"].state == NodeScript.State.AVAILABLE,
		"speed purchase opens net branch"
	)
	preview.page.select_node("cultivation")
	var expected_balance: int = preview.run.candy - preview.run.get_technology_cost("cultivation")
	await _click(preview.page.purchase)
	_check(
		preview.run.governance_level == 1 and preview.run.candy == expected_balance,
		"real cultivation"
	)
	preview.page.select_node("giant")
	var start: Vector2 = preview.page._nodes["giant"].position
	var point: Vector2 = preview.page._nodes["giant"].get_global_rect().get_center()
	await _mouse_button(point, MOUSE_BUTTON_LEFT, true)
	await _motion(point + Vector2(30.0, 22.0), Vector2(30.0, 22.0))
	await _mouse_button(point + Vector2(30.0, 22.0), MOUSE_BUTTON_LEFT, false)
	_check(preview.page._nodes["giant"].position.distance_to(start) > 10.0, "mouse drag moves node")
	preview._github_page.set_zoom(1.4)
	_check(is_equal_approx(preview._github_page.zoom_factor, 1.4), "zoom applies")
	preview._github_page.reset_layout()
	_check(
		preview.page._nodes["giant"].position.is_equal_approx(start), "layout reset restores node"
	)
	_check(
		preview.run.candy == expected_balance and preview.run.governance_level == 1,
		"layout reset retains progress"
	)
	var canvas_point: Vector2 = preview.page._canvas.get_global_rect().get_center()
	await _mouse_button(canvas_point, MOUSE_BUTTON_WHEEL_UP, true)
	_check(is_equal_approx(preview._zoom.value, 1.1), "wheel synchronizes slider")
	var graph_start: Vector2 = preview.page.graph.position
	await _mouse_button(canvas_point, MOUSE_BUTTON_RIGHT, true)
	await _motion(canvas_point + Vector2(25.0, 0.0), Vector2(25.0, 0.0))
	await _mouse_button(canvas_point + Vector2(25.0, 0.0), MOUSE_BUTTON_RIGHT, false)
	_check(preview.page.graph.position.x > graph_start.x, "right drag pans canvas")
	preview._github_page.reset_layout()
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle()
		_check_layout(preview)
		await _save("github_tech_tree_available_%dx%d.png" % [resolution.x, resolution.y])
	expected_balance = preview.run.candy - preview.run.get_technology_cost("giant")
	preview.page.purchase.pressed.emit()
	await _settle()
	_check(
		preview.run.giant_unlocked and preview.run.candy == expected_balance,
		"global research buys once"
	)
	preview.page.purchase.pressed.emit()
	await _settle()
	_check(preview.run.candy == expected_balance, "owned research cannot charge twice")
	preview.set_preview(3)
	preview.page.select_node("giant")
	await _settle()
	await _save("github_tech_tree_owned_1920x1080.png")
	print("Github technology preview: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_layout(preview: PreviewScript) -> void:
	var canvas: Rect2 = preview.page._canvas.get_global_rect()
	for node: NodeScript in preview.page._nodes.values():
		_check(canvas.encloses(node.get_global_rect()), "node fits clipped canvas: " + node.name)
		for other: NodeScript in preview.page._nodes.values():
			if node != other:
				_check(
					not node.get_global_rect().intersects(other.get_global_rect()),
					"hit areas separated"
				)
	var screen: Rect2 = root.get_visible_rect()
	_check(screen.encloses(preview.page.purchase.get_global_rect()), "purchase fits screen")
	_check(
		screen.encloses(
			(
				(preview.page.get_node("Margin/Content/NavigationControls/Reset") as Control)
				. get_global_rect()
			)
		),
		"toolbar fits screen"
	)


func _click(control: Control) -> void:
	await _settle()
	var point: Vector2 = control.get_global_rect().get_center()
	await _motion(point, Vector2.ZERO)
	await _mouse_button(point, MOUSE_BUTTON_LEFT, true)
	await _mouse_button(point, MOUSE_BUTTON_LEFT, false)
	await _settle()


func _mouse_button(point: Vector2, button: MouseButton, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = down
	root.push_input(event, true)
	await process_frame


func _motion(point: Vector2, relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
	await process_frame


func _settle() -> void:
	for _frame: int in range(6):
		await process_frame


func _save(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check(
		root.get_texture().get_image().save_png("res://artifacts/" + filename) == OK,
		"capture saved"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
