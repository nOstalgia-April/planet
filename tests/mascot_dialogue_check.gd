extends Node

const Dialogue = preload("res://scripts/ui/mascot_dialogue.gd")
const DialogueScene: PackedScene = preload("res://scenes/ui/mascot_dialogue.tscn")
const PREVIEW_PATH: String = "res://features/mascot_dialogue_preview/mascot_dialogue_preview.tscn"
const EXPECTED_LINES: Array[String] = [
	"喂——小心脚下！你差点踩到我们家刚冒出来的小家伙！",
	"你是……清扫员？来帮我们治理巢穴和生态的？",
]

var _dialogue: Dialogue
var _capture_enabled: bool = false
var _output_directory: String = ""
var _captures: Array[Dictionary] = []
var _failures: PackedStringArray = PackedStringArray()
var _started_indices: PackedInt32Array = PackedInt32Array()
var _started_texts: PackedStringArray = PackedStringArray()
var _finished_indices: PackedInt32Array = PackedInt32Array()
var _completion_count: int = 0
var _entrance_count: int = 0
var _voice_starts: int = 0
var _voice_stops: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if _capture_enabled and DisplayServer.get_name() == "headless":
		_check(false, "--capture needs a graphical renderer.")
		_finish()
		return
	var preview_scene: PackedScene = load(PREVIEW_PATH) as PackedScene
	_check_preview_configuration(preview_scene)
	var fixture: Node
	if _capture_enabled:
		_prepare_output()
		get_tree().root.mode = Window.MODE_WINDOWED
		get_tree().root.size = Vector2i(1920, 1080)
		fixture = preview_scene.instantiate()
		_dialogue = fixture.get_node("DialogueLayer/MascotDialogue") as Dialogue
	else:
		_dialogue = DialogueScene.instantiate() as Dialogue
		_dialogue.lines = PackedStringArray(EXPECTED_LINES)
		fixture = _dialogue
	preview_scene = null
	_dialogue.line_started.connect(_on_line_started)
	_dialogue.line_finished.connect(_on_line_finished)
	_dialogue.dialogue_finished.connect(_on_dialogue_finished)
	get_tree().root.add_child(fixture)
	_dialogue.presenter.entrance_finished.connect(_on_entrance_finished)
	_check(_dialogue.phase == Dialogue.Phase.ENTERING, "Autoplay starts with the entrance.")
	_check(not _dialogue.bubble.visible, "The bubble starts hidden.")
	_check(_dialogue.text_label.visible_characters == 0, "Entrance contains no dialogue text.")
	if _capture_enabled:
		await _check_background_input(fixture)
	await _check_manual_sequence()
	if _dialogue.phase == Dialogue.Phase.FINISHED:
		await _check_restart_and_stop()
		await _check_mouse_input()
		await _check_line_started_advance()
		await _check_clause_voice()
	_dialogue.stop()
	fixture.queue_free()
	_dialogue = null
	fixture = null
	await get_tree().process_frame
	await get_tree().process_frame
	_finish()


func _check_preview_configuration(preview_scene: PackedScene) -> void:
	var state: SceneState = preview_scene.get_state()
	var found_lines: bool = false
	for node_index in range(state.get_node_count()):
		var node_path: String = String(state.get_node_path(node_index)).trim_prefix("./")
		if node_path != "DialogueLayer/MascotDialogue":
			continue
		for property_index in range(state.get_node_property_count(node_index)):
			if state.get_node_property_name(node_index, property_index) == &"lines":
				found_lines = true
				_check(
					(
						state.get_node_property_value(node_index, property_index)
						== PackedStringArray(EXPECTED_LINES)
					),
					"Preview lines preserve both original sentences exactly."
				)
	_check(found_lines, "The real preview supplies the dialogue lines.")


func _check_background_input(preview: Node) -> void:
	var game: Node = preview.get_node("Game")
	_check(
		not game.is_processing() and not game.is_processing_input(),
		"The ready preview stops gameplay and its direct input while artwork remains active."
	)
	await get_tree().process_frame
	var pause_button: Control = game.get_node("HUD/Interface/GameMenu/Toolbar/Pause") as Control
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	click.pressed = true
	click.position = pause_button.get_global_transform_with_canvas() * (pause_button.size * 0.5)
	click.global_position = click.position
	get_viewport().push_input(click, true)
	var release: InputEventMouseButton = click.duplicate() as InputEventMouseButton
	release.pressed = false
	release.button_mask = 0
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	_check(not get_tree().paused, "Clicking the background Pause button cannot pause the preview.")
	get_tree().paused = false
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	var escape_release: InputEventKey = escape.duplicate() as InputEventKey
	escape_release.pressed = false
	get_viewport().push_input(escape_release, true)
	await get_tree().process_frame
	_check(not get_tree().paused, "Escape cannot pause the dialogue preview.")
	get_tree().paused = false


func _check_manual_sequence() -> void:
	var entrance_captured: bool = false
	var opening_seen: bool = false
	var partial_seen: Array[bool] = [false, false]
	var complete_seen: Array[bool] = [false, false]
	var last_visible: PackedInt32Array = PackedInt32Array([0, 0])
	var reveal_steps: PackedInt32Array = PackedInt32Array([0, 0])
	var deadline: int = Time.get_ticks_msec() + 30000
	while _dialogue.phase != Dialogue.Phase.FINISHED and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var index: int = _dialogue.line_index
		match _dialogue.phase:
			Dialogue.Phase.ENTERING:
				_check(not _dialogue.bubble.visible, "The bubble remains hidden during entrance.")
				if not entrance_captured and _dialogue.presenter.elapsed >= 0.3:
					entrance_captured = true
					await _capture_stage("01_entrance")
			Dialogue.Phase.OPENING:
				opening_seen = true
				_check(
					_entrance_count == 1, "The bubble opens after the natural entrance finishes."
				)
				_check(_dialogue.bubble.visible, "Opening makes the bubble visible.")
				_check(_dialogue.text_label.visible_characters == 0, "Opening precedes typing.")
			Dialogue.Phase.TYPING:
				_check(opening_seen, "Typing starts after the bubble opening.")
				_check(_dialogue.presenter.speaking, "Typing enables speaking.")
				_check(
					_dialogue.presenter.sprite.animation == &"talk", "Typing plays the talk clip."
				)
				_check(
					_dialogue.text_label.get_parsed_text() == EXPECTED_LINES[index],
					"Exact line text."
				)
				var visible_count: int = _dialogue.text_label.visible_characters
				_check(
					visible_count >= last_visible[index], "Visible characters never move backwards."
				)
				if visible_count > last_visible[index]:
					reveal_steps[index] += 1
					last_visible[index] = visible_count
				if not partial_seen[index] and visible_count >= 8:
					partial_seen[index] = true
					_check(
						visible_count < EXPECTED_LINES[index].length(), "A partial line is visible."
					)
					await _capture_stage("%02d_line_%d_partial" % [2 + index * 2, index + 1])
			Dialogue.Phase.HOLDING:
				_check(not _dialogue.presenter.speaking, "A completed line stops speaking.")
				_check(_dialogue.presenter.sprite.animation == &"idle", "Reading pauses play idle.")
				_check(
					_dialogue.text_label.visible_characters == EXPECTED_LINES[index].length(),
					"Reading pauses retain the complete line."
				)
				if not complete_seen[index]:
					complete_seen[index] = true
					# Let the final character finish its pop before freezing the complete-line image.
					if _capture_enabled:
						await get_tree().create_timer(0.25).timeout
					await _capture_stage("%02d_line_%d_complete" % [3 + index * 2, index + 1], true)
					await get_tree().create_timer(2.5).timeout
					_check(
						_dialogue.phase == Dialogue.Phase.HOLDING and _dialogue.line_index == index,
						"A complete line waits beyond the former automatic delay for confirmation."
					)
					_click(Vector2(80.0, 180.0))
	_check(_dialogue.phase == Dialogue.Phase.FINISHED, "The click-confirmed sequence completes.")
	_check(
		_started_indices == PackedInt32Array([0, 1]), "Lines start once in their original order."
	)
	_check(
		_started_texts == PackedStringArray(EXPECTED_LINES),
		"Line signals preserve the original text."
	)
	_check(_finished_indices == PackedInt32Array([0, 1]), "Both lines finish once in order.")
	_check(
		reveal_steps[0] > 2 and reveal_steps[1] > 2,
		"Both lines visibly reveal over multiple frames."
	)
	_check(complete_seen == [true, true], "Both complete lines have a reading pause.")
	_check(_entrance_count == 1, "The entrance completion emits once.")
	_check(
		not _capture_enabled or _captures.size() == 7,
		"All five stages and both complete-line sizes are captured."
	)
	await get_tree().create_timer(0.3).timeout
	_dialogue.advance()
	_dialogue.advance()
	_check(_completion_count == 1, "Completion emits once, including repeated advance calls.")


func _check_mouse_input() -> void:
	# Include a GUI blocker, as used by audio previews, and a button with child artwork.
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	var blocker: Control = Control.new()
	layer.add_child(blocker)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var button: Button = Button.new()
	button.position = Vector2(20.0, 20.0)
	button.size = Vector2(120.0, 50.0)
	layer.add_child(button)
	var artwork: Control = Control.new()
	button.add_child(artwork)
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.mouse_filter = Control.MOUSE_FILTER_PASS
	_dialogue.play(PackedStringArray(EXPECTED_LINES))
	if not await _wait_for_first_line():
		layer.queue_free()
		return
	_dialogue.set_process(false)
	var before: int = _dialogue.text_label.visible_characters
	_click(Vector2(60.0, 40.0))
	_check(_dialogue.text_label.visible_characters == before, "Menu artwork cannot complete text.")
	_check(_dialogue.phase == Dialogue.Phase.TYPING, "Menu clicks leave typing active.")
	_click(Vector2(80.0, 180.0), MOUSE_BUTTON_RIGHT)
	_check(_dialogue.phase == Dialogue.Phase.TYPING, "Right clicks cannot confirm dialogue.")
	_click(Vector2(80.0, 180.0))
	_check(_dialogue.phase == Dialogue.Phase.HOLDING, "A left click completes the current line.")
	_check(_dialogue.line_index == 0, "The completion click does not skip to the next line.")
	_click(Vector2(60.0, 40.0))
	_check(_dialogue.line_index == 0, "Menu clicks cannot confirm a completed line.")
	_click(Vector2(700.0, 400.0))
	_check(_dialogue.line_index == 1, "A second screen click starts the next line.")
	_click(Vector2(80.0, 180.0))
	_click(Vector2(80.0, 180.0))
	_check(_dialogue.phase == Dialogue.Phase.FINISHED, "The final line also needs confirmation.")
	_dialogue.stop()
	_click(Vector2(80.0, 180.0))
	_check(_dialogue.phase == Dialogue.Phase.HIDDEN, "Hidden dialogue ignores screen clicks.")
	_dialogue.set_process(true)
	layer.queue_free()
	await get_tree().process_frame


func _click(position: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = position
	click.global_position = position
	click.button_index = button
	click.pressed = true
	get_viewport().push_input(click, true)
	var release: InputEventMouseButton = click.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release, true)


func _check_restart_and_stop() -> void:
	_dialogue.play(_dialogue.lines)
	if not await _wait_for_first_line():
		return
	# This is the same API used by the preview's R shortcut, now invoked during typing.
	_dialogue.play(_dialogue.lines)
	_reset_observations()
	_check(_dialogue.phase == Dialogue.Phase.ENTERING, "Replay returns to entrance.")
	_check(not _dialogue.bubble.visible, "Replay hides the previous bubble.")
	_check(_dialogue.text_label.visible_characters == 0, "Replay clears the previous text.")
	if not await _wait_for_first_line():
		return
	_check(_started_indices == PackedInt32Array([0]), "Replay starts at the first line once.")
	_check(_finished_indices.is_empty() and _completion_count == 0, "Replay has no old completion.")
	_dialogue.stop()
	var stopped_count: int = _dialogue.text_label.visible_characters
	await get_tree().create_timer(0.4).timeout
	_check(_dialogue.phase == Dialogue.Phase.HIDDEN, "Stopped dialogue remains hidden.")
	_check(
		not _dialogue.visible and not _dialogue.bubble.visible, "Stop hides character and bubble."
	)
	_check(_dialogue.presenter.paused, "Stop pauses the presenter.")
	_check(_dialogue.text_label.visible_characters == stopped_count, "Stopped text cannot advance.")
	_check(
		_finished_indices.is_empty() and _completion_count == 0, "Stop cancels pending progress."
	)
	_dialogue.play(PackedStringArray(EXPECTED_LINES))
	_reset_observations()
	if not await _wait_for_first_line():
		return
	_dialogue.advance()
	_check(_dialogue.phase == Dialogue.Phase.HOLDING, "Advance completes only the current line.")
	_dialogue.advance()
	_check(_dialogue.line_index == 1, "The next advance starts the second line.")
	_dialogue.advance()
	_dialogue.advance()
	await get_tree().create_timer(0.3).timeout
	_check(_started_indices == PackedInt32Array([0, 1]), "Play after stop has a fresh line order.")
	_check(
		_finished_indices == PackedInt32Array([0, 1]), "Play after stop finishes each line once."
	)
	_check(_completion_count == 1, "Play after stop completes once without stale timing.")


func _wait_for_first_line() -> bool:
	var deadline: int = Time.get_ticks_msec() + 5000
	while _dialogue.phase != Dialogue.Phase.TYPING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var reached: bool = _dialogue.phase == Dialogue.Phase.TYPING and _dialogue.line_index == 0
	_check(reached, "A fresh play naturally reaches the first line.")
	return reached


func _check_line_started_advance() -> void:
	_dialogue.line_started.connect(_advance_started_line, CONNECT_ONE_SHOT)
	_dialogue.play(PackedStringArray(EXPECTED_LINES))
	_reset_observations()
	var deadline: int = Time.get_ticks_msec() + 5000
	while _dialogue.phase != Dialogue.Phase.HOLDING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(
		_dialogue.phase == Dialogue.Phase.HOLDING and _dialogue.line_index == 0,
		"A synchronous line_started advance completes the first line."
	)
	_check(
		_finished_indices == PackedInt32Array([0]),
		"A synchronous line_started advance emits line_finished once."
	)
	if _dialogue.line_started.is_connected(_advance_started_line):
		_dialogue.line_started.disconnect(_advance_started_line)
	_dialogue.stop()


func _check_clause_voice() -> void:
	_dialogue.voice_started.connect(_on_voice_started)
	_dialogue.voice_stopped.connect(_on_voice_stopped)
	var speed: float = _dialogue.characters_per_second
	_dialogue.characters_per_second = 40.0
	_dialogue.play(PackedStringArray(EXPECTED_LINES))
	_voice_starts = 0
	_voice_stops = 0
	var deadline: int = Time.get_ticks_msec() + 8000
	while _dialogue.phase != Dialogue.Phase.HOLDING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	# 喂 / 小心脚下 / 你差点……小家伙: dashes and the final mark close each clause.
	_check(
		_voice_starts == 3 and _voice_stops == 3,
		"Each punctuation-separated clause starts and stops the voice once, got %d/%d."
		% [_voice_starts, _voice_stops]
	)
	_dialogue.advance()
	while _voice_starts == 3 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_voice_starts == 4 and _voice_stops == 3, "The next line opens a new clause.")
	_dialogue.advance()
	_check(_voice_stops == 4, "Skipping a typing line stops its clause voice.")
	_dialogue.stop()
	_check(_voice_starts == _voice_stops, "Stopping leaves no clause voice running.")
	_dialogue.characters_per_second = speed
	_dialogue.voice_started.disconnect(_on_voice_started)
	_dialogue.voice_stopped.disconnect(_on_voice_stopped)


func _on_voice_started(_index: int) -> void:
	_voice_starts += 1


func _on_voice_stopped() -> void:
	_voice_stops += 1


func _advance_started_line(_index: int, _text: String) -> void:
	_dialogue.advance()


func _capture_stage(label: String, both_sizes: bool = false) -> void:
	if not _capture_enabled:
		return
	_dialogue.set_process(false)
	_dialogue.presenter.paused = true
	var dimensions: Array[Vector2i] = [Vector2i(1920, 1080)]
	if both_sizes:
		dimensions.append(Vector2i(1280, 800))
	for resolution in dimensions:
		get_tree().root.size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_tree().root.get_texture().get_image()
		var filename: String = "%s_%dx%d.png" % [label, resolution.x, resolution.y]
		_check(image.get_size() == resolution, "Capture uses the requested output dimensions.")
		_check(
			image.save_png(_output_directory.path_join(filename)) == OK,
			"Capture saves successfully."
		)
		(
			_captures
			. append(
				{
					"file": filename,
					"captured_at": Time.get_datetime_string_from_system(),
					"phase": Dialogue.Phase.keys()[_dialogue.phase],
					"line_index": _dialogue.line_index,
					"visible_characters": _dialogue.text_label.visible_characters,
					"text": _dialogue.text_label.get_parsed_text(),
					"animation": String(_dialogue.presenter.sprite.animation),
					"width": image.get_width(),
					"height": image.get_height(),
				}
			)
		)
	get_tree().root.size = Vector2i(1920, 1080)
	await get_tree().process_frame
	_dialogue.presenter.paused = false
	_dialogue.set_process(true)


func _prepare_output() -> void:
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	_output_directory = "res://artifacts/mascot_dialogue_%s_%d" % [timestamp, Time.get_ticks_usec()]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output_directory = argument.trim_prefix("--output=")
	_output_directory = ProjectSettings.globalize_path(_output_directory)
	_check(
		DirAccess.make_dir_recursive_absolute(_output_directory) == OK, "Capture directory exists."
	)


func _reset_observations() -> void:
	_started_indices.clear()
	_started_texts.clear()
	_finished_indices.clear()
	_completion_count = 0
	_entrance_count = 0


func _on_line_started(index: int, text: String) -> void:
	_started_indices.append(index)
	_started_texts.append(text)


func _on_line_finished(index: int) -> void:
	_finished_indices.append(index)


func _on_dialogue_finished() -> void:
	_completion_count += 1


func _on_entrance_finished() -> void:
	_entrance_count += 1


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
		push_error(message)


func _finish() -> void:
	if _capture_enabled and not _output_directory.is_empty():
		var manifest: FileAccess = FileAccess.open(
			_output_directory.path_join("manifest.json"), FileAccess.WRITE
		)
		if manifest != null:
			var report: Dictionary = {
				"scene": PREVIEW_PATH,
				"captures": _captures,
				"failures": _failures,
				"finished_at": Time.get_datetime_string_from_system(),
			}
			manifest.store_string(JSON.stringify(report, "\t") + "\n")
			manifest.close()
		else:
			_check(false, "Capture manifest saves successfully.")
		print("CAPTURES: ", _output_directory)
	if _failures.is_empty():
		print(
			"PASS: mascot entrance, typing/talk/idle, click completion and confirmation, menu exclusion, replay and stop/play."
		)
	else:
		print("FAIL: mascot dialogue checks: ", _failures)
	get_tree().quit(0 if _failures.is_empty() else 1)
