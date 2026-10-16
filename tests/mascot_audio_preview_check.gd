extends Node

const Preview = preload("res://features/mascot_audio_preview/stage_audio_preview.gd")
const Opening = preload("res://features/mascot_audio_preview/opening_audio_preview.gd")
const Dialogue = preload("res://scripts/ui/mascot_dialogue.gd")
const PATHS: PackedStringArray = [
	"res://features/mascot_audio_preview/opening_audio_preview.tscn",
	"res://features/mascot_audio_preview/phase_two_audio_preview.tscn",
	"res://features/mascot_audio_preview/phase_three_audio_preview.tscn",
]

var _lines: PackedStringArray = []
var _failures: PackedStringArray = []
var _output: String
var _capture: bool


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_output = "res://artifacts/mascot_audio_%d" % int(Time.get_unix_time_from_system())
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	if _capture:
		assert(DisplayServer.get_name() != "headless")
		DirAccess.make_dir_recursive_absolute(_output)
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280, 800)
	for index: int in range(PATHS.size()):
		await _check_preview(index)
	if _capture:
		var manifest: FileAccess = FileAccess.open(
			_output.path_join("manifest.json"), FileAccess.WRITE
		)
		manifest.store_string(
			JSON.stringify(
				{
					"scenes": PATHS,
					"finished_at": Time.get_datetime_string_from_system(),
					"failures": _failures
				},
				"\t"
			)
		)
		print("CAPTURES: ", ProjectSettings.globalize_path(_output))
	if _failures.is_empty():
		print(
			"PASS: all three complete dialogue sequences, forms, talk/idle, replay, input, audio lifecycle and two viewport sizes."
		)
	else:
		print("FAIL: ", _failures)
	if _failures.is_empty():
		GameLifecycle.request_quit()
	else:
		get_tree().quit(1)


func _check_preview(index: int) -> void:
	var packed: PackedScene = load(PATHS[index]) as PackedScene
	var preview: Preview = packed.instantiate() as Preview
	preview.talk_event_path = "event:/Vacuum/Vacuum_Loading"
	packed = null
	var speakers: Array[Dialogue] = [preview.get_node("DialogueLayer/MascotDialogue") as Dialogue]
	if preview is Opening:
		speakers.append(preview.get_node("DialogueLayer/CompactDialogue") as Dialogue)
	_lines.clear()
	for speaker: Dialogue in speakers:
		speaker.line_started.connect(_on_line_started)
	add_child(preview)
	_check(not get_tree().paused, "Preview must not pause the FMOD master bus.")
	_check(not preview.game.is_processing(), "Background gameplay is stopped.")
	_check(preview.dialogue.presenter.selected_form == index, "The correct form is selected.")
	await get_tree().create_timer(0.25).timeout
	await _capture_frame("%d_entrance" % index)
	await _wait_for_typing(preview.dialogue)
	_check(
		preview.dialogue.presenter.sprite.animation == &"talk", "Typing uses the talk animation."
	)
	await _capture_frame("%d_talk" % index)
	# A real input completes the line without advancing its index.
	_key(KEY_SPACE)
	_check(preview.dialogue.phase == Dialogue.Phase.HOLDING, "Space completes a typing line.")
	_check(preview.dialogue.line_index == 0, "Completing a line does not skip it.")
	_check(preview.dialogue.presenter.sprite.animation == &"idle", "Complete lines return to idle.")
	await _check_layout(preview.dialogue, "%d_full_line" % index)
	var advance_button: Control = preview.get_node("UI/Toolbar/Advance") as Control
	_click(advance_button.get_global_transform_with_canvas() * (advance_button.size * 0.5))
	_check(preview.dialogue.line_index == 1, "The menu Advance button advances exactly once.")
	_check(preview.dialogue.phase == Dialogue.Phase.TYPING, "The next line is not also completed.")
	var replay_button: Control = preview.get_node("UI/Toolbar/Replay") as Control
	_click(replay_button.get_global_transform_with_canvas() * (replay_button.size * 0.5))
	_check(preview.dialogue.phase == Dialogue.Phase.ENTERING, "The menu Replay button still works.")
	_lines.clear()
	preview.replay()
	_check(preview.dialogue.phase == Dialogue.Phase.ENTERING, "Replay restarts the entrance.")
	for speaker: Dialogue in speakers:
		speaker.characters_per_second = 200.0
		speaker.punctuation_pause = 0.0
	var deadline: int = Time.get_ticks_msec() + 22000
	while Time.get_ticks_msec() < deadline:
		if index == 0:
			if (preview as Opening).segment == Opening.Segment.DONE:
				break
		elif preview.dialogue.phase == Dialogue.Phase.IDLE:
			break
		for speaker: Dialogue in speakers:
			if speaker.phase == Dialogue.Phase.HOLDING and speaker._phase_elapsed >= 0.08:
				_click(Vector2(80.0, 180.0))
		await get_tree().process_frame
	var expected_count: int = [13, 10, 8][index]
	_check(
		_lines.size() == expected_count,
		"Complete sequence has %d lines, got %d." % [expected_count, _lines.size()]
	)
	_check(preview.dialogue.phase == Dialogue.Phase.IDLE, "The complete preview remains in idle.")
	_check(not preview.dialogue.presenter.paused, "Final idle stays animated.")
	_check(not preview.dialogue.bubble.visible, "Final idle hides the speech bubble.")
	if preview is Opening:
		var opening: Opening = preview as Opening
		var expected: PackedStringArray = (
			opening.intro_lines
			+ opening.vacuum_lines
			+ opening.reaction_lines
			+ opening.closing_lines
		)
		_check(_lines == expected, "Opening preserves all four dialogue groups in order.")
	else:
		_check(_lines == preview.dialogue.lines, "Stage lines preserve their complete order.")
	await _capture_frame("%d_final_idle" % index)
	await _check_audio_lifecycle(preview)
	preview.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _check_audio_lifecycle(preview: Preview) -> void:
	# Use an existing Bank event only to verify real instance start/stop ownership.
	# This is a plumbing check, not a claim that mascot voice assets exist.
	preview.talk_event_path = "event:/Vacuum/Vacuum_Loading"
	preview.dialogue.characters_per_second = 15.0
	preview.dialogue.punctuation_pause = 0.22
	preview.replay()
	await _wait_for_typing(preview.dialogue)
	await _wait_for_audio(preview, true)
	_check(preview._dialogue_audio != null, "A configured Bank event starts on a clause.")
	# Every first line has punctuation before its end, so the clause stops mid-line.
	await _wait_for_audio(preview, false)
	_check(
		preview._dialogue_audio == null and preview.dialogue.phase == Dialogue.Phase.TYPING,
		"Punctuation inside a line releases the clause sound."
	)
	await _wait_for_audio(preview, true)
	_check(preview._dialogue_audio != null, "The next clause starts the sound again.")
	preview.advance()
	_check(preview._dialogue_audio == null, "Finishing a line releases its loop.")
	preview.replay()
	_check(preview._dialogue_audio == null, "Replay clears the previous sound.")
	await _wait_for_typing(preview.dialogue)
	await _wait_for_audio(preview, true)
	_check(preview._dialogue_audio != null, "Replay can start the configured event again.")
	preview.stop_dialogue_audio()
	_check(preview._dialogue_audio == null, "Leaving can stop the current sound.")
	preview.talk_event_path = ""


func _wait_for_audio(preview: Preview, playing: bool) -> void:
	var deadline: int = Time.get_ticks_msec() + 3000
	while (preview._dialogue_audio != null) != playing and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _wait_for_typing(speaker: Dialogue) -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while speaker.phase != Dialogue.Phase.TYPING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(speaker.phase == Dialogue.Phase.TYPING, "Entrance naturally reaches typing.")


func _check_layout(speaker: Dialogue, label: String) -> void:
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_tree().root.size = dimensions
		await get_tree().process_frame
		await get_tree().process_frame
		_check(
			speaker.text_label.get_content_height() <= speaker.text_label.size.y,
			"Full text fits its bubble."
		)
		await _capture_frame("%s_%dx%d" % [label, dimensions.x, dimensions.y])


func _capture_frame(label: String) -> void:
	if not _capture:
		return
	await RenderingServer.frame_post_draw
	_check(
		get_viewport().get_texture().get_image().save_png(_output.path_join(label + ".png")) == OK,
		"Screenshot saves."
	)


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)
	event.pressed = false
	get_viewport().push_input(event, true)


func _click(position: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = position
	click.global_position = position
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	get_viewport().push_input(click, true)
	click.pressed = false
	get_viewport().push_input(click, true)


func _on_line_started(_index: int, text: String) -> void:
	_lines.append(text)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
