extends Control

signal replay_requested
signal close_requested
signal menu_requested
signal finished

@export_range(10.0, 120.0, 1.0) var scroll_speed: float = 42.0
@export_range(0.0, 5.0, 0.1) var opening_hold_seconds: float = 1.0

var playing: bool = false

var _hold_remaining: float = 0.0
var _scrolled: float = 0.0
var _completed: bool = false

@onready var _roll: VBoxContainer = $Roll
@onready var _thanks: VBoxContainer = $Roll/Thanks
@onready var _actions: HBoxContainer = $Actions
@onready var _skip: Button = $Skip
@onready var _replay: Button = $Actions/Replay
@onready var _mascot: AnimatedSprite2D = $Roll/Thanks/MascotHolder/Center/Sprite
@onready var _previous_groups: Array[Control] = [$Roll/Cast, $Roll/Project, $Roll/Team]


func _ready() -> void:
	resized.connect(_layout_content)
	visibility_changed.connect(_on_visibility_changed)
	_skip.pressed.connect(finish_credits)
	_replay.pressed.connect(replay_requested.emit)
	$Actions/Close.pressed.connect(close_requested.emit)
	$Actions/Menu.pressed.connect(menu_requested.emit)
	reset()
	_layout_content.call_deferred()


func play() -> void:
	if visible and (playing or _completed):
		return
	_completed = false
	_scrolled = 0.0
	_hold_remaining = opening_hold_seconds
	_set_previous_groups_opacity(1.0)
	_actions.hide()
	_skip.show()
	_layout_content()
	show()
	_mascot.play(&"idle")
	playing = true
	set_process(true)
	_skip.grab_focus()


func reset() -> void:
	playing = false
	_completed = false
	_scrolled = 0.0
	_hold_remaining = 0.0
	set_process(false)
	_actions.hide()
	_skip.hide()
	_mascot.stop()
	_set_previous_groups_opacity(1.0)
	hide()
	_layout_content()


func finish_credits() -> void:
	if not playing or not is_visible_in_tree():
		return
	playing = false
	_completed = true
	set_process(false)
	_roll.position.y = _ending_position()
	_set_previous_groups_opacity(0.0)
	_skip.hide()
	_actions.show()
	_replay.grab_focus()
	finished.emit()


func _process(delta: float) -> void:
	if not playing or not is_visible_in_tree():
		return
	var movement_seconds: float = maxf(0.0, delta - _hold_remaining)
	_hold_remaining = maxf(0.0, _hold_remaining - delta)
	_scrolled += movement_seconds * scroll_speed
	_roll.position.y = size.y + 24.0 - _scrolled
	var remaining: float = _roll.position.y - _ending_position()
	_set_previous_groups_opacity(clampf(remaining / 72.0, 0.0, 1.0))
	if remaining <= 0.0:
		finish_credits()


func _layout_content() -> void:
	_roll.size.x = minf(860.0, maxf(0.0, size.x - 64.0))
	_roll.size.y = _roll.get_combined_minimum_size().y
	_roll.position.x = (size.x - _roll.size.x) * 0.5
	_roll.position.y = _ending_position() if _completed else size.y + 24.0 - _scrolled


func _ending_position() -> float:
	return (
		size.y * 0.46
		- (_roll.get_combined_minimum_size().y - _thanks.get_combined_minimum_size().y * 0.5)
	)


func _set_previous_groups_opacity(opacity: float) -> void:
	for group: Control in _previous_groups:
		group.modulate.a = opacity


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		playing = false
		_mascot.stop()
		set_process(false)
