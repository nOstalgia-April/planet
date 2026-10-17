extends Control

signal close_requested
signal technology_upgrade_requested(id: String)

const PaletteSettings = preload("res://scripts/population_palette_settings.gd")
const PALETTE_ART: Shader = preload("res://shaders/population_art.gdshader")
const NodeScene: PackedScene = preload("res://scenes/ui/technology_node.tscn")
const NodeScript = preload("res://scripts/ui/technology_node.gd")
const GraphScript = preload("res://scripts/ui/technology_graph.gd")
const GlyphScript = preload("res://scripts/ui/technology_glyph.gd")
const GRAPH_SIZE: Vector2 = Vector2(1280.0, 660.0)
const TECHNOLOGIES: PackedStringArray = [
	"base_value",
	"pipe",
	"cultivation",
	"automation",
	"valuable",
	"giant",
	"combo_unlock",
	"net_unlock",
	"net_capacity",
	"net_size"
]
const TITLES: PackedStringArray = [
	"基础价值", "吸取速率", "巢穴培育", "完全治理", "高价值个体", "巨型史莱姆", "连击爬梯", "捕网解锁", "捕网扩容", "捕网大小"
]
const SYMBOLS: PackedInt32Array = [9, 0, 2, 7, 4, 10, 3, 1, 8, 1]
const COLORS: Array[Color] = [
	Color("e2b578"),
	Color("79acd8"),
	Color("83bea2"),
	Color("83bea2"),
	Color("d49c79"),
	Color("e59bbd"),
	Color("d3b575"),
	Color("b39ada"),
	Color("b39ada"),
	Color("b39ada")
]

var _palette: PackedColorArray = PaletteSettings.new().pink
var _node_art: ShaderMaterial

var selected_key: String = "base_value"
var _run: PrototypeRun
var _nodes: Dictionary[String, NodeScript] = {}
var _hovered_key: String = ""
var _detail_pointer: Vector2 = Vector2.ZERO
var _opening_cue_pending: bool = true

@onready var graph: GraphScript = %Graph
@onready var _canvas: Control = %Canvas
@onready var _wallet: Label = %Wallet
@onready var _detail_icon: GlyphScript = %DetailIcon
@onready var _detail_title: Label = %DetailTitle
@onready var _detail_level: Label = %DetailLevel
@onready var _detail_gain: RichTextLabel = %DetailGain
@onready var _detail_effect: RichTextLabel = %DetailEffect
@onready var _detail_note: Label = %DetailNote
@onready var _requirements: VBoxContainer = %Requirements
@onready var _detail: PanelContainer = $Margin/Content/Body/Detail


func _ready() -> void:
	# The supplied Chinese face has no usable underline metrics.
	var bold: FontVariation = (
		_detail_effect.get_theme_font("bold_font").duplicate() as FontVariation
	)
	var bold_face: FontFile = bold.base_font.duplicate() as FontFile
	bold_face.set_cache_underline_position(0, 16, 2.0)
	bold_face.set_cache_underline_thickness(0, 16, 1.0)
	bold.base_font = bold_face
	_detail_effect.add_theme_font_override("bold_font", bold)
	_node_art = ShaderMaterial.new()
	_node_art.shader = PALETTE_ART
	_detail.material = _node_art
	set_palette(_palette)
	%Close.pressed.connect(func() -> void: close_requested.emit())
	_canvas.resized.connect(_fit_graph)
	_fit_graph.call_deferred()
	visibility_changed.connect(_on_visibility_changed)


func set_palette(colors: PackedColorArray) -> void:
	_palette = colors
	_node_art.set_shader_parameter("population_palette_enabled", true)
	var parameters: PackedStringArray = [
		"palette_dark", "palette_mid", "palette_ink", "palette_bright", "palette_light"
	]
	for index: int in range(parameters.size()):
		_node_art.set_shader_parameter(parameters[index], colors[index])
	for node: NodeScript in _nodes.values():
		node.set_accent(colors[4], _node_art)
	graph.line_color = PaletteSettings.ui_color(Color("f0a0c5"), colors[4])
	graph.queue_redraw()
	for label: Label in [_wallet, _detail_title, %RequirementHeading]:
		label.add_theme_color_override("font_color", colors[4].lerp(Color.WHITE, 0.65))
	for label: Label in [_detail_level, _detail_note, %NextGoalNote]:
		label.add_theme_color_override("font_color", colors[4].darkened(0.18))
	%NextGoal.add_theme_color_override("font_color", colors[4])
	_detail_gain.add_theme_color_override("default_color", colors[4].lerp(Color.WHITE, 0.65))
	_detail_effect.add_theme_color_override("default_color", colors[4].lerp(Color.WHITE, 0.65))
	for label: Label in _requirements.get_children():
		label.add_theme_color_override("font_color", colors[4].darkened(0.12))
	if _nodes.has(selected_key):
		_detail_icon.ink = _nodes[selected_key].glyph.ink
		_detail_icon.queue_redraw()


func _on_visibility_changed() -> void:
	_hide_details()
	if not is_visible_in_tree():
		_opening_cue_pending = true
		for node: NodeScript in _nodes.values():
			node.stop_available_cue()
	elif _run != null:
		refresh(_run)


func refresh(run: PrototypeRun) -> void:
	_run = run
	if _nodes.is_empty():
		_build_graph()
	_wallet.text = str(run.candy)
	for id: String in _nodes:
		_nodes[id].refresh(
			_state_for(id), _detail.visible and id == selected_key, _current_level(id)
		)
		_nodes[id].show_price(_max_level(id), _cost(id))
	_refresh_details()
	_refresh_goal()
	graph.queue_redraw()
	if _opening_cue_pending and is_visible_in_tree():
		_opening_cue_pending = false
		for node: NodeScript in _nodes.values():
			node.play_available_cue()


func has_available_technology() -> bool:
	for node: NodeScript in _nodes.values():
		if node.state == NodeScript.State.AVAILABLE:
			return true
	return false


func is_technology_available(id: String) -> bool:
	return _nodes.has(id) and _nodes[id].state == NodeScript.State.AVAILABLE


func focus_available_goal() -> void:
	if is_visible_in_tree() and is_technology_available("automation"):
		_nodes["automation"].grab_focus()
		_show_details("automation")


func select_node(id: String) -> void:
	assert(_nodes.has(id), "Technology selection must name an existing upgrade item.")
	if _hovered_key != id:
		_hide_details()
	selected_key = id
	refresh(_run)


func _build_graph() -> void:
	for index: int in range(TECHNOLOGIES.size()):
		var id: String = TECHNOLOGIES[index]
		var node: NodeScript = NodeScene.instantiate() as NodeScript
		node.name = id
		graph.add_child(node)
		node.configure(id, TITLES[index], SYMBOLS[index], COLORS[index])
		node.set_accent(_palette[4], _node_art)
		node.position = _node_position(id) - NodeScript.ICON_CENTER
		node.pressed.connect(_activate_node.bind(id))
		node.mouse_entered.connect(_show_details.bind(id))
		node.mouse_exited.connect(_hide_node_details.bind(id))
		node.focus_entered.connect(_show_details.bind(id))
		node.focus_exited.connect(_hide_node_details.bind(id))
		node.set_meta(UiAudio.PURCHASE_META, true)
		_nodes[id] = node
	graph.nodes = _nodes
	graph.node_keys = TECHNOLOGIES
	for id: String in TECHNOLOGIES:
		for prerequisite: String in _node_prerequisites(id):
			if id == "net_size" and prerequisite == "net_unlock":
				continue
			graph.links.append(Vector2i(TECHNOLOGIES.find(prerequisite), TECHNOLOGIES.find(id)))
	_fit_graph()


func _node_position(id: String) -> Vector2:
	match id:
		"base_value":
			return Vector2(640.0, 426.0)
		"pipe":
			return Vector2(640.0, 562.0)
		"cultivation":
			return Vector2(640.0, 285.0)
		"automation":
			return Vector2(640.0, 74.0)
		"valuable":
			return Vector2(820.0, 200.0)
		"giant":
			return Vector2(820.0, 330.0)
		"combo_unlock":
			return Vector2(360.0, 300.0)
		"net_unlock":
			return Vector2(920.0, 458.0)
		"net_capacity":
			return Vector2(1080.0, 265.0)
		"net_size":
			return Vector2(1080.0, 74.0)
	return Vector2.ZERO


func _fit_graph() -> void:
	var available: Vector2 = _canvas.size - Vector2(24.0, 20.0)
	var factor: float = minf(available.x / GRAPH_SIZE.x, available.y / GRAPH_SIZE.y)
	graph.scale = Vector2.ONE * maxf(0.1, factor)
	graph.size = GRAPH_SIZE
	graph.position = (_canvas.size - GRAPH_SIZE * graph.scale) * 0.5


func _current_level(id: String) -> int:
	match id:
		"base_value":
			return _run.base_value_level + 1
		"pipe":
			return _run.pipe_level + 1
		"net_capacity":
			return _run.net_level + 1 if _run.net_unlocked else 0
		"net_size":
			return _run.net_size_level + 1 if _run.get_technology_requirement(id).is_empty() else 0
	return _run.get_technology_level(id)


func _max_level(id: String) -> int:
	match id:
		"base_value":
			return _run.settings.base_value_multipliers.size()
		"pipe":
			return _run.settings.pipe_capture_seconds.size()
		"net_capacity":
			return _run.settings.net_capacities.size()
		"net_size":
			return _run.settings.net_size_multipliers.size()
		"combo_unlock":
			return _run.settings.combo_upgrade_costs.size()
		"valuable":
			return _run.settings.valuable_upgrade_costs.size()
	return 1


func _cost(id: String) -> int:
	return _run.get_technology_cost(id)


func _node_prerequisites(id: String) -> Dictionary[String, int]:
	var result: Dictionary[String, int] = _run.get_technology_prerequisites(id)
	# The initial tool anchors the central path without adding a research gate.
	if id == "base_value":
		result["pipe"] = 0
	elif id == "cultivation":
		result["base_value"] = 0
	return result


func _state_for(id: String) -> NodeScript.State:
	if _current_level(id) >= _max_level(id):
		return NodeScript.State.PURCHASED
	var requirement: String = _run.get_technology_requirement(id)
	if not requirement.is_empty():
		return NodeScript.State.LOCKED
	return NodeScript.State.AVAILABLE if _run.candy >= _cost(id) else NodeScript.State.UNAFFORDABLE


func _refresh_details() -> void:
	# Economy updates also arrive while this panel is closed. Refresh the
	# description and prerequisite controls when the player actually opens it.
	if not _detail.visible:
		return
	var id: String = selected_key
	var node: NodeScript = _nodes[id]
	_detail_icon.symbol = node.glyph.symbol
	_detail_icon.locked = node.state == NodeScript.State.LOCKED
	_detail_icon.ink = node.glyph.ink
	_detail_icon.queue_redraw()
	_detail_title.text = node.title_label.text
	_detail_level.text = (
		"Lv.%d → Lv.%d" % [_current_level(id), mini(_current_level(id) + 1, _max_level(id))]
	)
	if node.state == NodeScript.State.PURCHASED:
		_detail_level.text = "Lv.%d/%d · MAX" % [_current_level(id), _max_level(id)]
	_detail_level.visible = not _detail_icon.locked
	_detail_effect.text = _run.get_technology_description(id)
	if id == "automation":
		_detail_effect.text = _detail_effect.text.replace("最终帮助星球自愈！", "[b][u]最终帮助星球自愈！[/u][/b]")
	_detail_effect.visible = not _detail_effect.text.is_empty()
	var gain: String = _run.get_technology_gain(id)
	_detail_gain.text = "[font_size=18]%s[/font_size]" % gain
	_detail_gain.visible = not gain.is_empty()
	_detail_note.text = "再攒 %d 糖果即可升级" % maxi(0, _cost(id) - _run.candy)
	_detail_note.visible = node.state == NodeScript.State.UNAFFORDABLE
	for child: Node in _requirements.get_children():
		_requirements.remove_child(child)
		child.queue_free()
	var prerequisites: Dictionary[String, int] = _run.get_technology_prerequisites(id)
	%RequirementHeading.visible = node.state == NodeScript.State.LOCKED
	_requirements.visible = node.state == NodeScript.State.LOCKED
	for prerequisite: String in prerequisites:
		var required_level: int = prerequisites[prerequisite]
		var fulfilled: bool = _run.get_technology_level(prerequisite) >= required_level
		if fulfilled:
			continue
		var label: Label = Label.new()
		label.text = "%s  %s" % ["✓" if fulfilled else "○", _nodes[prerequisite].title_label.text]
		if prerequisite == "pipe":
			label.text += " · %d级" % (required_level + 1)
		elif prerequisite == "net_capacity":
			label.text += " · %d级（满级）" % (required_level + 1)
		label.add_theme_font_size_override("font_size", 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_color", _palette[4].darkened(0.12))
		_requirements.add_child(label)
	_place_details.call_deferred()


func _refresh_goal() -> void:
	%NextGoal.text = ""
	%NextGoalNote.text = ""
	for id: String in ["net_unlock", "cultivation", "automation"]:
		if _run.get_technology_level(id) > 0:
			continue
		if _state_for(id) == NodeScript.State.LOCKED and id != "automation":
			break
		var prerequisites: Dictionary[String, int] = _run.get_technology_prerequisites(id)
		var fulfilled: int = 0
		for prerequisite: String in prerequisites:
			if _run.get_technology_level(prerequisite) >= prerequisites[prerequisite]:
				fulfilled += 1
		%NextGoal.text = "下一项关键解锁 · " + _nodes[id].title_label.text
		var progress: String = "前置已满足"
		if fulfilled < prerequisites.size():
			progress = "前置 %d/%d" % [fulfilled, prerequisites.size()]
		var purposes: Dictionary[String, String] = {
			"net_unlock": "一次捕获成群史莱姆", "cultivation": "培育巢穴，容纳更多怪物", "automation": "开放自动化改造，持续产糖"
		}
		%NextGoalNote.text = purposes[id] + "  ·  " + progress
		break


func _purchase_selected() -> void:
	if _state_for(selected_key) != NodeScript.State.AVAILABLE:
		if _state_for(selected_key) == NodeScript.State.UNAFFORDABLE:
			UiAudio.insufficient_points()
		return
	technology_upgrade_requested.emit(selected_key)


func _activate_node(id: String) -> void:
	select_node(id)
	_purchase_selected()


func _show_details(id: String) -> void:
	_hovered_key = id
	_detail_pointer = get_viewport().get_mouse_position()
	if not _nodes[id].is_hovered():
		_detail_pointer = _nodes[id].get_global_rect().get_center()
	_detail.show()
	select_node(id)
	_place_details.call_deferred()


func _hide_node_details(id: String) -> void:
	if _hovered_key == id:
		_hide_details()


func _hide_details() -> void:
	_hovered_key = ""
	_detail.hide()
	for node: NodeScript in _nodes.values():
		node.selected = false
		node._refresh_appearance()
	graph.queue_redraw()


func _place_details() -> void:
	if not _detail.visible:
		return
	_detail.size = Vector2(248.0, 0.0)
	var body: Control = _detail.get_parent() as Control
	var inverse: Transform2D = body.get_global_transform_with_canvas().affine_inverse()
	var node: NodeScript = _nodes[selected_key]
	if node.has_focus() and not node.is_hovered():
		var node_rect: Rect2 = inverse * node.get_global_rect()
		var beside: Vector2 = Vector2(node_rect.end.x + 24.0, node_rect.position.y)
		if beside.x + _detail.size.x > body.size.x - 12.0:
			beside.x = node_rect.position.x - _detail.size.x - 24.0
		_detail.position = beside.clamp(
			Vector2(12.0, 12.0), body.size - _detail.size - Vector2(12.0, 12.0)
		)
		return
	var pointer: Vector2 = inverse * _detail_pointer
	var node_center: Vector2 = inverse * _nodes[selected_key].get_global_rect().get_center()
	var offset: Vector2 = Vector2(24.0, 24.0)
	if node_center.x > body.size.x * 0.5:
		offset.x = -_detail.size.x - 24.0
	if node_center.y > body.size.y * 0.5:
		offset.y = -_detail.size.y - 24.0
	_detail.position = (pointer + offset).clamp(
		Vector2(12.0, 12.0), body.size - _detail.size - Vector2(12.0, 12.0)
	)


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventMouseMotion:
		_detail_pointer = (event as InputEventMouseMotion).position
		_place_details()
