extends Control

signal finished

const Dialogue = preload("res://scripts/ui/mascot_dialogue.gd")

enum Phase { CLOSED, UNROLLING, TYPING, READING, CLOSING }

@export var heading: String
@export_multiline var first_section: String
@export_multiline var second_section: String
@export_multiline var third_section: String
@export var white_paper: bool = false
@export_range(0.6, 1.0, 0.01) var paper_scale: float = 0.82
@export_group("Timing")
@export_range(10.0, 90.0, 1.0) var characters_per_second: float = 45.0
@export_range(0.1, 2.0, 0.05) var unroll_seconds: float = 0.65
@export_range(0.0, 0.5, 0.01) var close_seconds: float = 0.18
@export_group("Typing sound")
# Like the mascot's voice: starts as each clause's first character appears and
# stops at its punctuation, spaces or line breaks, sounding at least
# min_typing_seconds; a clause starting within that time continues the sound.
@export var typing_event: String = "event:/UI/Text_Typing"
@export_range(0.0, 1.0, 0.05) var min_typing_seconds: float = 0.3

var playing: bool = false
var phase: Phase = Phase.CLOSED
var _characters: float = 0.0
var _sequence: Tween
var _typing_sound: FmodEvent
var _typing_started_msec: int = 0
var _typing_voiced: bool = false
# Bumped by every start or stop, so a postponed stop that is no longer
# current does nothing.
var _typing_version: int = 0

@onready var _page: Control = $Page
@onready var _paper: Sprite2D = $Page/Paper
@onready var _text: RichTextLabel = $Page/Text
@onready var _close: Button = $Page/Close
@onready var _animation: AnimationPlayer = $Unroll


func _ready() -> void:
	_text.text = first_section + "\n\n" + second_section + "\n\n" + third_section
	var paper_material: ShaderMaterial = _paper.material as ShaderMaterial
	paper_material.set_shader_parameter("white_paper", white_paper)
	_text.add_theme_color_override("default_color", Color.BLACK if white_paper else Color.WHITE)
	if white_paper:
		var button_ink: ShaderMaterial = _close.material.duplicate() as ShaderMaterial
		button_ink.set_shader_parameter("ink", Color.BLACK)
		_close.material = button_ink
		var brush: TextureRect = $Page/Close/Brush
		var brush_ink: ShaderMaterial = brush.material.duplicate() as ShaderMaterial
		brush_ink.set_shader_parameter("ink", Color(0.72, 0.72, 0.72))
		brush.material = brush_ink
	_close.pressed.connect(close)
	_animation.animation_finished.connect(_on_unrolled)
	resized.connect(_fit_page)
	reset()
	_fit_page()


func play() -> void:
	if playing:
		return
	playing = true
	phase = Phase.UNROLLING
	_characters = 0.0
	_text.visible_characters = 0
	_close.hide()
	_close.disabled = true
	_page.modulate.a = 1.0
	show()
	_fit_page()
	set_process(true)
	set_process_input(true)
	_animation.speed_scale = 0.65 / unroll_seconds
	_animation.play(&"unroll")
	_animation.advance(0.0)


func _process(delta: float) -> void:
	if phase != Phase.TYPING:
		return
	_characters += delta / Engine.time_scale * characters_per_second
	var shown: int = _text.visible_characters
	_text.visible_characters = mini(int(_characters), _text.get_total_character_count())
	var parsed: String = _text.get_parsed_text()
	for index: int in range(shown, mini(_text.visible_characters, parsed.length())):
		_set_typing_voiced(not (parsed[index] in Dialogue.SILENT_CHARACTERS))
	if _text.visible_characters >= _text.get_total_character_count():
		reveal_all()


func _on_unrolled(_animation_name: StringName) -> void:
	if phase == Phase.UNROLLING:
		phase = Phase.TYPING


func reveal_all() -> void:
	if phase not in [Phase.UNROLLING, Phase.TYPING]:
		return
	_animation.seek(0.65, true)
	_animation.pause()
	_stop_typing_sound()
	_text.visible_characters = -1
	phase = Phase.READING
	_close.disabled = false
	_close.show()


func close() -> void:
	if phase != Phase.READING:
		return
	phase = Phase.CLOSING
	_close.disabled = true
	_close.release_focus()
	_sequence = create_tween().set_ignore_time_scale(true)
	_sequence.tween_property(_page, "modulate:a", 0.0, close_seconds)
	_sequence.tween_callback(_finish)


func reset() -> void:
	if _sequence != null:
		_sequence.kill()
	_stop_typing_sound()
	_animation.stop()
	playing = false
	phase = Phase.CLOSED
	_page.modulate.a = 1.0
	_close.hide()
	_close.disabled = true
	hide()
	set_process(false)
	set_process_input(false)


func _input(event: InputEvent) -> void:
	if not playing:
		return
	# GUI input reaches the button only after the whole note is readable.
	if phase == Phase.READING and event is InputEventMouse:
		if _close.get_global_rect().has_point((event as InputEventMouse).position):
			return
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			reveal_all()
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER]:
			if phase == Phase.READING:
				close()
			else:
				reveal_all()
	get_viewport().set_input_as_handled()


func _finish() -> void:
	reset()
	finished.emit()


func _set_typing_voiced(voiced: bool) -> void:
	if voiced == _typing_voiced:
		return
	_typing_voiced = voiced
	_typing_version += 1
	if voiced:
		# Text_Typing is a one-shot; a long run may have outlasted it.
		if (
			_typing_sound != null
			and _typing_sound.get_playback_state() == FmodServer.FMOD_STUDIO_PLAYBACK_STOPPED
		):
			_stop_typing_sound()
			_typing_voiced = true
		if _typing_sound == null and not typing_event.is_empty():
			_typing_sound = GameAudio.start_loop(typing_event)
			_typing_started_msec = Time.get_ticks_msec()
		return
	var remaining: float = (
		min_typing_seconds - float(Time.get_ticks_msec() - _typing_started_msec) / 1000.0
	)
	if remaining <= 0.0:
		_stop_typing_sound()
	else:
		get_tree().create_timer(remaining, true, false, true).timeout.connect(
			_finish_typing_sound.bind(_typing_version)
		)


func _finish_typing_sound(version: int) -> void:
	if version == _typing_version:
		_stop_typing_sound()


func _stop_typing_sound() -> void:
	_typing_voiced = false
	_typing_version += 1
	GameAudio.stop_loop(_typing_sound)
	_typing_sound = null


func _exit_tree() -> void:
	_stop_typing_sound()


func _fit_page() -> void:
	var factor: float = minf(size.x / 1280.0, size.y / 800.0) * paper_scale
	_page.scale = Vector2.ONE * factor
	_page.position = (size - _page.size * factor) * 0.5
