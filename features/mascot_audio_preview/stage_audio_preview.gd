extends Node

const Play = preload("res://features/场景预览/游玩预览.gd")
const Dialogue = preload("res://scripts/ui/mascot_dialogue.gd")

@export var talk_event_path: String = "":
	set(value):
		talk_event_path = value
		if is_node_ready():
			stop_dialogue_audio()
			_talk_audio_ready = (not value.is_empty() and GameAudio.has_events([value]))

var _dialogue_audio: FmodEvent
var _talk_audio_ready: bool = false

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
	speaker.voice_stopped.connect(stop_dialogue_audio)


func stop_dialogue_audio() -> void:
	if _dialogue_audio != null:
		GameAudio.stop_loop(_dialogue_audio)
		_dialogue_audio = null


func _on_voice_started(_index: int) -> void:
	stop_dialogue_audio()
	if _talk_audio_ready:
		_dialogue_audio = GameAudio.start_loop(talk_event_path)


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
