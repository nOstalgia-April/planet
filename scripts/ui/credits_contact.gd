extends Button

@export var email: String = ""

var _reveal: Tween

@onready var _clip: Control = $Reveal
@onready var _panel: PanelContainer = $Reveal/Contact
@onready var _address: Label = $Reveal/Contact/Address


func _ready() -> void:
	_address.text = email
	mouse_entered.connect(_set_expanded.bind(true))
	mouse_exited.connect(_leave)
	focus_entered.connect(_set_expanded.bind(true))
	focus_exited.connect(_set_expanded.bind(false))
	pressed.connect(_set_expanded.bind(true))
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(queue_redraw)


func _draw() -> void:
	var font: Font = get_theme_font("font")
	var font_size: int = get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline: float = (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	draw_line(Vector2(0, baseline + 3), Vector2(text_width, baseline + 3), Color.WHITE, 1.0, true)
	var envelope: Rect2 = Rect2(text_width + 6, 5, 16, 11)
	draw_rect(envelope, Color.WHITE, false, 1.3)
	var fold: Vector2 = envelope.position + Vector2(8, 6)
	draw_line(envelope.position, fold, Color.WHITE, 1.3, true)
	draw_line(envelope.position + Vector2(16, 0), fold, Color.WHITE, 1.3, true)


func _set_expanded(expanded: bool) -> void:
	if _reveal != null:
		_reveal.kill()
	if not expanded:
		_clip.hide()
		_clip.size.x = 0.0
		return
	_panel.size = _panel.get_combined_minimum_size()
	_clip.position = Vector2(size.x + 6.0, (size.y - _panel.size.y) * 0.5)
	_clip.size = Vector2(0, _panel.size.y)
	_clip.show()
	_reveal = create_tween()
	(
		_reveal
		. tween_property(_clip, "size:x", _panel.size.x, 0.18)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)


func _leave() -> void:
	release_focus()
	_set_expanded(false)


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_set_expanded(false)
