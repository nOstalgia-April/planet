extends Node

signal phase_changed(phase: Phase)
signal completed

const Play = preload("res://features/场景预览/游玩预览.gd")
const Dialogue = preload("res://scripts/ui/mascot_dialogue.gd")
const Spotlight = preload("res://features/tutorial_intro/tool_spotlight.gd")
const PipeCursor = preload("res://scripts/pipe_cursor.gd")

enum Phase {
	IDLE,
	OVERVIEW,
	ZOOMING,
	EMERGING,
	WAIT_LANDING,
	SLOWING,
	INTRO,
	DOCK,
	WAIT_TOOL,
	VACUUM,
	WAIT_CAPTURE,
	CAPTURE_FEEDBACK,
	REACTION_SLOWING,
	REACTION,
	REWARD_WAIT,
	CLOSING,
	RESUMING,
	DONE
}

@export var game: Play
@export_group("Timing")
@export var overview_seconds: float = 1.0
@export var zoom_seconds: float = 0.9
@export var emergence_seconds: float = 0.85
@export var slow_seconds: float = 0.65
@export var resume_seconds: float = 0.4
@export var dock_seconds: float = 0.65
@export var reward_pause_seconds: float = 1.8
@export_group("Dialogue")
@export var intro_lines: PackedStringArray
@export var vacuum_lines: PackedStringArray
@export var reaction_lines: PackedStringArray
@export var closing_lines: PackedStringArray

var phase: Phase = Phase.IDLE
var first_capture_seen: bool = false
var _elapsed: float = 0.0
var _previous_time_scale: float = 1.0
var _owns_time_scale: bool = false
var _tool_press_started: bool = false
var _tool_activation_allowed: bool = false
var _dock_process_mode: ProcessMode
var _feedback_effect: CollectionEffect
var _reward_finished: bool = false
var _transport_settled: bool = false
var _compact_finished: bool = false
var _opening_airborne: Array[PrototypeSlime] = []

@onready var dialogue: Dialogue = $TutorialLayer/MascotDialogue
@onready var compact_dialogue: Dialogue = $TutorialLayer/CompactDialogue
@onready var spotlight: Spotlight = $TutorialLayer/ToolSpotlight
@onready var _layer: CanvasLayer = $TutorialLayer
@onready var _pipe: PipeCursor = game.get_node("%Pipe") as PipeCursor


func _ready() -> void:
	assert(game != null, "Tutorial needs its gameplay scene.")
	assert(not intro_lines.is_empty() and not closing_lines.is_empty())
	dialogue.dialogue_finished.connect(_on_dialogue_finished)
	compact_dialogue.dialogue_finished.connect(_on_compact_finished)
	_pipe.transport_finished.connect(_on_transport_settled)
	_pipe.transport_cancelled.connect(_on_transport_settled)
	game.vacuum_capture_completed.connect(_on_capture_completed)
	game.get_node("HUD/Interface/ToolDock/Pipe/Button").pressed.connect(_on_tool_chosen)
	get_viewport().size_changed.connect(_layout_dialogue)


func begin() -> void:
	first_capture_seen = false
	_reward_finished = false
	_transport_settled = false
	_compact_finished = false
	_tool_press_started = false
	_tool_activation_allowed = false
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_dock_process_mode = game._layout._tool_dock.process_mode
	game._layout._tool_dock.process_mode = Node.PROCESS_MODE_ALWAYS
	game._layout.dock_intro_progress = 0.0
	game._layout.set_view_switch_enabled(false)
	game._view.presentation_locked = false
	game._view.zoom_steps(-1.0, false)
	_set_gameplay_enabled(false)
	game._pipe.hide()
	dialogue.stop()
	compact_dialogue.stop()
	spotlight.hide()
	for nest: NestView in game._nest_views:
		nest.set_emergence_progress(0.0)
	_layout_dialogue()
	_set_phase(Phase.OVERVIEW)


func _process(delta: float) -> void:
	if phase in [Phase.VACUUM, Phase.WAIT_CAPTURE] and get_tree().paused:
		return
	var unscaled_delta: float = delta / Engine.time_scale if _owns_time_scale else delta
	_elapsed += unscaled_delta
	match phase:
		Phase.OVERVIEW:
			if _elapsed >= overview_seconds:
				game._view.presentation_locked = true
				game._view.zoom_discovery(1.0, zoom_seconds)
				_set_phase(Phase.ZOOMING)
		Phase.ZOOMING:
			if not game._view.is_transitioning():
				for nest: NestView in game._nest_views:
					nest.begin_emergence()
				_set_phase(Phase.EMERGING)
		Phase.EMERGING:
			var progress: float = clampf(_elapsed / maxf(emergence_seconds, 0.001), 0.0, 1.0)
			for nest: NestView in game._nest_views:
				nest.set_emergence_progress(progress)
			if progress >= 1.0:
				_launch_opening_slimes()
		Phase.WAIT_LANDING:
			if _opening_airborne.is_empty():
				_previous_time_scale = Engine.time_scale
				_owns_time_scale = true
				_set_phase(Phase.SLOWING)
		Phase.SLOWING, Phase.REACTION_SLOWING:
			var progress: float = clampf(_elapsed / maxf(slow_seconds, 0.001), 0.0, 1.0)
			Engine.time_scale = (
				_previous_time_scale * lerpf(1.0, 0.08, smoothstep(0.0, 1.0, progress))
			)
			if progress >= 1.0:
				_restore_time_scale()
				game._layout.set_presentation_paused(true)
				if phase == Phase.SLOWING:
					_set_phase(Phase.INTRO)
					dialogue.play(intro_lines)
				else:
					_set_phase(Phase.REACTION)
					dialogue.play(reaction_lines)
		Phase.DOCK:
			var progress: float = clampf(_elapsed / dock_seconds, 0.0, 1.0)
			game._layout.dock_intro_progress = Tween.interpolate_value(
				0.0, 1.0, progress, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT
			)
			if progress >= 1.0:
				game._layout.dock_intro_progress = 1.0
				spotlight.show()
				_set_phase(Phase.WAIT_TOOL)
		Phase.CAPTURE_FEEDBACK:
			if _reward_finished and _transport_settled and _compact_finished:
				compact_dialogue.stop()
				_pipe.hide()
				_layer.process_mode = Node.PROCESS_MODE_ALWAYS
				_previous_time_scale = Engine.time_scale
				_owns_time_scale = true
				_set_phase(Phase.REACTION_SLOWING)
		Phase.REWARD_WAIT:
			if _elapsed >= reward_pause_seconds:
				_set_phase(Phase.CLOSING)
				dialogue.play(closing_lines, false)
		Phase.RESUMING:
			var progress: float = clampf(_elapsed / maxf(resume_seconds, 0.001), 0.0, 1.0)
			Engine.time_scale = (
				_previous_time_scale * lerpf(0.08, 1.0, smoothstep(0.0, 1.0, progress))
			)
			if progress >= 1.0:
				_restore_time_scale()
				game._view.presentation_locked = false
				_set_gameplay_enabled(true)
				_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
				_set_phase(Phase.DONE)
				completed.emit()


func _input(event: InputEvent) -> void:
	if not _is_controlling_gameplay():
		return
	if phase == Phase.WAIT_TOOL:
		var button: Button = game._quick_pipe_button
		if event is InputEventMouseMotion:
			if (
				_tool_press_started
				or button.get_global_rect().has_point((event as InputEventMouseMotion).position)
			):
				return
		elif event is InputEventMouseButton:
			var mouse: InputEventMouseButton = event as InputEventMouseButton
			if mouse.button_index == MOUSE_BUTTON_LEFT:
				if mouse.pressed and button.get_global_rect().has_point(mouse.position):
					_tool_press_started = true
					_tool_activation_allowed = false
					return
				if not mouse.pressed and _tool_press_started:
					# GUI owns release/cancellation, including releases outside the real button.
					_tool_press_started = false
					_tool_activation_allowed = button.get_global_rect().has_point(mouse.position)
					return
	get_viewport().set_input_as_handled()


func _on_tool_chosen() -> void:
	if phase != Phase.WAIT_TOOL or not _tool_activation_allowed:
		return
	_tool_activation_allowed = false
	spotlight.hide()
	game._quick_pipe_button.release_focus()
	game._layout._tool_dock.process_mode = _dock_process_mode
	game._layout.set_presentation_paused(false)
	game._view.presentation_locked = false
	_set_gameplay_enabled(true)
	_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_set_phase(Phase.VACUUM)
	dialogue.stop()
	compact_dialogue.play(vacuum_lines)


func _launch_opening_slimes() -> void:
	assert(game.run.nests.size() == 2 and game._slimes.is_empty())
	# Advance both real production clocks together while ordinary gameplay stays locked.
	for nest: NestState in game.run.nests:
		game.run.schedule_next_spawn(nest.nest_id, 0.0)
	game.run.advance(0.0001)
	_opening_airborne.assign(game._slimes)
	assert(not _opening_airborne.is_empty(), "Opening production must create real slime actors.")
	for slime: PrototypeSlime in _opening_airborne:
		slime.launch_landed.connect(_on_opening_slime_landed)
	_set_phase(Phase.WAIT_LANDING)


func _on_opening_slime_landed(slime: PrototypeSlime) -> void:
	_opening_airborne.erase(slime)
	slime.launch_landed.disconnect(_on_opening_slime_landed)


func _clear_opening_wait() -> void:
	for slime: PrototypeSlime in _opening_airborne:
		if is_instance_valid(slime):
			slime.launch_landed.disconnect(_on_opening_slime_landed)
	_opening_airborne.clear()


func _on_capture_completed(_nest_id: int, _candy_gained: int, feedback: CollectionEffect) -> void:
	if first_capture_seen or phase not in [Phase.VACUUM, Phase.WAIT_CAPTURE]:
		return
	assert(feedback != null, "The first near-view capture must have its candy feedback.")
	first_capture_seen = true
	_feedback_effect = feedback
	_feedback_effect.finished.connect(_on_reward_finished, CONNECT_ONE_SHOT)
	# Stop new actions while the actual reward and vacuum transport finish naturally.
	# The world children keep animating; hiding the pipe here would cancel its cycle.
	_set_gameplay_enabled(false)
	game._vacuum_audio.stop_now()
	_pipe.active = false
	_pipe.queue_redraw()
	game._view.presentation_locked = true
	game._layout.set_view_switch_enabled(false)
	_set_phase(Phase.CAPTURE_FEEDBACK)


func _on_reward_finished() -> void:
	_feedback_effect = null
	_reward_finished = true


func _on_transport_settled() -> void:
	if phase == Phase.CAPTURE_FEEDBACK:
		_transport_settled = true


func _on_compact_finished() -> void:
	_compact_finished = true
	compact_dialogue.dismiss_bubble()
	if phase == Phase.VACUUM:
		_set_phase(Phase.WAIT_CAPTURE)


func _on_dialogue_finished() -> void:
	match phase:
		Phase.INTRO:
			dialogue.dismiss_bubble()
			_set_phase(Phase.DOCK)
		Phase.REACTION:
			dialogue.dismiss_bubble()
			_set_phase(Phase.REWARD_WAIT)
		Phase.CLOSING:
			dialogue.stop()
			_previous_time_scale = Engine.time_scale
			_owns_time_scale = true
			Engine.time_scale = _previous_time_scale * 0.08
			game._layout.set_presentation_paused(false)
			game.set_process(true)
			_set_phase(Phase.RESUMING)


func cancel() -> void:
	var controlled_gameplay: bool = _is_controlling_gameplay()
	_set_phase(Phase.IDLE)
	_clear_opening_wait()
	_clear_feedback_wait()
	_restore_time_scale()
	if controlled_gameplay:
		for nest: NestView in game._nest_views:
			nest.set_emergence_progress(1.0)
		game._layout.set_presentation_paused(false)
		game._view.presentation_locked = false
		game._view.clear_discovery_camera()
		_set_gameplay_enabled(true)
	game._layout._tool_dock.process_mode = _dock_process_mode
	game._layout.dock_intro_progress = 1.0
	dialogue.stop()
	compact_dialogue.stop()
	spotlight.hide()


func _exit_tree() -> void:
	_clear_opening_wait()
	_clear_feedback_wait()
	_restore_time_scale()
	if _is_controlling_gameplay():
		game._layout.set_presentation_paused(false)


func _clear_feedback_wait() -> void:
	if is_instance_valid(_feedback_effect):
		_feedback_effect.finished.disconnect(_on_reward_finished)
	_feedback_effect = null
	_reward_finished = false
	_transport_settled = false
	_compact_finished = false


func _is_controlling_gameplay() -> bool:
	return phase not in [Phase.IDLE, Phase.VACUUM, Phase.WAIT_CAPTURE, Phase.DONE]


func _restore_time_scale() -> void:
	if _owns_time_scale:
		Engine.time_scale = _previous_time_scale
		_owns_time_scale = false


func _set_gameplay_enabled(enabled: bool) -> void:
	game.set_process(enabled)
	game.set_process_input(enabled)
	game.set_process_unhandled_input(enabled)
	game.set_process_unhandled_key_input(enabled)


func _set_phase(value: Phase) -> void:
	phase = value
	_elapsed = 0.0
	phase_changed.emit(phase)


func _layout_dialogue() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var factor: float = minf(viewport_size.x / 1280.0, viewport_size.y / 800.0)
	for panel: Dialogue in [dialogue, compact_dialogue]:
		panel.scale = Vector2.ONE * factor
		panel.size = viewport_size / factor
