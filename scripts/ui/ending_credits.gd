extends Control

signal menu_requested
signal finished

@export_range(10.0, 120.0, 1.0) var scroll_speed: float = 42.0
@export_range(0.0, 5.0, 0.1) var opening_hold_seconds: float = 1.0

var playing: bool = false

var _hold_remaining: float = 0.0
var _scrolled: float = 0.0
var _completed: bool = false
var _returning_to_menu: bool = false

@onready var _roll: VBoxContainer = $Roll
@onready var _skip: Button = $Skip


func _ready() -> void:
	resized.connect(_layout_content)
	visibility_changed.connect(_on_visibility_changed)
	_skip.pressed.connect(skip_credits)
	reset()
	_layout_content.call_deferred()


func play() -> void:
	if visible and (playing or _completed or _returning_to_menu):
		return
	_completed = false
	_returning_to_menu = false
	_scrolled = 0.0
	_hold_remaining = opening_hold_seconds
	_skip.show()
	_layout_content()
	show()
	playing = true
	set_process(true)
	_skip.grab_focus()


func reset() -> void:
	playing = false
	_completed = false
	_returning_to_menu = false
	_scrolled = 0.0
	_hold_remaining = 0.0
	set_process(false)
	_skip.hide()
	hide()
	_layout_content()


func finish_credits() -> void:
	if not playing or not is_visible_in_tree():
		return
	playing = false
	_completed = true
	set_process(false)
	_roll.position.y = _ending_position()
	finished.emit()
	skip_credits()


func skip_credits() -> void:
	if not is_visible_in_tree() or _returning_to_menu:
		return
	_returning_to_menu = true
	playing = false
	set_process(false)
	menu_requested.emit()


func _process(delta: float) -> void:
	if not playing or not is_visible_in_tree():
		return
	var movement_seconds: float = maxf(0.0, delta - _hold_remaining)
	_hold_remaining = maxf(0.0, _hold_remaining - delta)
	_scrolled += movement_seconds * scroll_speed
	_roll.position.y = size.y + 24.0 - _scrolled
	var remaining: float = _roll.position.y - _ending_position()
	if remaining <= 0.0:
		finish_credits()


func _layout_content() -> void:
	_roll.size.x = minf(860.0, maxf(0.0, size.x - 64.0))
	_roll.size.y = _roll.get_combined_minimum_size().y
	_roll.position.x = (size.x - _roll.size.x) * 0.5
	_roll.position.y = _ending_position() if _completed else size.y + 24.0 - _scrolled


func _ending_position() -> float:
	return -_roll.get_combined_minimum_size().y - 24.0


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		playing = false
		set_process(false)
