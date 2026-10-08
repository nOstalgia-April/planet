extends Button

enum State { PURCHASED, AVAILABLE, UNAFFORDABLE, LOCKED }

const GlyphScript = preload("res://scripts/ui/technology_glyph.gd")
const ICON_CENTER: Vector2 = Vector2(80.0, 36.0)

var technology_id: String = ""
var level: int = 0
var state: State = State.LOCKED
var accent: Color = Color("83b7df")
var selected: bool = false
var _pulse: float = 0.0
var _square_style: StyleBoxFlat = StyleBoxFlat.new()
var _selection_style: StyleBoxFlat = StyleBoxFlat.new()
var _halo_style: StyleBoxFlat = StyleBoxFlat.new()

@onready var glyph: GlyphScript = $Glyph
@onready var title_label: Label = $Title
@onready var level_label: Label = $Level


func _ready() -> void:
	for style: StyleBoxFlat in [_square_style, _selection_style, _halo_style]:
		style.set_corner_radius_all(7)
	_square_style.set_border_width_all(2)
	_selection_style.set_border_width_all(1)
	_selection_style.bg_color = Color.TRANSPARENT
	_selection_style.border_color = Color("f0f2e8")
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
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
	level_label.text = str(level)
	set_process(state == State.AVAILABLE)
	var ink: Color = Color("83939a") if state == State.LOCKED else Color("edf1ed")
	if state == State.AVAILABLE:
		ink = Color("f8d477")
	title_label.add_theme_color_override("font_color", ink)
	level_label.add_theme_color_override("font_color", accent.lightened(0.25) if level > 0 else ink)
	glyph.ink = Color("71858c") if state == State.LOCKED else accent.lightened(0.25)
	glyph.inset = Color("82949b") if state == State.LOCKED else Color("e5eeed")
	glyph.queue_redraw()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_pulse = fmod(_pulse + delta * 2.0, TAU)
	queue_redraw()


func _draw() -> void:
	var square: Rect2 = Rect2(ICON_CENTER - Vector2.ONE * 34.0, Vector2.ONE * 68.0)
	var frame: Color = Color("465962")
	var fill: Color = Color("223138")
	if state == State.PURCHASED:
		frame = accent
		fill = accent.darkened(0.67)
	elif state == State.UNAFFORDABLE:
		frame = accent.darkened(0.28)
		fill = accent.darkened(0.67 if level > 0 else 0.83)
	elif state == State.AVAILABLE:
		frame = Color("f3cc67")
		fill = Color("4b452b")
		var strength: float = 0.7 + 0.3 * sin(_pulse)
		_halo_style.bg_color = Color(frame, 0.025 * strength)
		for ring: int in range(5, 0, -1):
			draw_style_box(_halo_style, square.grow(float(ring) * 3.5))
		for ray: int in range(8):
			var direction: Vector2 = Vector2.from_angle(float(ray) * PI / 4.0 + 0.2)
			var normal: Vector2 = direction.orthogonal() * 3.0
			var points: PackedVector2Array = PackedVector2Array(
				[
					ICON_CENTER + direction * 37.0 + normal,
					ICON_CENTER + direction * (53.0 + 7.0 * strength),
					ICON_CENTER + direction * 37.0 - normal,
				]
			)
			draw_colored_polygon(points, Color(frame, 0.16 * strength))
	if is_hovered() or has_focus():
		frame = frame.lightened(0.3)
		fill = fill.lightened(0.05)
	_square_style.bg_color = fill
	_square_style.border_color = frame
	draw_style_box(_square_style, square)
	if selected:
		draw_style_box(_selection_style, square.grow(5.0))
	# Text stays below the single icon and masks any vertical prerequisite line.
	var text_width: float = (
		(
			title_label
			. get_theme_font("font")
			. get_string_size(title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
			. x
		)
		+ 10.0
	)
	draw_rect(Rect2(63.0, 74.0, 34.0, 24.0), Color("101e26"))
	draw_rect(Rect2(80.0 - text_width * 0.5, 99.0, text_width, 24.0), Color("101e26"))
	if level > 0:
		draw_polyline(
			PackedVector2Array([Vector2(37.0, 5.0), Vector2(41.0, 9.0), Vector2(48.0, 1.0)]),
			accent,
			2.0,
			true
		)
