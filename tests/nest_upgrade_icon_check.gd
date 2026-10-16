extends Node

const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const OUTPUT: String = "res://artifacts/nest_upgrade_hover_20261016"

var _game: Play
var _failures: int = 0


func _ready() -> void:
	get_tree().root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	if "--inspect-motion" in OS.get_cmdline_user_args():
		get_tree().root.title = "Nest Upgrade Motion Check"
	_run.call_deferred()


func _run() -> void:
	_game = PLAY.instantiate() as Play
	add_child(_game)
	_game.set_process(false)
	_game._view.set_process(false)
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		_game.restart_run()
		await _settle()
		_game._select_nest(1)
		_check(not _game._nest_button.visible, "research-locked upgrade is hidden")
		_check(_game._nest_button.tooltip_text.is_empty(), "locked upgrade has no tooltip")
		_game.run.candy = 100000
		_check(_game.run.upgrade_pipe(), "pipe prerequisite")
		_check(_game.run.purchase_technology("net"), "net prerequisite")
		_check(_game.run.purchase_technology("governance"), "cultivation prerequisite")
		var nest: NestState = _game.run.get_nest(1)
		var view: NestView = _game._nest_views[0]
		_game._world.rotation = -PI * 0.5 - nest.position.angle()
		await _settle()
		for species: int in range(3):
			nest.species = species as NestState.Species
			view.configure_species(species)
			_game._select_nest(1)
			await _settle()
			var button: Button = _game._nest_button
			var price: Label = button.get_node("Price") as Label
			_check(price.text == "50", "only the actual price is shown")
			_check(button.text.is_empty(), "no effect text on upgrade control")
			_check(not button.disabled, "available upgrade is enabled")
			_check(
				get_viewport().get_visible_rect().encloses(button.get_global_rect()),
				"icon stays on screen"
			)
			_check((button.get_node("Action") as Label).text == "升级", "action is named")
			_check(button.tooltip_text.is_empty(), "upgrade has no tooltip")
			if (
				species == 0
				and resolution.x == 1280
				and (
					"--inspect-motion" in OS.get_cmdline_user_args()
					or "--check-motion" in OS.get_cmdline_user_args()
				)
			):
				await _inspect_motion(button)
			await _check_hover_path(view, 0.0)
			await _capture("species_%d_%dx%d" % [species, resolution.x, resolution.y])
		for angle: float in [-0.35, 0.35]:
			_game._world.rotation = -PI * 0.5 - nest.position.angle() + angle
			await _settle()
			_game._select_nest(1)
			await _check_hover_path(view, angle)
			await _capture("rotated_%s_%dx%d" % [str(angle), resolution.x, resolution.y])
		_game.run.candy = 49
		_game._refresh_hud()
		_check(_game._nest_button.disabled, "one candy short cannot purchase")
		_game.run.candy = 50
		_game._refresh_hud()
		await _click(
			_game._nest_button.get_global_transform_with_canvas() * (_game._nest_button.size * 0.5)
		)
		_check(
			nest.level == 1 and _game.run.candy == 0,
			"icon click upgrades selected nest and charges once"
		)
		_check(
			(_game._nest_button.get_node("Price") as Label).text == "600",
			"price updates after purchase"
		)
		nest.level = 2
		_game.run.candy = 100000
		_game._refresh_hud()
		_check(not _game._nest_button.visible, "final upgrade stays hidden before its research")
		nest.is_tamed = true
		_game._refresh_hud()
		_check(not _game._nest_button.visible, "finished nest has no purchasable icon")
		_game._select_nest(1)
		_check(not _game._layout._nest_card.visible, "finished nest leaves no invisible UI blocker")
	print("Nest upgrade icon: %d failures" % _failures)
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _check_hover_path(view: NestView, angle: float) -> void:
	var button: Button = _game._nest_button
	var corners: PackedVector2Array = view.get_hover_polygon()
	var tangent: Vector2 = (corners[1] - corners[0]).normalized()
	var button_transform: Transform2D = button.get_global_transform_with_canvas()
	_check(
		button_transform.x.normalized().dot(tangent) > 0.999,
		"button follows nest rotation %s" % angle
	)
	var bottom: Vector2 = button_transform * Vector2(button.size.x * 0.5, button.size.y)
	var top: Vector2 = (corners[0] + corners[1]) * 0.5
	_check(bottom.distance_to(top) < 4.0, "button is close to nest")
	# Traverse both sloping sides from the wide nest to the narrower button.
	for side: int in range(2):
		var start: Vector2 = corners[side].lerp(top, 0.12)
		var finish: Vector2 = (
			button_transform * Vector2(button.size.x * (0.1 if side == 0 else 0.9), 12.0)
		)
		for step: int in range(11):
			_game._update_nest_hover(start.lerp(finish, float(step) / 10.0))
			_check(_game.selected_nest_id == 1, "diagonal hover corridor remains open")
	_game._update_nest_hover(Vector2(-1000.0, -1000.0))
	_check(_game.selected_nest_id == -1, "leaving the corridor closes upgrade")
	_game._select_nest(1)


func _click(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	get_tree().root.push_input(motion, true)
	await _settle()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		get_tree().root.push_input(event, true)
		await get_tree().process_frame
	await _settle()


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or "--no-captures" in OS.get_cmdline_user_args():
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await RenderingServer.frame_post_draw
	_check(
		get_viewport().get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK,
		"screenshot"
	)


func _inspect_motion(button: Button) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(100.0, 200.0)
	get_tree().root.push_input(motion, true)
	var inspect: bool = "--inspect-motion" in OS.get_cmdline_user_args()
	print("Motion preview: idle")
	await get_tree().create_timer(20.0 if inspect else 0.4).timeout
	await _emit_motion_image(button, "idle")
	await get_tree().create_timer(0.6).timeout
	await _emit_motion_image(button, "flow")
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	motion.position = point
	get_tree().root.push_input(motion, true)
	print("Motion preview: hover")
	await get_tree().create_timer(20.0 if inspect else 0.6).timeout
	await _emit_motion_image(button, "hover")
	var backing: TextureRect = button.get_node("Backing") as TextureRect
	_check(backing.scale.x > 1.1, "hover visibly enlarges icon and rim")
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	get_tree().root.push_input(down, true)
	print("Motion preview: held")
	await get_tree().create_timer(10.0 if inspect else 0.4).timeout
	await _emit_motion_image(button, "held")
	_check(backing.scale.x < 1.0, "holding compresses the button")
	# Release outside to inspect the rebound without buying an upgrade.
	motion.position = Vector2(100.0, 200.0)
	get_tree().root.push_input(motion, true)
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = motion.position
	get_tree().root.push_input(up, true)
	print("Motion preview: released")
	await get_tree().create_timer(1.0).timeout
	_check(absf(backing.scale.x - 1.0) < 0.01, "leaving restores resting size")


func _emit_motion_image(button: Button, label: String) -> void:
	if "--check-motion" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var ratio: Vector2 = Vector2(screenshot.get_size()) / get_viewport().get_visible_rect().size
	var bounds: Rect2 = (
		(button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, button.size)).grow(30.0)
	)
	var region: Rect2i = Rect2i(bounds.position * ratio, bounds.size * ratio)
	var crop: Image = screenshot.get_region(region)
	print("MOTION_IMAGE|%s|%s" % [label, Marshalls.raw_to_base64(crop.save_png_to_buffer())])


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
