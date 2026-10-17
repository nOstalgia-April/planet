extends Node

const Play = preload("res://features/场景预览/游玩预览.gd")
const Dialogue = preload("res://scripts/ui/mascot_dialogue.gd")

@export var talk_event_path: String = "":
	set(value):
		talk_event_path = value
		if is_node_ready():
			stop_dialogue_audio()
			_talk_audio_ready = (not value.is_empty() and GameAudio.has_events([value]))

# A clause can be a single character before punctuation (about 0.07 s of
# typing); its voice still sounds at least this long before stopping.
@export_range(0.0, 1.0, 0.05) var min_voice_seconds: float = 0.3

var _dialogue_audio: FmodEvent
var _talk_audio_ready: bool = false
var _voice_started_msec: int = 0
# Bumped by every start or stop, so a postponed stop that is no longer
# current does nothing.
var _stop_version: int = 0

@onready var game: Play = $Game
@onready var dialogue: Dialogue = $DialogueLayer/MascotDialogue
@onready var _toolbar: Control = $UI/Toolbar


func _ready() -> void:
	# Keep the formal scene's artwork and resize handling active without running tools.
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.set_process_unhandled_key_input(false)
	game._layout.set_process_unhandled_key_input(false)
	game._view.presentation_locked = true
	game._pipe.hide()
	game._net.hide()
	GameAudio.stop_music()
	_talk_audio_ready = (not talk_event_path.is_empty() and GameAudio.has_events([talk_event_path]))
	bind_dialogue_audio(dialogue)
	dialogue.dialogue_finished.connect(_on_dialogue_finished)
	$UI/Toolbar/Return.pressed.connect(return_to_menu)
	$UI/Toolbar/Replay.pressed.connect(replay)
	$UI/Toolbar/Advance.pressed.connect(advance)
	get_viewport().size_changed.connect(_layout_dialogue)
	_layout_dialogue()
	replay()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event.pressed and not key_event.echo:
		match key_event.keycode:
			KEY_ESCAPE:
				return_to_menu()
			KEY_R:
				replay()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				advance()
	# The preview owns keyboard input; the UI blocker owns background mouse input.
	get_viewport().set_input_as_handled()


func replay() -> void:
	stop_dialogue_audio()
	dialogue.play(dialogue.lines)


func advance() -> void:
	dialogue.advance()


func return_to_menu() -> void:
	stop_dialogue_audio()
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred("res://scenes/主菜单/主菜单.tscn")


# Each clause between punctuation plays the talk sound once from its start.
func bind_dialogue_audio(speaker: Dialogue) -> void:
	speaker.voice_started.connect(_on_voice_started)
	speaker.voice_stopped.connect(_on_voice_stopped)


# Stops at once (replay, leaving); clause ends go through _on_voice_stopped.
func stop_dialogue_audio() -> void:
	_stop_version += 1
	if _dialogue_audio != null:
		GameAudio.stop_loop(_dialogue_audio)
		_dialogue_audio = null


func _on_voice_started(_index: int) -> void:
	if _dialogue_audio != null:
		# Still within a short clause's minimum: keep that sound going.
		_stop_version += 1
		return
	if _talk_audio_ready:
		_dialogue_audio = GameAudio.start_loop(talk_event_path)
		_voice_started_msec = Time.get_ticks_msec()


func _on_voice_stopped() -> void:
	if _dialogue_audio == null:
		return
	var remaining: float = (
		min_voice_seconds - float(Time.get_ticks_msec() - _voice_started_msec) / 1000.0
	)
	if remaining <= 0.0:
		stop_dialogue_audio()
		return
	_stop_version += 1
	get_tree().create_timer(remaining, true, false, true).timeout.connect(
		_finish_postponed_stop.bind(_stop_version)
	)


func _finish_postponed_stop(version: int) -> void:
	if version == _stop_version:
		stop_dialogue_audio()


func _exit_tree() -> void:
	stop_dialogue_audio()


func _on_dialogue_finished() -> void:
	dialogue.dismiss_bubble()


func _layout_dialogue() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var factor: float = minf(viewport_size.x / 1280.0, viewport_size.y / 800.0)
	dialogue.scale = Vector2.ONE * factor
	dialogue.size = viewport_size / factor
	_toolbar.scale = Vector2.ONE * factor
	_toolbar.position = Vector2(24.0, 72.0) * factor
