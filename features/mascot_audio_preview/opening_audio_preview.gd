extends "res://features/mascot_audio_preview/stage_audio_preview.gd"

enum Segment { INTRO, VACUUM, REACTION, REWARD_WAIT, CLOSING, DONE }

@export var intro_lines: PackedStringArray
@export var vacuum_lines: PackedStringArray
@export var reaction_lines: PackedStringArray
@export var closing_lines: PackedStringArray
@export var reward_pause_seconds: float = 1.8

var segment: Segment = Segment.INTRO
var _wait_elapsed: float = 0.0

@onready var compact_dialogue: Dialogue = $DialogueLayer/CompactDialogue


func _ready() -> void:
	compact_dialogue.dialogue_finished.connect(_on_compact_finished)
	bind_dialogue_audio(compact_dialogue)
	super._ready()


func _process(delta: float) -> void:
	if segment != Segment.REWARD_WAIT:
		return
	_wait_elapsed += delta
	if _wait_elapsed >= reward_pause_seconds:
		segment = Segment.CLOSING
		dialogue.play(closing_lines, false)


func replay() -> void:
	stop_dialogue_audio()
	segment = Segment.INTRO
	_wait_elapsed = 0.0
	compact_dialogue.stop()
	dialogue.play(intro_lines)


func advance() -> void:
	if segment == Segment.VACUUM:
		compact_dialogue.advance()
	else:
		dialogue.advance()


func _on_dialogue_finished() -> void:
	match segment:
		Segment.INTRO:
			dialogue.stop()
			segment = Segment.VACUUM
			compact_dialogue.play(vacuum_lines)
		Segment.REACTION:
			dialogue.dismiss_bubble()
			segment = Segment.REWARD_WAIT
			_wait_elapsed = 0.0
		Segment.CLOSING:
			segment = Segment.DONE
			dialogue.dismiss_bubble()


func _on_compact_finished() -> void:
	compact_dialogue.stop()
	segment = Segment.REACTION
	dialogue.play(reaction_lines)


func _layout_dialogue() -> void:
	super._layout_dialogue()
	compact_dialogue.scale = dialogue.scale
	compact_dialogue.size = dialogue.size
