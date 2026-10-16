extends Button

enum State { PURCHASED, AVAILABLE, UNAFFORDABLE, LOCKED }

const PaletteSettings = preload("res://scripts/population_palette_settings.gd")
const GlyphScript = preload("res://scripts/ui/technology_glyph.gd")
const AvailableCueScript = preload("res://scripts/effects/technology_available_cue.gd")
const ICON_CENTER: Vector2 = Vector2(70.0, 40.0)
const PRICE_COLORS: Array[Color] = [
	Color("c6adba"), Color("ffe4f0"), Color("b59aa9"), Color("947987")
]
const INK_COLORS: Array[Color] = [Color("c6adba"), Color.WHITE, Color("b59aa9"), Color("947987")]
const MILESTONES: Dictionary[String, String] = {
	"net_unlock": "解锁工具", "cultivation": "经营巢穴", "automation": "自动产糖"
}

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
@onready var _halo: TextureRect = $Halo
@onready var _focus_ink: TextureRect = $FocusInk
@onready var _purchase_glow: ColorRect = $PurchaseGlow
@onready var _available_cue: AvailableCueScript = $AvailableCue


func _ready() -> void:
	mouse_entered.connect(_refresh_appearance)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_refresh_appearance)
	focus_exited.connect(_refresh_appearance)
	glyph.use_supplied_art = true
	_purchase_glow.material = _purchase_glow.material.duplicate()
	set_process(false)


func configure(id: String, title: String, symbol: int, color: Color) -> void:
	technology_id = id
	title_label.text = title
	glyph.symbol = symbol
	accent = color
	$Milestone.text = MILESTONES.get(id, "")
	$Milestone.visible = MILESTONES.has(id)
	if MILESTONES.has(id):
		glyph.position -= Vector2(4.0, 4.0)
		glyph.size += Vector2(8.0, 8.0)
	if id == "base_value":
		glyph.position -= Vector2(8.0, 8.0)
		glyph.size += Vector2(16.0, 16.0)
		title_label.add_theme_font_size_override("font_size", 22)


func set_accent(color: Color, artwork: ShaderMaterial) -> void:
	accent = color
	_halo.material = artwork
	_focus_ink.material = artwork
	(_purchase_glow.material as ShaderMaterial).set_shader_parameter(
		"glow_color", _color(Color("ffc7e6"))
	)
	_available_cue.set_color(_color(Color("ffabd4")))
	refresh(state, selected, level)


func _color(source: Color) -> Color:
	return PaletteSettings.ui_color(source, accent)


func refresh(next_state: State, is_selected: bool, current_level: int) -> void:
	state = next_state
	if state != State.AVAILABLE:
		_available_cue.stop()
	selected = is_selected
	level = current_level
	glyph.locked = state == State.LOCKED
	glyph.ink = _color(INK_COLORS[state])
	level_label.add_theme_color_override("font_color", _color(PRICE_COLORS[state]))
	title_label.add_theme_color_override("font_color", _color(INK_COLORS[state]))
	$Milestone.modulate = Color.WHITE
	$Milestone.add_theme_color_override("font_color", _color(INK_COLORS[state]))
	price_label.add_theme_color_override("font_color", _color(PRICE_COLORS[state]))
	for label: Label in [level_label, price_label]:
		label.add_theme_color_override("font_outline_color", _color(Color("1a030f")))
	var revealed: bool = state != State.LOCKED or technology_id == "automation"
	title_label.visible = revealed
	level_label.visible = revealed
	$Price.visible = revealed
	$Milestone.visible = revealed and MILESTONES.has(technology_id)
	glyph.queue_redraw()
	_refresh_appearance()


func play_available_cue() -> void:
	if state == State.AVAILABLE:
		_available_cue.play()


func stop_available_cue() -> void:
	_available_cue.stop()


func show_price(max_level: int, cost: int) -> void:
	level_label.text = "Lv.%d/%d" % [level, max_level]
	price_label.text = str(cost)
	if state == State.PURCHASED:
		price_label.text = "✓ MAX"
	elif state == State.LOCKED:
		price_label.text = "未解锁"
	price_label.add_theme_color_override("font_color", _color(PRICE_COLORS[state]))
	coin.visible = state in [State.AVAILABLE, State.UNAFFORDABLE]
	coin.modulate.a = 1.0 if state == State.AVAILABLE else 0.55


func _refresh_appearance() -> void:
	var active: bool = selected or is_hovered() or has_focus()
	_purchase_glow.visible = state == State.AVAILABLE
	_halo.visible = state == State.AVAILABLE or (active and state != State.PURCHASED)
	_halo.modulate.a = 0.85 if active else 0.55
	_focus_ink.visible = active
	title_label.add_theme_color_override(
		"font_color", _color(Color("ffc4e0") if active else INK_COLORS[state])
	)
	queue_redraw()


func _on_mouse_exited() -> void:
	# Pointer inspection owns the selection after a click.
	release_focus()
	_refresh_appearance()


func _draw() -> void:
	if selected or is_hovered() or has_focus():
		draw_arc(ICON_CENTER, 43.0, 0.0, TAU, 64, _color(Color("f84798")), 2.0, true)
	elif state == State.AVAILABLE:
		draw_arc(ICON_CENTER, 40.0, 0.0, TAU, 64, _color(Color("cf7d9f")), 1.0, true)
	if state == State.PURCHASED:
		draw_polyline(
			PackedVector2Array([Vector2(94, 22), Vector2(98, 26), Vector2(106, 17)]),
			_color(Color("c4b2bf")),
			2.0,
			true
		)
	elif state == State.AVAILABLE:
		draw_line(Vector2(94, 22), Vector2(104, 22), _color(Color("ffe4f0")), 2.0, true)
		draw_line(Vector2(99, 17), Vector2(99, 27), _color(Color("ffe4f0")), 2.0, true)
