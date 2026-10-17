extends Node

signal story_started(kind: Kind)
signal story_finished(kind: Kind)
signal rescue_finished

const Play = preload("res://features/场景预览/游玩预览.gd")
const Dialogue = preload("res://scripts/ui/mascot_dialogue.gd")
const Restoration = preload("res://features/tutorial_intro/story_restoration.gd")

enum Kind { NONE, OPENING, CULTIVATION, AUTOMATION, COLOR_ONE, COLOR_TWO, COLOR_THREE, RESCUE }
enum Phase { IDLE, OVERVIEW, ZOOMING, EMERGING, LANDING, SLOWING, TALKING, WAIT_COLOR, RESUMING }

@export var game: Play
@export var restoration: Restoration
@export_group("Timing")
@export_range(0.1, 1.0, 0.05) var background_speed: float = 0.5
@export var slow_seconds: float = 0.65
@export var resume_seconds: float = 0.4
@export var overview_seconds: float = 1.0
@export var zoom_seconds: float = 0.9
@export var emergence_seconds: float = 0.85
@export_group("Dialogue")
@export var opening_lines: PackedStringArray
@export var cultivation_lines: PackedStringArray
@export var automation_lines: PackedStringArray
@export var first_color_lines: PackedStringArray
@export var second_color_lines: PackedStringArray
@export var third_color_lines: PackedStringArray
@export var rescue_lines: PackedStringArray
@export_group("Voice")
@export var talk_events: PackedStringArray = PackedStringArray(
	[
		"event:/Gibberish/Gibberish_Stage1",
		"event:/Gibberish/Gibberish_Stage2",
		"event:/Gibberish/Gibberish_Stage3"
	]
)
@export_range(0.0, 1.0, 0.05) var min_voice_seconds: float = 0.3

var kind: Kind = Kind.NONE
var phase: Phase = Phase.IDLE
var current_form: int = 0
var seen: Array[Kind] = []
var active_dialogue: Dialogue

var _elapsed: float = 0.0
var _saved_time_scale: float = 1.0
var _owns_controls: bool = false
var _pending_teaching: Array[Kind] = []
var _airborne: Array[PrototypeSlime] = []
var _form_tween: Tween
var _resume_from_speed: float = 1.0
var _voice: FmodEvent
var _voice_requested: bool = false
var _voice_remaining: float = 0.0

@onready var narrative: Dialogue = $StoryLayer/Narrative
@onready var teaching: Dialogue = $StoryLayer/Teaching
@onready var color_dialogue: Dialogue = $StoryLayer/ColorDialogue


func _ready() -> void:
	assert(game != null and restoration != null)
	assert(talk_events.size() == 3)
	for panel: Dialogue in [narrative, teaching, color_dialogue]:
		panel.dialogue_finished.connect(_on_dialogue_finished)
		panel.line_started.connect(_on_line_started)
		panel.voice_started.connect(_on_voice_started)
		panel.voice_stopped.connect(_on_voice_stopped)
	get_viewport().size_changed.connect(_layout_dialogues)
	_layout_dialogues()


func begin() -> void:
	seen.clear()
	_pending_teaching.clear()
	current_form = 0
	if not game.run.economy_changed.is_connected(_on_economy_changed):
		game.run.economy_changed.connect(_on_economy_changed)
		restoration.story_started.connect(_on_color_started)
		restoration.presentation_finished.connect(_on_color_finished)
	_acquire_controls()
	game._view.show_restoration_overview()
	kind = Kind.OPENING
	active_dialogue = narrative
	game._layout.dock_intro_progress = 0.0
	for nest: NestView in game._nest_views:
		nest.set_emergence_progress(0.0)
	_set_phase(Phase.OVERVIEW)


func _process(delta: float) -> void:
	var real_delta: float = delta / Engine.time_scale
	_voice_remaining = maxf(0.0, _voice_remaining - real_delta)
	if not _voice_requested and _voice_remaining <= 0.0:
		_stop_voice()
	_elapsed += real_delta
	if _owns_controls:
		GameAudio.set_music_ducked(true)
		game._planet_audio.zoom_sounds_muted = true
		GameAudio.set_near_view_gain(game._view.near_blend)
	match phase:
		Phase.IDLE:
			_try_teaching()
		Phase.OVERVIEW:
			if _elapsed >= overview_seconds:
				game._view.zoom_discovery(1.0, zoom_seconds)
				_set_phase(Phase.ZOOMING)
		Phase.ZOOMING:
			if not game._view.is_transitioning():
				for nest: NestView in game._nest_views:
					nest.begin_emergence()
				_set_phase(Phase.EMERGING)
		Phase.EMERGING:
			var progress: float = minf(_elapsed / emergence_seconds, 1.0)
			for nest: NestView in game._nest_views:
				nest.set_emergence_progress(progress)
			if progress >= 1.0:
				_launch_opening_slimes()
		Phase.LANDING:
			if _airborne.is_empty():
				_set_phase(Phase.SLOWING)
		Phase.SLOWING:
			var progress: float = minf(_elapsed / maxf(slow_seconds, 0.001), 1.0)
			Engine.time_scale = (
				_saved_time_scale * lerpf(1.0, background_speed, smoothstep(0.0, 1.0, progress))
			)
			if progress >= 1.0:
				_play_lines()
		Phase.RESUMING:
			var progress: float = minf(_elapsed / maxf(resume_seconds, 0.001), 1.0)
			Engine.time_scale = lerpf(
				_resume_from_speed, _saved_time_scale, smoothstep(0.0, 1.0, progress)
			)
			if progress >= 1.0:
				_finish_story()


func _input(event: InputEvent) -> void:
	if not _owns_controls:
		return
	if event is InputEventMouse:
		if game._layout.game_menu.contains_pointer((event as InputEventMouse).position):
			return
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			return
		if key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER]:
			if phase == Phase.TALKING:
				active_dialogue.advance()
	get_viewport().set_input_as_handled()


func _acquire_controls() -> void:
	if _owns_controls:
		return
	_owns_controls = true
	_saved_time_scale = Engine.time_scale
	game._layout.close_panels()
	game._clear_nest_selection()
	game._cancel_view_drag()
	game._capture_at(0.0, game._tool_pointer, false)
	game._vacuum_audio.stop_now()
	game._pipe.hide()
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.set_process_unhandled_key_input(false)
	game._layout.set_process(false)
	game._layout._tool_dock.hide()
	game._layout._view_shortcut.hide()
	game._view.presentation_locked = true


func _release_controls() -> void:
	if not _owns_controls:
		return
	Engine.time_scale = _saved_time_scale
	_owns_controls = false
	game._view.presentation_locked = false
	game._layout.dock_intro_progress = 1.0
	game._layout._tool_dock.show()
	game._layout.set_process(true)
	game._layout.set_process_unhandled_key_input(true)
	game.set_process(true)
	game.set_process_input(true)
	game.set_process_unhandled_input(true)
	game.set_process_unhandled_key_input(true)
	game._view_blocks_tool_until_release = true
	game._select_tool(game._active_tool)
	GameAudio.set_music_ducked(false)
	game._planet_audio.zoom_sounds_muted = false


func _launch_opening_slimes() -> void:
	for nest: NestState in game.run.nests:
		game.run.schedule_next_spawn(nest.nest_id, 0.0)
	game.run.advance(0.0001)
	_airborne.assign(game._slimes)
	for slime: PrototypeSlime in _airborne:
		slime.launch_landed.connect(_on_landed)
	_set_phase(Phase.LANDING)


func _on_landed(slime: PrototypeSlime) -> void:
	_airborne.erase(slime)
	slime.launch_landed.disconnect(_on_landed)


func _on_economy_changed() -> void:
	if game.run.get_technology_level("cultivation") > 0:
		_queue_teaching(Kind.CULTIVATION)
	if game.run.get_technology_level("automation") > 0:
		_queue_teaching(Kind.AUTOMATION)


func _queue_teaching(value: Kind) -> void:
	if value not in seen and value not in _pending_teaching and kind != value:
		_pending_teaching.append(value)


func _try_teaching() -> void:
	if _pending_teaching.is_empty() or game._layout.is_technology_open():
		return
	if game._view.presentation_locked or game.run.is_complete or game._view.is_transitioning():
		return
	kind = _pending_teaching.pop_front()
	active_dialogue = teaching
	_acquire_controls()
	_set_phase(Phase.SLOWING)


func _on_color_started(stage: int) -> void:
	assert(stage >= 1 and stage <= 3)
	kind = (Kind.COLOR_ONE + stage - 1) as Kind
	active_dialogue = color_dialogue
	_acquire_controls()
	Engine.time_scale = _saved_time_scale * background_speed
	_play_lines()


func _on_color_finished() -> void:
	if kind in [Kind.COLOR_ONE, Kind.COLOR_TWO, Kind.COLOR_THREE]:
		_begin_resuming()


func play_rescue() -> void:
	kind = Kind.RESCUE
	current_form = 2
	active_dialogue = narrative
	_acquire_controls()
	_set_phase(Phase.SLOWING)


func _play_lines() -> void:
	active_dialogue.form_index = current_form
	active_dialogue.presenter.modulate.a = 1.0
	active_dialogue.play(_lines_for(kind))
	_set_phase(Phase.TALKING)
	seen.append(kind)
	story_started.emit(kind)


func _lines_for(value: Kind) -> PackedStringArray:
	match value:
		Kind.OPENING:
			return opening_lines
		Kind.CULTIVATION:
			return cultivation_lines
		Kind.AUTOMATION:
			return automation_lines
		Kind.COLOR_ONE:
			return first_color_lines
		Kind.COLOR_TWO:
			return second_color_lines
		Kind.COLOR_THREE:
			return third_color_lines
		Kind.RESCUE:
			return rescue_lines
	assert(false, "No dialogue for this story beat.")
	return PackedStringArray()


func _on_line_started(index: int, _text: String) -> void:
	if index != 0:
		return
	if kind == Kind.COLOR_ONE:
		_transform_to(1)
	elif kind == Kind.COLOR_THREE:
		_transform_to(2)


func _transform_to(form: int) -> void:
	_form_tween = create_tween().set_ignore_time_scale(true)
	_form_tween.tween_property(active_dialogue.presenter, "modulate:a", 0.0, 0.18)
	_form_tween.tween_callback(_reveal_form.bind(form))
	_form_tween.tween_property(active_dialogue.presenter, "modulate:a", 1.0, 0.22)


func _reveal_form(form: int) -> void:
	var was_voicing: bool = _voice_requested
	_stop_voice()
	current_form = form
	active_dialogue.form_index = form
	active_dialogue.presenter.select_form(form)
	active_dialogue.presenter.seek(active_dialogue.presenter.entrance_duration())
	active_dialogue.presenter.set_speaking(active_dialogue.phase == Dialogue.Phase.TYPING)
	if was_voicing:
		_on_voice_started(active_dialogue.line_index)


func _on_voice_started(_index: int) -> void:
	_voice_requested = true
	if _voice == null:
		_voice = GameAudio.start_loop(talk_events[current_form])
		_voice_remaining = min_voice_seconds


func _on_voice_stopped() -> void:
	_voice_requested = false
	if _voice_remaining <= 0.0:
		_stop_voice()


func _stop_voice() -> void:
	_voice_requested = false
	_voice_remaining = 0.0
	if _voice != null:
		GameAudio.stop_loop(_voice)
		_voice = null


func _on_dialogue_finished() -> void:
	active_dialogue.dismiss_bubble()
	if kind in [Kind.COLOR_ONE, Kind.COLOR_TWO, Kind.COLOR_THREE]:
		restoration.confirm_dialogue()
		_set_phase(Phase.WAIT_COLOR)
	else:
		_begin_resuming()


func _begin_resuming() -> void:
	if _form_tween != null:
		_form_tween.kill()
	active_dialogue.stop()
	_stop_voice()
	_resume_from_speed = Engine.time_scale
	game._view.presentation_locked = true
	_set_phase(Phase.RESUMING)


func _finish_story() -> void:
	var finished_kind: Kind = kind
	_release_controls()
	kind = Kind.NONE
	_set_phase(Phase.IDLE)
	story_finished.emit(finished_kind)
	if finished_kind == Kind.RESCUE:
		rescue_finished.emit()


func cancel() -> void:
	if _form_tween != null:
		_form_tween.kill()
	for slime: PrototypeSlime in _airborne:
		if is_instance_valid(slime):
			slime.launch_landed.disconnect(_on_landed)
	_airborne.clear()
	_pending_teaching.clear()
	for panel: Dialogue in [narrative, teaching, color_dialogue]:
		panel.stop()
		panel.presenter.modulate.a = 1.0
	_stop_voice()
	_release_controls()
	kind = Kind.NONE
	_set_phase(Phase.IDLE)


func _exit_tree() -> void:
	_stop_voice()
	if _owns_controls:
		Engine.time_scale = _saved_time_scale
	GameAudio.set_music_ducked(false)


func _set_phase(value: Phase) -> void:
	phase = value
	_elapsed = 0.0


func _layout_dialogues() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var factor: float = minf(viewport_size.x / 1280.0, viewport_size.y / 800.0)
	for panel: Dialogue in [narrative, teaching, color_dialogue]:
		panel.scale = Vector2.ONE * factor
		panel.size = viewport_size / factor
