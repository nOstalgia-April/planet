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
	await _check_hold_upgrade()
	if "--hold-only" in OS.get_cmdline_user_args():
		print("Nest hold upgrade: %d failures" % _failures)
		get_tree().quit(0 if _failures == 0 else 1)
		return
	await _check_entrance()
	if "--entrance-only" in OS.get_cmdline_user_args():
		print("Nest upgrade entrance: %d failures" % _failures)
		get_tree().quit(0 if _failures == 0 else 1)
		return
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


func _check_entrance() -> void:
	_game._update_nest_prompts()
	_check(_game._nest_prompts.is_empty(), "locked research has no entry prompts")
	_game.run.candy = 100000
	_game.run.upgrade_pipe()
	_game.run.purchase_technology("net")
	_game.run.purchase_technology("governance")
	_game._view.zoom_steps(-1.0, false)
	_game._update_nest_prompts()
	_check(_game._nest_prompts.is_empty(), "research in overview waits for near view")
	_game._view.zoom_steps(1.0, false)
	await _settle()
	_game._update_nest_prompts()
	_check(not _game._nest_prompts.is_empty(), "returning near reveals visible nests")
	_check(_game._nest_prompts.size() >= 2, "visible nests show independent prompts together")
	var button: Button = _game._nest_prompts[1]
	var price: Label = button.get_node("Price") as Label
	_check(not button.visible, "entering the screen starts a hidden wait")
	_game._update_nest_prompts(0.6)
	_check(not button.visible, "less than one second cannot show the prompt")
	_game._world.rotation += PI
	_game._update_nest_prompts(1.0)
	_check(not button.visible, "leaving the screen cancels pending entrance")
	_game._world.rotation -= PI
	_game._update_nest_prompts(0.6)
	_check(not button.visible, "reentry does not reuse the cancelled wait")
	_game._suspend_nest_prompts()
	_game._update_nest_prompts(0.99)
	_game._refresh_hud()
	_check(not button.visible, "suspension resets the wait and HUD refresh cannot bypass it")
	_game._update_nest_prompts(0.02)
	_check(button.visible, "one uninterrupted second starts the entrance")
	_check(not price.visible, "entrance begins with icon only")
	var start: Vector2 = button.position
	await get_tree().create_timer(0.6).timeout
	_check(price.visible, "settled prompt shows price")
	_check(button.position.distance_to(start) > 40.0, "icon rises from nest head")
	var final_position: Vector2 = button.position
	button.begin_entrance()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = button.get_global_transform_with_canvas() * (button.size * 0.5)
	get_tree().root.push_input(motion, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(button.position.is_equal_approx(final_position), "early hover snaps to final position")
	_check(price.visible, "early hover reveals price immediately")
	_check(
		_game._layout.is_over_ui(button.get_global_transform_with_canvas() * (button.size * 0.5)),
		"entry prompt blocks collection"
	)
	_game.run.candy = 0
	_game._refresh_hud()
	_check(button.disabled and price.text == "50", "unaffordable prompt retains actual price")
	_game.run.candy = 100000
	_game._refresh_hud()
	await _click(button.get_global_transform_with_canvas() * (button.size * 0.5))
	_check(_game.run.get_nest(1).level == 1, "entry button upgrades its own nest")
	_check(price.text == "600", "entry price updates after purchase")
	_game._layout._toggle_pause()
	_check(not button.visible, "pause hides entry prompts")
	_game._layout._toggle_pause()
	_game._world.rotation += PI
	_game._update_nest_prompts()
	_check(not button.visible, "offscreen nest hides its prompt")
	_game._world.rotation -= PI
	_game._update_nest_prompts()
	_check(not button.visible, "reentering nest waits before playing entrance again")
	_game._update_nest_prompts(1.0)
	_check(button.visible and not price.visible, "reentering nest plays entrance again")
	await get_tree().create_timer(0.6).timeout
	if "--capture-entrance" in OS.get_cmdline_user_args():
		for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
			get_tree().root.size = resolution
			await _settle()
			_game._update_nest_prompts()
			for prompt: Button in _game._nest_prompts.values():
				prompt.begin_entrance()
			await _capture_entrance("start_%d" % resolution.x)
			await get_tree().create_timer(0.6).timeout
			_game._update_nest_prompts()
			await _capture_entrance("settled_%d" % resolution.x)
	var new_position: Vector2 = _game.run.get_nest(1).position
	_game.run._add_nest(NestState.Species.MUCUS, new_position, true)
	var new_id: int = _game.run.nests.back().nest_id
	_game._update_nest_prompts()
	_check(not _game._nest_prompts.has(new_id), "emerging nest waits until discovery finishes")
	_game.run.finish_nest_discovery(new_id)
	_game._update_nest_prompts()
	_check(_game._nest_prompts.has(new_id), "newly discovered onscreen nest gets a prompt")
	_check(not _game._nest_prompts[new_id].visible, "new discovery also waits one second")
	_game._update_nest_prompts(1.0)
	_check(_game._nest_prompts[new_id].visible, "new discovery appears after its wait")
	await _check_prompt_timeout(button)
	_game.run.get_nest(new_id).level = 2
	_game._update_nest_prompts()
	_check(not _game._nest_prompts[new_id].visible, "research-locked final upgrade hides prompt")
	_game.restart_run()
	_check(_game._nest_prompts.is_empty(), "restart clears old prompts")


func _check_prompt_timeout(button: Button) -> void:
	button.set_process(false)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(10.0, 150.0)
	get_viewport().push_input(motion, true)
	button.begin_entrance()
	button._process(3.99)
	_check(button.visible and not button.prompt_expired, "prompt stays for four idle seconds")
	button._process(0.02)
	_check(
		button.prompt_expired and button.visible, "idle prompt starts lowering after four seconds"
	)
	button._process(0.5)
	_check(not button.visible, "lowering ends with hidden prompt")
	_game._update_nest_prompts()
	_game._refresh_hud()
	_check(not button.visible, "per-frame and currency refresh cannot reopen expired prompts")
	_game._world.rotation += PI
	_game._update_nest_prompts()
	_game._world.rotation -= PI
	_game._update_nest_prompts()
	_check(not button.visible, "expired prompt still waits on screen reentry")
	_game._update_nest_prompts(1.0)
	_check(button.visible and not button.prompt_expired, "screen reentry resets idle timeout")
	button._finish_entrance()
	motion.position = button.get_global_transform_with_canvas() * (button.size * 0.5)
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	button._advance_prompt(5.0, motion.position)
	button._process(0.5)
	_check(button.visible and not button.prompt_expired, "hover preserves the prompt")
	var price_material: ShaderMaterial = button.get_node("Price").material as ShaderMaterial
	_check(
		float(price_material.get_shader_parameter("hover_amount")) > 0.9,
		"affordable hover enables price color"
	)
	_game.run.candy = 0
	_game._refresh_hud()
	button._process(0.1)
	_check(
		is_zero_approx(float(price_material.get_shader_parameter("hover_amount"))),
		"unaffordable hover clears price color"
	)
	_game.run.candy = 100000
	_game._refresh_hud()
	motion.position = Vector2(10.0, 150.0)
	get_viewport().push_input(motion, true)
	button._process(0.1)
	_check(
		is_zero_approx(float(price_material.get_shader_parameter("hover_amount"))),
		"leaving hover clears price color immediately"
	)
	button.set_hold_progress(0.5)
	button._process(5.0)
	_check(button.visible and not button.prompt_expired, "active hold prevents timeout")
	button.set_hold_progress(-1.0)
	button._process(4.0)
	button._process(0.5)
	_check(not button.visible, "idle countdown resumes after interaction")
	button.set_hold_progress(0.0)
	_check(button.visible and not button.prompt_expired, "hold can reopen an expired prompt")
	button.set_hold_progress(-1.0)
	button.set_process(true)


func _capture_entrance(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"res://artifacts/nest_entrance_20261017/%s.png" % label
	)


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


func _check_hold_upgrade() -> void:
	get_tree().root.size = Vector2i(1920, 1080)
	_game.restart_run()
	_game.run.candy = 100000
	_game.run.upgrade_pipe()
	_game.run.purchase_technology("net")
	_game.run.purchase_technology("governance")
	_game._view.zoom_steps(1.0, false)
	await _settle()
	_game._update_nest_prompts()
	await get_tree().create_timer(0.6).timeout
	var nest: NestState = _game.run.get_nest(1)
	var point: Vector2 = _game._nest_views[0].get_hover_rect().get_center()
	var button: Button = _game._nest_prompts[1]
	var candy: int = _game.run.candy
	await _hold_input(point, true)
	_check(_game._held_nest_id == 1, "press on nest starts hold")
	_check(button.scale.x < 0.5 and button.modulate.a < 0.6, "hold starts small and translucent")
	await _capture_hold("start")
	_game._advance_nest_hold(_game.nest_hold_seconds * 0.5, point)
	_check(nest.level == 0 and _game.run.candy == candy, "partial hold spends nothing")
	_check(button.scale.x > 0.5 and button.scale.x < 1.0, "hold grows toward original size")
	await _capture_hold("half")
	await _hold_input(point, false)
	_check(_game._held_nest_id == -1, "release cancels immediately")
	_check(button.scale == Vector2.ONE and button.modulate.a == 1.0, "cancel restores button")
	await _hold_input(point, true)
	_game._advance_nest_hold(_game.nest_hold_seconds, point)
	_check(nest.level == 1 and _game.run.candy == candy - 50, "full hold purchases once")
	_check(button.scale == Vector2.ONE and button.modulate.a == 1.0, "success restores full size")
	await _capture_hold("success")
	_game._advance_nest_hold(_game.nest_hold_seconds * 2.0, point)
	_check(nest.level == 1, "continued hold never purchases another level")
	await _hold_input(point, false)
	await _hold_input(point, true)
	_check(_game._held_nest_id == 1, "a new press can start the next upgrade")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(10.0, 150.0)
	get_tree().root.push_input(motion, true)
	await get_tree().process_frame
	_check(_game._held_nest_id == -1, "leaving nest cancels immediately")
	await _hold_input(point, false)
	await _hold_input(point, true)
	_check(_game._held_nest_id == 1, "hold is active before pausing")
	_game._layout._toggle_pause()
	_check(_game._held_nest_id == -1, "pause cancels hold")
	_game._layout._toggle_pause()
	await _hold_input(point, false)
	_game._update_nest_prompts()
	await get_tree().create_timer(0.6).timeout
	await _hold_input(point, true)
	_check(_game._held_nest_id == 1, "hold is active before affordability changes")
	_game.run.candy = 0
	_game._advance_nest_hold(_game.nest_hold_seconds, point)
	_check(_game._held_nest_id == -1 and nest.level == 1, "lost affordability cancels purchase")
	await _hold_input(point, false)
	await _hold_input(point, true)
	_check(_game._held_nest_id == -1, "unaffordable nest cannot begin hold")
	await _hold_input(point, false)
	_game.run.candy = candy
	await _hold_input(point, true)
	_check(_game._held_nest_id == 1, "hold is active before focus loss")
	_game._on_window_focus_exited()
	_check(_game._held_nest_id == -1, "focus loss cancels hold")
	_game._on_window_focus_entered()
	await _hold_input(point, false)
	await _hold_input(point, true)
	_game._request_view_steps(-1.0)
	_check(_game._held_nest_id == -1, "view change cancels hold")
	await _hold_input(point, false)
	_game._view.zoom_steps(1.0, false)
	_game._update_nest_prompts()
	await get_tree().create_timer(0.6).timeout
	await _hold_input(point, true)
	_check(_game._held_nest_id == 1, "hold is active before restart")
	_game.restart_run()
	_check(_game._held_nest_id == -1, "restart clears pending purchase")
	await _hold_input(point, false)
	await _hold_input(point, true)
	_check(_game._held_nest_id == -1, "research locked nest cannot begin hold")
	await _hold_input(point, false)


func _hold_input(point: Vector2, pressed: bool) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	get_tree().root.push_input(motion, true)
	await get_tree().process_frame
	_game.update_pointer_release_state()
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	if DisplayServer.get_name() == "headless":
		get_tree().root.push_input(event, true)
	await get_tree().process_frame
	_game.update_pointer_release_state()


func _capture_hold(label: String) -> void:
	if "--capture-hold" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"res://artifacts/nest_hold_20261017_task/%s.png" % label
	)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
