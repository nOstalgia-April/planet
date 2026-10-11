extends Button

enum State { PURCHASED, AVAILABLE, UNAFFORDABLE, LOCKED }

const GlyphScript = preload("res://scripts/ui/technology_glyph.gd")
const ICON_CENTER: Vector2 = Vector2(60.0, 48.0)
const PRICE_COLORS: Array[Color] = [
	Color("bda9b6"), Color("b9e6ae"), Color("d7a18f"), Color("b4a3b0")
]
const INK_COLORS: Array[Color] = [
	Color("bdaeb8"), Color("fff0f6"), Color("b5a4af"), Color("929292")
]
const PLATE_COLORS: Array[Color] = [
	Color("221b23"), Color("301b29"), Color("241b23"), Color("21182080")
]
const RIM_COLORS: Array[Color] = [
	Color("65545f"), Color("bd678e"), Color("51404c"), Color("43333f60")
]

var technology_id: String = ""
var level: int = 0
var state: State = State.LOCKED
var accent: Color = Color("f84798")
var selected: bool = false

@onready var glyph: GlyphScript = $Glyph
@onready var title_label: Label = $Title
@onready var level_label: Label = $Level
@onready var price_label: Label = $Price/Value
@onready var coin: TextureRect = $Price/Coin
@onready var _plate_material: ShaderMaterial = $InkPlate.material as ShaderMaterial


func _ready() -> void:
	mouse_entered.connect(_refresh_appearance)
	mouse_exited.connect(_refresh_appearance)
	focus_entered.connect(_refresh_appearance)
	focus_exited.connect(_refresh_appearance)
	glyph.use_supplied_art = true
	set_process(false)


func configure(id: String, title: String, symbol: int, color: Color) -> void:
	technology_id = id
	title_label.text = title
	glyph.symbol = symbol
	accent = color


func refresh(next_state: State, is_selected: bool, current_level: int) -> void:
	state = next_state
	selected = is_selected
	level = current_level
	glyph.locked = state == State.LOCKED
	glyph.ink = INK_COLORS[state]
	level_label.add_theme_color_override("font_color", INK_COLORS[state].darkened(0.18))
	level_label.visible = not glyph.locked
	$Price.visible = not glyph.locked
	glyph.queue_redraw()
	_refresh_appearance()


func show_price(max_level: int, cost: int) -> void:
	level_label.text = "%d/%d" % [level, max_level]
	price_label.text = "已满级" if state == State.PURCHASED else str(cost)
	price_label.add_theme_color_override("font_color", PRICE_COLORS[state])
	coin.visible = state != State.PURCHASED


func _refresh_appearance() -> void:
	var active: bool = is_hovered() or has_focus()
	var rim: Color = RIM_COLORS[state]
	var fill: Color = PLATE_COLORS[state]
	if active:
		rim = Color("efb0cd")
		fill = fill.lightened(0.045)
	_plate_material.set_shader_parameter("fill_color", fill)
	_plate_material.set_shader_parameter("rim_color", rim)
	queue_redraw()


func _draw() -> void:
	if state == State.PURCHASED:
		draw_polyline(
			PackedVector2Array([Vector2(80, 24), Vector2(84, 28), Vector2(92, 19)]),
			Color("c4b2bf"),
			2.0,
			true
		)
	elif state == State.AVAILABLE:
		draw_line(Vector2(80, 24), Vector2(90, 24), Color("e9a0c2"), 2.0, true)
		draw_line(Vector2(85, 19), Vector2(85, 29), Color("e9a0c2"), 2.0, true)
