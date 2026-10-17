extends Control

signal menu_requested
signal finished

@export_range(10.0, 120.0, 1.0) var scroll_speed: float = 42.0
@export_range(0.0, 5.0, 0.1) var opening_hold_seconds: float = 0.0

var playing: bool = false

var _hold_remaining: float = 0.0
var _scrolled: float = 0.0
var _completed: bool = false
var _returning_to_menu: bool = false
var _dragging: bool = false

@onready var _roll: VBoxContainer = $Roll
@onready var _return_button: Button = $ReturnToMenu


func _ready() -> void:
	resized.connect(_layout_content)
	visibility_changed.connect(_on_visibility_changed)
	_return_button.pressed.connect(return_to_menu)
	reset()
	_layout_content.call_deferred()


func play() -> void:
	if visible and (playing or _completed or _returning_to_menu):
		return
	_completed = false
	_returning_to_menu = false
	_scrolled = 0.0
	_hold_remaining = opening_hold_seconds
	_dragging = false
	_return_button.hide()
	_layout_content()
	show()
	playing = true
	set_process(true)


func reset() -> void:
	playing = false
	_completed = false
	_returning_to_menu = false
	_scrolled = 0.0
	_hold_remaining = 0.0
	_dragging = false
	set_process(false)
	_return_button.hide()
	hide()
	_layout_content()


func finish_credits() -> void:
	if not playing or not is_visible_in_tree():
		return
	playing = false
	_completed = true
	_dragging = false
	set_process(false)
	_roll.position.y = _ending_position()
	_return_button.show()
	_return_button.grab_focus()
	finished.emit()


func return_to_menu() -> void:
	if not _completed or not is_visible_in_tree() or _returning_to_menu:
		return
	_returning_to_menu = true
	playing = false
	set_process(false)
	_return_button.hide()
	_return_button.release_focus()
	menu_requested.emit()


func _process(delta: float) -> void:
	if not playing or not is_visible_in_tree():
		return
	var movement_seconds: float = maxf(0.0, delta - _hold_remaining)
	_hold_remaining = maxf(0.0, _hold_remaining - delta)
	_advance_scroll(movement_seconds * scroll_speed)


func _gui_input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_dragging = (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if _dragging and motion.relative.y < 0.0:
			_hold_remaining = 0.0
			_advance_scroll(-motion.relative.y)
		accept_event()


func _advance_scroll(distance: float) -> void:
	_scrolled += distance
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
		_dragging = false
		set_process(false)
