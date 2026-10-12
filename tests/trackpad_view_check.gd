extends Node

const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const OUTPUT: String = "res://artifacts/view_ui_transition_20261013"

var _game: Play
var _failures: int = 0
var _point: Vector2 = Vector2(400, 180)


func _ready() -> void:
	get_tree().root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		_game = PLAY.instantiate() as Play
		add_child(_game)
		await _settle()
		_game._apply_layout()
		_game.set_process(false)
		_game._view.set_process(false)
		_game._window_has_focus = true
		await _check_view_ui(resolution)
		var nests: Array[NestView] = _game._nest_views.duplicate()
		var candy: int = _game.run.candy
		_check(
			(
				absf(
					(
						_game._layout._view_shortcut.get_global_rect().get_center().y
						- _game.get_viewport_rect().size.y * 0.5
					)
				)
				< 1.0
			),
			"shortcut stays at the left vertical center"
		)
		await _capture("near", resolution)
		_pan(Vector2(0, 3))
		_pinch(0.99)
		_check(not _game._view.is_overview(), "small gestures do not switch")
		await _fresh_stroke()
		_pan(Vector2(100, 10))
		_check(not _game._view.is_overview(), "horizontal swipe ignored")
		_pan(Vector2(0, 20))
		_pan(Vector2(0, -20))
		_pan(Vector2(0, 22))
		_check(not _game._view.is_overview(), "direction changes discard partial travel")
		_pan(Vector2(0, 20))
		_check(_game._view.is_overview(), "vertical scroll accumulates into overview")
		_pan(Vector2(0, -100))
		_check(_game._view.is_overview(), "in-flight reversal ignored")
		_finish_transition()
		_pan(Vector2(0, -100))
		_check(_game._view.is_overview(), "same stroke cannot reverse after transition")
		await _capture("overview", resolution)
		await _fresh_stroke()
		_pan(Vector2(0, -45))
		_check(not _game._view.is_overview(), "new reverse scroll returns near")
		await _fresh_stroke()
		_pinch(0.96)
		_pinch(0.96)
		_check(not _game._view.is_overview(), "pinch threshold rejects small changes")
		_pinch(0.96)
		_check(_game._view.is_overview(), "pinch closes to overview")
		_finish_transition()
		_pinch(1.4)
		_check(_game._view.is_overview(), "pinch remains latched")
		await _fresh_stroke()
		_pinch(1.04)
		_pinch(1.04)
		_pinch(1.04)
		_check(not _game._view.is_overview(), "spreading fingers returns near")
		await _fresh_stroke()
		var ui_point: Vector2 = _game._layout._view_switch.get_global_rect().get_center()
		_pan(Vector2(0, 60), ui_point)
		_pan(Vector2(0, 60))
		_check(not _game._view.is_overview(), "gesture beginning on UI stays suppressed")
		await _fresh_stroke()
		_game._view.presentation_locked = true
		_pinch(0.5)
		_tab()
		_check(not _game._view.is_overview(), "presentation blocks pinch and Tab")
		_game._view.presentation_locked = false
		_game._on_window_focus_exited()
		_tab()
		_pan(Vector2(0, 60))
		_check(not _game._view.is_overview(), "unfocused window blocks inputs")
		_game._on_window_focus_entered()
		_game._view.begin_drag(_point)
		_tab()
		_check(not _game._view.is_overview(), "drag blocks Tab")
		_game._view.end_drag()
		_game._layout._show_technology()
		await _settle()
		_tab()
		_pinch(0.5)
		_check(not _game._view.is_overview(), "technology page blocks inputs")
		_check(not _game._layout._view_shortcut.visible, "technology hides shortcut")
		_game._layout.close_panels()
		_game._layout._toggle_pause()
		await _settle()
		_tab()
		_check(not _game._view.is_overview(), "pause blocks Tab")
		_game._layout._toggle_pause()
		_game._completion.show()
		_tab()
		_check(not _game._view.is_overview(), "completion blocks Tab")
		_game._completion.hide()
		await _settle()
		# A focused HUD control must not steal Tab for focus traversal.
		_game._nest_button.focus_mode = Control.FOCUS_ALL
		_game._nest_button.show()
		_game._layout._nest_card.show()
		_game._nest_button.grab_focus()
		_tab(false, true)
		_check(not _game._view.is_overview(), "modified Tab ignored")
		_tab()
		_check(_game._view.is_overview(), "Tab switches before GUI focus traversal")
		_finish_transition()
		_tab(true)
		_check(_game._view.is_overview(), "held Tab echo ignored")
		_tab()
		_check(not _game._view.is_overview(), "second Tab returns near")
		_finish_transition()
		_game._layout.set_view_switch_enabled(true)
		_click(_game._layout._view_switch.get_global_rect().get_center())
		_check(_game._view.is_overview(), "left-side icon click switches view")
		_wheel(MOUSE_BUTTON_WHEEL_UP)
		_check(not _game._view.is_overview(), "wheel can still reverse a transition")
		_finish_transition()
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
		_check(_game._view.is_overview(), "wheel down still enters overview")
		_finish_transition()
		_check(_game._nest_views == nests and _game.run.candy == candy, "world state preserved")
		_game.restart_run()
		_game.set_process(false)
		_game._window_has_focus = true
		_pinch(0.8)
		_check(_game._view.is_overview(), "restart clears previous gesture state")
		_game.queue_free()
		await get_tree().process_frame
	print("TRACKPAD VIEW: %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_view_ui(resolution: Vector2i) -> void:
	var dock: Control = _game._layout._tool_dock
	_check(
		_game._layout._view_switch.texture_normal == DiskDemoLayout.VIEW_ZOOM_OUT,
		"near view shows zoom-out glyph"
	)
	_game._view.zoom_steps(-1.0)
	_check(
		_game._layout._tool_dock.pipe_button.is_visible_in_tree(), "outgoing tools fade as a group"
	)
	_check(
		_game._layout._view_switch.texture_normal == DiskDemoLayout.VIEW_ZOOM_IN,
		"overview target shows zoom-in glyph"
	)
	# Sample the actual tween deterministically, independent of screenshot/GPU stalls.
	_game._layout._tool_dock._view_fade.pause()
	_game._layout._tool_dock._view_fade.custom_step(0.06)
	_check(
		dock.modulate.a > 0.0 and dock.modulate.a < 1.0, "dock fades out instead of disappearing"
	)
	_game._view._process(0.06)
	await _capture("out_fading", resolution)
	_game._layout._tool_dock._view_fade.custom_step(0.18)
	_game._view._process(0.24)
	_check(is_zero_approx(dock.modulate.a), "entire dock hidden during zoom")
	var technology: Button = _game._layout._tool_dock.technology_button
	_click(technology.get_global_rect().get_center())
	_check(not _game._layout.is_technology_open(), "invisible technology entry cannot open")
	await _capture("out_hidden", resolution)
	# A reversal must keep the dock hidden and use the final destination's glyph.
	_game._view.zoom_steps(1.0)
	_check(is_zero_approx(dock.modulate.a), "reversing zoom does not flash the dock")
	_check(
		_game._layout._view_switch.texture_normal == DiskDemoLayout.VIEW_ZOOM_OUT,
		"reversal updates the destination glyph"
	)
	_finish_transition()
	_check(is_zero_approx(dock.modulate.a), "fade-in begins only after zoom finishes")
	_game._layout._tool_dock._view_fade.pause()
	_game._layout._tool_dock._view_fade.custom_step(0.08)
	_check(dock.modulate.a > 0.0 and dock.modulate.a < 1.0, "dock fades back in")
	await _capture("near_returning", resolution)
	_game._layout._tool_dock._view_fade.play()
	await get_tree().create_timer(0.20).timeout
	_check(is_equal_approx(dock.modulate.a, 1.0), "near dock fully restored")
	_game._view.zoom_steps(-1.0)
	await get_tree().create_timer(0.18).timeout
	_finish_transition()
	await get_tree().create_timer(0.25).timeout
	_check(is_equal_approx(dock.modulate.a, 1.0), "overview dock fully restored")
	_check(
		not _game._layout._tool_dock.pipe_button.is_visible_in_tree(),
		"overview retains its normal entries"
	)
	await _capture("overview_ready", resolution)
	_game._view.focus_surface(Vector2.UP.angle())
	await get_tree().create_timer(0.18).timeout
	_game._view._process(0.3)
	_check(is_zero_approx(dock.modulate.a), "bubble focus path also hides the dock")
	await _capture("in_hidden", resolution)
	_finish_transition()
	await get_tree().create_timer(0.25).timeout
	_game._view.zoom_steps(-1.0)
	await get_tree().create_timer(0.04).timeout
	_game._layout._toggle_pause()
	var paused_alpha: float = dock.modulate.a
	await get_tree().create_timer(0.18, true).timeout
	_check(is_equal_approx(dock.modulate.a, paused_alpha), "pause freezes the fade")
	_game._layout._toggle_pause()
	_game.restart_run()
	_game._window_has_focus = true
	_check(is_equal_approx(dock.modulate.a, 1.0), "restart cancels the fade and restores dock")
	await get_tree().create_timer(0.25).timeout
	_check(is_equal_approx(dock.modulate.a, 1.0), "old fade cannot hide the restarted dock")
	_check(
		_game._layout._view_switch.texture_normal == DiskDemoLayout.VIEW_ZOOM_OUT,
		"restart restores near-view glyph"
	)


func _pan(delta: Vector2, point: Vector2 = Vector2(400, 180)) -> void:
	var event: InputEventPanGesture = InputEventPanGesture.new()
	event.position = point
	event.delta = delta
	get_viewport().push_input(event, true)


func _pinch(factor: float) -> void:
	var event: InputEventMagnifyGesture = InputEventMagnifyGesture.new()
	event.position = _point
	event.factor = factor
	get_viewport().push_input(event, true)


func _tab(echo: bool = false, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = true
	event.echo = echo
	event.shift_pressed = shift
	get_viewport().push_input(event, true)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	get_viewport().push_input(event, true)


func _wheel(button: MouseButton) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = _point
	event.button_index = button
	event.pressed = true
	get_viewport().push_input(event, true)


func _click(point: Vector2) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	get_viewport().push_input(event, true)


func _finish_transition() -> void:
	_game._view._process(_game._view.transition_seconds)
	_game._layout.set_view_switch_enabled(_game._can_toggle_view())


func _fresh_stroke() -> void:
	_finish_transition()
	await get_tree().create_timer(0.36).timeout
	_game._window_has_focus = true


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(label: String, resolution: Vector2i) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		"%s/%s_%dx%d.png" % [OUTPUT, label, resolution.x, resolution.y]
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
