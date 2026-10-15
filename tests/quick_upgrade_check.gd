extends Node

const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const Dock = preload("res://scripts/ui/bottom_dock.gd")
const OUTPUT: String = "res://artifacts/quick_upgrade_20261015"

var _game: Play
var _dock: Dock
var _failures: int = 0


func _ready() -> void:
	get_tree().root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	_run.call_deferred()


func _run() -> void:
	_game = PLAY.instantiate() as Play
	add_child(_game)
	_game.set_process(false)
	_game._view.set_process(false)
	_dock = _game._layout._tool_dock
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		_game.restart_run()
		await _settle()
		await _check_pipe_progression()
		await _check_purchase_edges(resolution)
		await _check_net_and_selection()
	print("Quick upgrade: %d failures" % _failures)
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _check_pipe_progression() -> void:
	for level: int in range(_game.run.settings.pipe_upgrade_costs.size()):
		await _wallet(_game.run.get_pipe_upgrade_cost())
		await _click(_dock.upgrades[0])
		_check(_game.run.pipe_level == level + 1, "each pipe tier upgrades through a click")
		_check(_game.run.candy == 0, "each pipe tier charges its exact price")
	_check(_dock.states[0] == Dock.ToolState.MAXED, "level 8 is maxed")
	_check(not _dock._expanded[0], "level 8 hides its purchase tab")
	await _wallet(3000)
	_game._on_quick_upgrade(0)
	_check(_game.run.candy == 3000, "maxed pipe cannot charge again")


func _check_purchase_edges(resolution: Vector2i) -> void:
	_game.run.pipe_level = 6
	await _wallet(2999)
	await _hover(_dock.pipe_button.get_global_rect().get_center())
	_check(_dock.upgrades[0].disabled, "one candy short disables the final upgrade")
	await _click(_dock.upgrades[0], Vector2(0.5, 0.9))
	_check(_game.run.pipe_level == 6 and _game.run.candy == 2999, "disabled edge cannot spend")
	# The lower edge overlaps the tool button's rectangle. GUI order must still
	# route that click to the purchase, even though its art draws behind the tool.
	for fraction: Vector2 in [
		Vector2(0.5, 0.2),
		Vector2(0.5, 0.5),
		Vector2(0.1, 0.9),
		Vector2(0.9, 0.9),
		Vector2(0.5, 0.98)
	]:
		_game.run.pipe_level = 6
		await _wallet(3000)
		await _click(_dock.upgrades[0], fraction)
		_check(_game.run.pipe_level == 7, "all parts of the tab upgrade level 7 to 8")
		_check(_game.run.candy == 0, "edge purchase charges 3000 exactly once")
		_check(
			(_dock.pipe_button.get_node("Detail") as Label).text == "8 级",
			"edge purchase refreshes the displayed level"
		)
	_game.run.pipe_level = 6
	await _wallet(3000)
	_game._status_label.modulate.a = 0.0
	await _capture("level_7", resolution)
	await _click(_dock.upgrades[0], Vector2(0.5, 0.9), true)
	_check(_game.run.pipe_level == 7 and _game.run.candy == 1, "income refresh preserves purchase")
	_check(
		is_equal_approx(_game.run.get_pipe_capture_seconds(), 0.08),
		"final purchase applies level 8 capture speed"
	)
	await _capture("level_8", resolution)


func _check_net_and_selection() -> void:
	await _wallet(_game.run.get_technology_cost("net_unlock"))
	await _click(_dock.upgrades[1], Vector2(0.5, 0.9))
	_check(_game.run.net_unlocked and _game.run.candy == 0, "net unlock edge also purchases")
	await _wallet(_game.run.get_technology_cost("net_capacity"))
	await _click(_dock.upgrades[1], Vector2(0.5, 0.9))
	_check(_game.run.net_level == 1 and _game.run.candy == 0, "net capacity edge also purchases")
	await _wallet(10000)
	await _click(_dock.net_button)
	_check(_game._active_tool == 1 and _game.run.candy == 10000, "net body still selects its tool")
	_game.run.pipe_level = 6
	await _wallet(3000)
	await _click(_dock.pipe_button)
	_check(
		_game._active_tool == 0 and _game.run.pipe_level == 6 and _game.run.candy == 3000,
		"pipe body still selects its tool without buying"
	)


func _wallet(amount: int) -> void:
	_game.run.candy = amount
	_game.run.economy_changed.emit()
	await _settle()


func _hover(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_tree().root.push_input(motion, true)
	await _settle()


func _click(
	button: Button, fraction: Vector2 = Vector2(0.5, 0.5), refresh_between: bool = false
) -> void:
	var rect: Rect2 = button.get_global_rect()
	var point: Vector2 = rect.position + rect.size * fraction
	await _hover(point)
	_check(get_viewport().gui_get_hovered_control() == button, "click reaches the intended button")
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = point
		event.global_position = point
		get_tree().root.push_input(event, true)
		if pressed and refresh_between:
			_game.run.candy += 1
			_game.run.economy_changed.emit()
		await get_tree().process_frame
	await _settle()


func _capture(label: String, resolution: Vector2i) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args():
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await RenderingServer.frame_post_draw
	var path: String = OUTPUT + "/%s_%dx%d.png" % [label, resolution.x, resolution.y]
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture " + label)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.25, true).timeout


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
