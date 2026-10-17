extends Node

const Preview = preload("res://features/场景预览/地鼠捕获预览.gd")
const PREVIEW_SCENE: PackedScene = preload("res://features/场景预览/地鼠捕获预览.tscn")

var _failures: Array[String] = []
var _sampled_pointer: Vector2


func _ready() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	get_tree().root.size = Vector2i(1280, 800)
	var preview: Preview = PREVIEW_SCENE.instantiate() as Preview
	get_tree().root.add_child(preview)
	get_tree().current_scene = preview
	await get_tree().process_frame
	await get_tree().process_frame
	preview._apply_layout()
	preview.set_process(false)
	preview._view.set_process(false)
	preview._window_has_focus = true
	var ordinary: Button = preview.get_node("PreviewControls/Controls/Buttons/Ordinary") as Button
	var valuable: Button = preview.get_node("PreviewControls/Controls/Buttons/Valuable") as Button
	var retry: Button = preview.get_node("PreviewControls/Controls/Buttons/Retry") as Button
	_check(
		ordinary.pressed.is_connected(preview._set_preview_kind.bind(false)),
		"Ordinary button is connected to a valid preview callback."
	)
	_check(
		valuable.pressed.is_connected(preview._set_preview_kind.bind(true)),
		"Valuable button is connected to a valid preview callback."
	)
	_check(
		retry.pressed.is_connected(preview._restart_preview_actor),
		"Retry button is connected to a valid preview callback."
	)
	for high_value: bool in [true, false]:
		var kind_button: Button = valuable if high_value else ordinary
		kind_button.pressed.emit()
		_check(preview._preview_actor.high_value == high_value, "Kind button changes the actor.")
		_check(kind_button.button_pressed, "Kind button reflects the selected variant.")
		var previous_id: int = preview._preview_actor.get_instance_id()
		retry.pressed.emit()
		_check(
			preview._preview_actor.get_instance_id() != previous_id,
			"Retry button replaces the current actor."
		)
		_check(preview._slimes.size() == 1, "Manual retry leaves exactly one active actor.")
		await _check_capture(preview, high_value)
	preview.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print(
			"PASS: mole preview loads, buttons work, basic suction settles once, and retry preserves kind"
		)
	else:
		for failure: String in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_capture(preview: Preview, high_value: bool) -> void:
	var actor: Preview.DrillMonster = preview._preview_actor
	actor.set_process(false)
	if "--capture" in OS.get_cmdline_user_args():
		for clip_time: float in [0.25, 0.625, 0.875]:
			actor.art.animation_player.pause()
			actor.art.animation_player.seek(clip_time, true)
			actor.refresh_presentation()
			await _capture(preview, "emerge_%03d" % roundi(clip_time * 1000.0))
	actor._process(1.01)
	actor.refresh_presentation()
	var pointer: Vector2 = actor.get_capture_hit_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = pointer
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await get_tree().process_frame
	_mouse(pointer, false)
	_step_capture(preview, pointer, 0.1)
	_check(actor.can_capture(), "Preview actor becomes exposed.")
	_check(not actor.has_node("CaptureCue"), "Preview has no hold prompt.")
	_check_pipe_position(preview, "Preview suction")
	preview._capture_at(0.0, actor.get_capture_point(), false)
	var duration: float = preview.run.get_pipe_capture_seconds()
	var candy_before: int = preview.run.candy
	var caught_before: int = preview._caught_count
	_step_capture(preview, pointer, duration * 0.5)
	_check(is_equal_approx(actor.capture_progress, 0.5), "Hovering alone advances suction.")
	_check(actor.art._suction, "Suction displays the struggling expression.")
	await _capture(preview, "suction")
	_mouse(pointer, true)
	_mouse(pointer, false)
	_check(is_equal_approx(actor.capture_progress, 0.5), "Mouse release does not reset suction.")
	_step_capture(preview, Vector2(-100, -100), 0.1)
	_check(actor.capture_progress == 0.0 and not actor.art._suction, "Leaving resets suction.")
	_step_capture(preview, pointer, duration + 0.001)
	_check(preview._caught_count == caught_before + 1, "Suction increments the count once.")
	_check(preview.run.candy > candy_before, "Capture pays treasure.")
	_check(preview._slimes.is_empty(), "Capture removes the actor.")
	await _capture(preview, "caught")
	var candy_after: int = preview.run.candy
	_step_capture(preview, pointer, 0.0)
	_check(preview.run.candy == candy_after, "Capture cannot pay twice.")
	preview._process(preview.retry_seconds * 0.5)
	preview._process(preview.retry_seconds * 0.6)
	_check(is_instance_valid(preview._preview_actor), "Automatic retry spawns a new actor.")
	_check(preview._slimes.size() == 1, "Automatic retry creates exactly one active actor.")
	_check(
		preview._preview_actor.high_value == high_value, "Automatic retry preserves the variant."
	)


func _step_capture(preview: Preview, pointer: Vector2, seconds: float) -> void:
	_sampled_pointer = pointer
	if DisplayServer.get_name() == "headless":
		# Headless has no OS pointer, but Input still tracks the injected held button.
		var holding: bool = preview.update_pointer_release_state()
		var world_pointer: Vector2 = (
			preview._world.get_global_transform_with_canvas().affine_inverse() * pointer
		)
		preview._drive_tool(seconds, world_pointer, holding)
	else:
		preview.get_viewport().warp_mouse(pointer)
		# Windows rounds warps to physical pixels; compare against the actual sampled input.
		_sampled_pointer = preview.get_viewport().get_mouse_position()
		preview._process(seconds)


func _check_pipe_position(preview: Preview, label: String) -> void:
	_check(preview._pipe.visible, label + " preserves the visible vacuum.")
	_check(
		(
			preview._pipe.get_global_transform_with_canvas().origin.distance_to(_sampled_pointer)
			< 0.01
		),
		label + " keeps the vacuum mouth following the pointer."
	)


func _capture(preview: Preview, label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/mole_basic_suction_20261017")
	var variant: String = "valuable" if preview._preview_valuable else "ordinary"
	var path: String = (
		"res://artifacts/mole_basic_suction_20261017/preview_%s_%s.png" % [variant, label]
	)
	_check(
		get_viewport().get_texture().get_image().save_png(path) == OK,
		"Fresh preview capture saved."
	)
	print("CAPTURE: ", path)


func _mouse(pointer: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = pointer
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
