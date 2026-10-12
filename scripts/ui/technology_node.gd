extends Button

enum State { PURCHASED, AVAILABLE, UNAFFORDABLE, LOCKED }

const GlyphScript = preload("res://scripts/ui/technology_glyph.gd")
const ICON_CENTER: Vector2 = Vector2(60.0, 48.0)
const PRICE_COLORS: Array[Color] = [
	Color("fff4d9"), Color("b9e6ae"), Color("d7a18f"), Color("b4a3b0")
]
const HALO_OPACITY: PackedFloat32Array = [0.85, 1.0, 0.8, 0.6]

var technology_id: String = ""
var level: int = 0
var state: State = State.LOCKED
var accent: Color = Color("f84798")
var selected: bool = false
var is_endpoint: bool = false

@onready var glyph: GlyphScript = $Glyph
@onready var title_label: Label = $Title
@onready var level_label: Label = $Level
@onready var price_label: Label = $Price/Value
@onready var coin: TextureRect = $Price/Coin
@onready var _halo: TextureRect = $Halo
@onready var _focus_ink: TextureRect = $FocusInk


func _ready() -> void:
	mouse_entered.connect(_refresh_appearance)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_refresh_appearance)
	focus_exited.connect(_refresh_appearance)
	glyph.use_supplied_art = true
	set_process(false)


func configure(id: String, title: String, symbol: int, color: Color) -> void:
	technology_id = id
	title_label.text = title
	glyph.symbol = symbol
	accent = color
	is_endpoint = id == "automation"


func refresh(next_state: State, is_selected: bool, current_level: int) -> void:
	state = next_state
	selected = is_selected
	level = current_level
	glyph.locked = state == State.LOCKED
	glyph.ink = Color.WHITE
	level_label.add_theme_color_override("font_color", Color("fff0f7"))
	title_label.visible = is_endpoint and not glyph.locked
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
	_halo.visible = not active
	_halo.modulate.a = HALO_OPACITY[state]
	_focus_ink.visible = active
	queue_redraw()


func _on_mouse_exited() -> void:
	# Hand control back to the pointer after a click; do not leave two black nodes.
	release_focus()
	_refresh_appearance()


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
