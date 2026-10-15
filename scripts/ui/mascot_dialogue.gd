extends Control

signal line_started(index: int, text: String)
signal line_finished(index: int)
signal dialogue_finished

const Presenter = preload("res://scripts/ui/mascot_presenter.gd")
const GlyphPop = preload("res://scripts/ui/dialogue_glyph_pop.gd")

enum Phase { HIDDEN, ENTERING, OPENING, TYPING, HOLDING, FINISHED, IDLE }

@export var lines: PackedStringArray = PackedStringArray()
@export var autoplay: bool = true
@export_range(0, 2, 1) var form_index: int = 0
@export_group("Timing")
@export_range(1.0, 40.0, 1.0) var characters_per_second: float = 15.0
@export_range(0.0, 1.0, 0.01) var punctuation_pause: float = 0.22
@export_range(0.05, 1.0, 0.01) var bubble_open_seconds: float = 0.24
@export_range(0.0, 8.0, 0.1) var line_hold_seconds: float = 2.2

var phase: Phase = Phase.HIDDEN
var line_index: int = -1

var _phase_elapsed: float = 0.0
var _next_character_at: float = 0.0
var _glyph_pop: GlyphPop = GlyphPop.new()
var _playback_version: int = 0

@onready var presenter: Presenter = $MascotPresenter
@onready var bubble: Control = $SpeechBubble
@onready var text_label: RichTextLabel = $SpeechBubble/Text


func _ready() -> void:
	presenter.entrance_finished.connect(_on_entrance_finished)
	bubble.hide()
	if autoplay and not lines.is_empty():
		play(lines)
	else:
		hide()
		presenter.paused = true


func _process(delta: float) -> void:
	_phase_elapsed += delta
	_glyph_pop.clock += delta
	match phase:
		Phase.OPENING:
			var progress: float = clampf(_phase_elapsed / bubble_open_seconds, 0.0, 1.0)
			bubble.scale = Vector2.ONE * lerpf(0.88, 1.0, 1.0 - pow(1.0 - progress, 3.0))
			bubble.modulate.a = progress
			if progress >= 1.0:
				_start_line(0)
		Phase.TYPING:
			_reveal_characters()
		Phase.HOLDING:
			if _phase_elapsed >= line_hold_seconds:
				advance()


func play(dialogue_lines: PackedStringArray, replay_entrance: bool = true) -> void:
	assert(not dialogue_lines.is_empty(), "A dialogue needs at least one line.")
	var keep_presenter: bool = not replay_entrance and visible
	_playback_version += 1
	lines = dialogue_lines.duplicate()
	line_index = -1
	_phase_elapsed = 0.0
	_glyph_pop.clock = 0.0
	_glyph_pop.revealed_at.clear()
	text_label.clear()
	text_label.visible_characters = 0
	bubble.hide()
	bubble.modulate.a = 0.0
	phase = Phase.ENTERING
	show()
	if keep_presenter:
		presenter.set_speaking(false)
		presenter.paused = false
		if presenter.elapsed >= presenter.entrance_duration():
			_open_bubble()
	else:
		presenter.select_form(form_index)


func advance() -> void:
	if phase == Phase.TYPING:
		# A single advance reveals this line; it never also skips the reading pause.
		while _glyph_pop.revealed_at.size() < lines[line_index].length():
			_glyph_pop.revealed_at.append(_glyph_pop.clock - _glyph_pop.pop_seconds)
		text_label.visible_characters = lines[line_index].length()
		_finish_line()
	elif phase == Phase.HOLDING:
		if line_index + 1 < lines.size():
			_start_line(line_index + 1)
		else:
			phase = Phase.FINISHED
			dialogue_finished.emit()


func stop() -> void:
	_playback_version += 1
	phase = Phase.HIDDEN
	presenter.set_speaking(false)
	presenter.paused = true
	bubble.hide()
	hide()


func dismiss_bubble() -> void:
	_playback_version += 1
	phase = Phase.IDLE
	_phase_elapsed = 0.0
	presenter.set_speaking(false)
	presenter.seek(maxf(presenter.elapsed, presenter.entrance_duration()))
	presenter.paused = false
	bubble.hide()
	show()


func _on_entrance_finished() -> void:
	if phase != Phase.ENTERING:
		return
	_open_bubble()


func _open_bubble() -> void:
	phase = Phase.OPENING
	_phase_elapsed = 0.0
	bubble.pivot_offset = bubble.size * Vector2(0.82, 0.85)
	bubble.scale = Vector2.ONE * 0.88
	bubble.modulate.a = 0.0
	bubble.show()


func _start_line(index: int) -> void:
	line_index = index
	phase = Phase.TYPING
	_phase_elapsed = 0.0
	_next_character_at = 0.0
	_glyph_pop.clock = 0.0
	_glyph_pop.revealed_at.clear()
	text_label.clear()
	# Add raw text under the effect so dialogue punctuation cannot become BBCode.
	text_label.push_customfx(_glyph_pop, {})
	text_label.add_text(lines[index])
	text_label.pop()
	text_label.visible_characters = 0
	presenter.set_speaking(true)
	var playback_version: int = _playback_version
	line_started.emit(index, lines[index])
	if playback_version == _playback_version and phase == Phase.TYPING and line_index == index:
		_reveal_characters()


func _reveal_characters() -> void:
	var line: String = lines[line_index]
	while _glyph_pop.clock >= _next_character_at and text_label.visible_characters < line.length():
		var index: int = text_label.visible_characters
		_glyph_pop.revealed_at.append(_next_character_at)
		text_label.visible_characters += 1
		_next_character_at += 1.0 / characters_per_second
		if line[index] in "，。！？；：、…—":
			_next_character_at += punctuation_pause
	if text_label.visible_characters == line.length():
		_finish_line()


func _finish_line() -> void:
	if phase != Phase.TYPING:
		return
	presenter.set_speaking(false)
	phase = Phase.HOLDING
	_phase_elapsed = 0.0
	line_finished.emit(line_index)
