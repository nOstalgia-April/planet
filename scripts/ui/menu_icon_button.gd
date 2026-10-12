extends Button

@export var glyph: Texture2D
@export var glyph_size: float = 34.0
var highlighted: bool = false

@onready var _brush: TextureRect = $Brush


func _ready() -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	_brush.visible = highlighted or is_hovered() or has_focus()
	if glyph != null:
		var extent: Vector2 = glyph.get_size()
		extent *= glyph_size / maxf(extent.x, extent.y)
		draw_texture_rect(
			glyph,
			Rect2((size - extent) * 0.5 + Vector2.ONE, extent),
			false,
			Color(0.04, 0.05, 0.12, 0.65)
		)
		draw_texture_rect(glyph, Rect2((size - extent) * 0.5, extent), false)
