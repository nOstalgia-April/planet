extends "res://tests/story_flow_check.gd"


func _run() -> void:
	get_tree().create_timer(100.0, true, false, true).timeout.connect(_timeout)
	_output = "res://artifacts/opening_view_check_%d" % Time.get_unix_time_from_system()
	_game = GameScene.instantiate() as Game
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	_flow = _game.story
	await _close_note(_flow.briefing)
	await _wait_talk(Flow.Kind.OPENING)
	_check(_game._view.is_overview(), "NPC speaks in overview")
	_check(not _game._restoration.core.is_processing(), "core stays still during opening dialogue")
	_check(_game._slimes.is_empty(), "no opening monsters before the player enters")
	await _key(KEY_TAB)
	_check(_game._view.is_overview(), "Tab cannot skip opening dialogue")
	await _capture("overview_dialogue")
	await _finish_dialogue()
	_check(_flow.phase == Flow.Phase.WAIT_VIEW, "dialogue waits for a view action")
	_check(is_equal_approx(_flow.view_hint_hold_seconds, 5.0), "hint holds for five seconds")
	_check(is_equal_approx(_flow.view_hint_fade_seconds, 3.0), "hint fades over three seconds")
	_check(_flow.view_hint.visible, "view hint appears after dialogue")
	_check(_flow.view_hint.text == "滚动滚轮 或 按 TAB 切换视角", "approved hint text is exact")
	_check(_game._restoration.core.is_processing(), "core resumes while waiting for the player")
	var clock: float = _game.run.nests[0].spawn_clock
	await get_tree().create_timer(1.2).timeout
	await _key(KEY_ENTER)
	await _click()
	_check(
		_flow.phase == Flow.Phase.WAIT_VIEW, "time, Enter and clicks do not complete the tutorial"
	)
	_check(_game._slimes.is_empty(), "waiting does not spawn monsters")
	_check(is_equal_approx(clock, _game.run.nests[0].spawn_clock), "waiting freezes production")
	for nest: NestView in _game._nest_views:
		_check(is_zero_approx(nest.emergence_progress), "nests wait for the camera entrance")
	await _capture("view_hint")
	await _key(KEY_ESCAPE)
	_check(get_tree().paused, "pause works while waiting")
	var paused_elapsed: float = _flow._elapsed
	await get_tree().create_timer(0.25, true, false, true).timeout
	_check(is_equal_approx(_flow._elapsed, paused_elapsed), "pause freezes the hint countdown")
	await _key(KEY_TAB)
	_check(_flow.phase == Flow.Phase.WAIT_VIEW, "paused Tab does not continue")
	await _key(KEY_ESCAPE)
	var saved_story: Dictionary = _flow.capture_save()
	var saved_world: Dictionary = _game.capture_gameplay_save()
	await _reload(saved_world, saved_story)
	_check(_flow.phase == Flow.Phase.WAIT_VIEW, "reload resumes the pending view prompt")
	_check(not _flow.narrative.visible and _flow.view_hint.visible, "reload does not replay NPC")
	_check(_game._restoration.core.is_processing(), "reload keeps the waiting core animated")
	await _key(KEY_TAB)
	_check(_flow.phase == Flow.Phase.ZOOMING, "Tab starts the camera entrance")
	_check(not _flow.view_hint.visible, "camera entrance clears the hint")
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _key(KEY_TAB)
	_check(
		is_equal_approx(_game._view.target_zoom, 1.0), "repeat input cannot reverse the entrance"
	)
	var zoom_story: Dictionary = _flow.capture_save()
	var zoom_world: Dictionary = _game.capture_gameplay_save()
	await _reload(zoom_world, zoom_story)
	_check(_flow.phase == Flow.Phase.ZOOMING, "reload continues camera entrance")
	var deadline: int = Time.get_ticks_msec() + 12000
	while _flow.phase != Flow.Phase.LANDING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_flow.phase == Flow.Phase.LANDING, "nests emerge and launch monsters after entrance")
	var count: int = _game._slimes.size()
	_check(count > 0, "opening produces its original monsters")
	var landing_story: Dictionary = _flow.capture_save()
	var landing_world: Dictionary = _game.capture_gameplay_save()
	await _reload(landing_world, landing_story)
	await _wait_idle()
	_check(_game._slimes.size() == count, "reload does not duplicate opening monsters")
	_check(not _game._view.is_overview(), "original gameplay continues in near view")
	_check(_flow.seen.count(Flow.Kind.OPENING) == 1, "opening dialogue is recorded once")
	await _capture("near_gameplay")
	for button: MouseButton in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		await _reload(saved_world, saved_story)
		await _wheel(button)
		_check(
			_flow.phase == Flow.Phase.ZOOMING, "either wheel direction accepts the initial prompt"
		)
		await _wait_idle()
		_check(_game._slimes.size() == count, "wheel entrance produces one opening group")
	await _reload(saved_world, saved_story)
	while _flow.phase == Flow.Phase.WAIT_VIEW and _flow._elapsed < 4.9:
		_check(is_equal_approx(_flow.view_hint.modulate.a, 1.0), "hint remains opaque during hold")
		await get_tree().process_frame
	_check(_flow.phase == Flow.Phase.WAIT_VIEW, "no automatic entrance before five seconds")
	while _flow.phase == Flow.Phase.WAIT_VIEW and _flow._elapsed < 6.5:
		await get_tree().process_frame
	_check(absf(_flow.view_hint.modulate.a - 0.5) < 0.06, "hint is half faded at 6.5 seconds")
	await _capture("view_hint_fading")
	var fading_story: Dictionary = _flow.capture_save()
	await _reload(saved_world, fading_story)
	_check(
		absf(_flow._elapsed - float(fading_story.view_hint_elapsed)) < 0.1,
		"reload preserves fade time"
	)
	_check(absf(_flow.view_hint.modulate.a - 0.5) < 0.1, "reload preserves fade opacity")
	var remaining: float = 8.0 - _flow._elapsed
	var before: int = Time.get_ticks_msec()
	while _flow.phase == Flow.Phase.WAIT_VIEW:
		await get_tree().process_frame
	var waited: float = float(Time.get_ticks_msec() - before) / 1000.0
	_check(absf(waited - remaining) < 0.15, "automatic entrance occurs at eight seconds")
	_check(_flow.phase == Flow.Phase.ZOOMING, "fully faded hint automatically enters the planet")
	_check(not _flow.view_hint.visible, "automatic entrance clears the hint")
	await _wait_idle()
	_check(_game._slimes.size() == count, "automatic entrance continues the original opening")
	await _reload(saved_world, saved_story)
	_game.restart_run()
	_check(not _flow.view_hint.visible, "restart clears the old prompt")
	_check(_flow.phase == Flow.Phase.NOTE, "restart begins with the original note")
	_check(not _game._restoration.core.is_processing(), "restart resets the core hold")
	_game.story.cancel()
	_game.queue_free()
	get_tree().current_scene = null
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_equal_approx(Engine.time_scale, 1.0), "cleanup restores the world clock")
	if _failures.is_empty():
		print(
			"PASS: overview dialogue, core animation, 5s hold + 3s fade, automatic entrance, Tab/wheel, pause, saves and restart."
		)
	else:
		print("FAIL: ", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _reload(world: Dictionary, story: Dictionary) -> void:
	_flow.cancel()
	_game.restore_gameplay_save(world)
	_flow.restore_save(story)
	await get_tree().process_frame


func _wheel(button: MouseButton) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = get_viewport().get_visible_rect().size * Vector2(0.5, 0.4)
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	# Hold the guide clock while artwork still updates its screen-space masks on resize.
	var was_processing: bool = _flow.is_processing()
	_flow.set_process(false)
	await super._capture(label)
	_flow.set_process(was_processing)
