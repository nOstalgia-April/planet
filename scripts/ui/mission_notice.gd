extends Control

signal finished

@export var heading: String
@export_multiline var first_section: String
@export_multiline var second_section: String
@export_multiline var third_section: String
@export_group("Timing")
@export var transition_seconds: float = 0.5
@export var reveal_seconds: float = 1.2
@export var section_hold_seconds: float = 4.0
@export var final_hold_seconds: float = 3.0

var playing: bool = false
var _sequence: Tween

@onready var _black: ColorRect = $Black
@onready var _page: VBoxContainer = $Page
@onready var _sections: Array[Control] = [$Page/First, $Page/Second, $Page/Third]


func _ready() -> void:
	$Page/First/Heading.text = heading
	$Page/First/Body.text = first_section
	$Page/Second.text = second_section
	$Page/Third.text = third_section
	resized.connect(_fit_page)
	_page.minimum_size_changed.connect(_fit_page)
	reset()


func play() -> void:
	if playing:
		return
	playing = true
	show()
	_page.modulate.a = 1.0
	_fit_page()
	_black.modulate.a = 0.0
	for section: Control in _sections:
		section.modulate.a = 0.0
	_sequence = create_tween().set_ignore_time_scale(true)
	_sequence.tween_property(_black, "modulate:a", 1.0, transition_seconds)
	for index: int in range(_sections.size()):
		_sequence.tween_property(_sections[index], "modulate:a", 1.0, reveal_seconds)
		if index < _sections.size() - 1:
			_sequence.tween_interval(section_hold_seconds)
	_sequence.tween_interval(final_hold_seconds)
	_sequence.tween_property(_page, "modulate:a", 0.0, transition_seconds)
	_sequence.tween_callback(_finish)


func reset() -> void:
	if _sequence != null:
		_sequence.kill()
	playing = false
	_page.modulate.a = 1.0
	hide()
	set_process_input(false)


func _input(_event: InputEvent) -> void:
	if is_visible_in_tree():
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		set_process_input(is_visible_in_tree())


func _finish() -> void:
	playing = false
	finished.emit()


func _fit_page() -> void:
	var factor: float = minf(size.x / 1280.0, size.y / 800.0)
	_page.scale = Vector2.ONE * factor
	_page.size = Vector2(1000.0, _page.get_combined_minimum_size().y)
	_page.position = (size - _page.size * factor) * 0.5
