extends Control

signal close_requested
signal technology_upgrade_requested(id: String)

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
	"combo_reward",
	"combo_interval",
	"net_unlock",
	"net_capacity"
]
const TITLES: PackedStringArray = [
	"基础价值", "吸取速率", "巢穴培育", "完全自动化", "高价值个体", "巨型史莱姆", "连击解锁", "连击奖励", "连击间隔", "捕网解锁", "捕网扩容"
]
const SYMBOLS: PackedInt32Array = [9, 0, 2, 7, 4, 10, 3, 6, 5, 1, 8]
const COLORS: Array[Color] = [
	Color("e2b578"),
	Color("79acd8"),
	Color("83bea2"),
	Color("83bea2"),
	Color("d49c79"),
	Color("e59bbd"),
	Color("d3b575"),
	Color("d3b575"),
	Color("d3b575"),
	Color("b39ada"),
	Color("b39ada")
]

var selected_key: String = "base_value"
var _run: PrototypeRun
var _nodes: Dictionary[String, NodeScript] = {}
var _hovered_key: String = ""
var _pointer_position: Vector2 = Vector2.ZERO

@onready var graph: GraphScript = %Graph
@onready var _canvas: Control = %Canvas
@onready var _wallet: Label = %Wallet
@onready var _detail_icon: GlyphScript = %DetailIcon
@onready var _detail_title: Label = %DetailTitle
@onready var _detail_state: Label = %DetailState
@onready var _detail_level: Label = %DetailLevel
@onready var _detail_gain: RichTextLabel = %DetailGain
@onready var _detail_effect: Label = %DetailEffect
@onready var _detail_note: Label = %DetailNote
@onready var _requirements: VBoxContainer = %Requirements
@onready var _detail: PanelContainer = $Margin/Content/Body/Detail


func _ready() -> void:
	_pointer_position = get_viewport().get_mouse_position()
	%Close.pressed.connect(func() -> void: close_requested.emit())
	_canvas.resized.connect(_fit_graph)
	_fit_graph.call_deferred()
	visibility_changed.connect(_hide_details)


func refresh(run: PrototypeRun) -> void:
	_run = run
	if _nodes.is_empty():
		_build_graph()
	_wallet.text = "%d 糖果" % run.candy
	for id: String in _nodes:
		_nodes[id].refresh(_state_for(id), id == selected_key, _current_level(id))
		_nodes[id].show_price(_max_level(id), _cost(id))
	_refresh_details()
	graph.queue_redraw()


func has_available_technology() -> bool:
	for node: NodeScript in _nodes.values():
		if node.state == NodeScript.State.AVAILABLE:
			return true
	return false


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
			return Vector2(360.0, 458.0)
		"combo_reward":
			return Vector2(270.0, 245.0)
		"combo_interval":
			return Vector2(450.0, 245.0)
		"net_unlock":
			return Vector2(920.0, 458.0)
		"net_capacity":
			return Vector2(920.0, 74.0)
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
		"combo_interval":
			return _run.combo_interval_level + 1 if _run.combo_level > 0 else 0
	return _run.get_technology_level(id)


func _max_level(id: String) -> int:
	match id:
		"base_value":
			return _run.settings.base_value_multipliers.size()
		"pipe":
			return _run.settings.pipe_capture_seconds.size()
		"net_capacity":
			return _run.settings.net_capacities.size()
		"combo_reward":
			return _run.settings.combo_upgrade_costs.size()
		"combo_interval":
			return _run.settings.combo_interval_bonus_seconds.size()
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
	var id: String = selected_key
	var node: NodeScript = _nodes[id]
	_detail_icon.symbol = node.glyph.symbol
	_detail_icon.locked = node.state == NodeScript.State.LOCKED
	_detail_icon.ink = node.glyph.ink
	_detail_icon.queue_redraw()
	_detail_title.text = "未解锁" if _detail_icon.locked else node.title_label.text
	_detail_level.text = "%d/%d" % [_current_level(id), _max_level(id)]
	_detail_level.visible = not _detail_icon.locked
	_detail_state.text = ["已满级", "购买", "糖果不足", ""][node.state]
	_detail_state.add_theme_color_override(
		"font_color", NodeScript.PRICE_COLORS[node.state]
	)
	_detail_effect.text = _effect(id)
	_detail_effect.visible = not _detail_icon.locked
	var values: PackedStringArray = _upgrade_values(id)
	_detail_gain.text = (
		"[font_size=26]%s[/font_size] [color=#bda9b4][font_size=15](%s)[/font_size][/color]"
		% [values[0], values[1]]
	)
	_detail_gain.visible = not _detail_icon.locked
	%DetailPurchase.visible = not _detail_icon.locked
	%DetailCoin.visible = node.state != NodeScript.State.PURCHASED
	%DetailCost.visible = node.state != NodeScript.State.PURCHASED
	%DetailCost.text = str(_cost(id))
	%DetailCost.add_theme_color_override("font_color", NodeScript.PRICE_COLORS[node.state])
	_detail_note.text = _note(id)
	_detail_note.visible = not _detail_icon.locked and not _detail_note.text.is_empty()
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
		label.add_theme_font_size_override("font_size", 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override(
			"font_color", Color("d5b7c9")
		)
		_requirements.add_child(label)


func _effect(id: String) -> String:
	match id:
		"base_value":
			return "提高每只史莱姆的糖果收益。"
		"pipe":
			return "缩短吸入每只个体所需的时间。"
		"net_unlock", "net_capacity":
			return "提高捕网一次可捕获的数量。" if id == "net_capacity" else "解锁范围捕获工具。"
		"cultivation":
			return "开放各巢穴的培育建设。"
		"automation":
			return "开放各巢穴的自动产糖建设。"
		"combo_unlock", "combo_reward":
			return "连续吸入 %d 只后，后续捕获获得额外糖果。" % _run.settings.combo_target
		"combo_interval":
			return "延长两次吸入之间的连击续接时间。"
		"valuable":
			return "每 %d 只新生个体出现 1 只金色个体。" % _run.settings.valuable_spawn_every
		"giant":
			return "屏幕外、活动范围重叠的巢穴可融合个体，保留全部糖果收益。"
	return ""


func _upgrade_values(id: String) -> PackedStringArray:
	var owned: bool = _state_for(id) == NodeScript.State.PURCHASED
	var settings: PrototypeSettings = _run.settings
	match id:
		"base_value":
			var current: int = _run.get_base_value()
			var next_level: int = mini(_run.base_value_level + 1, settings.base_value_multipliers.size() - 1)
			var next: int = settings.slime_reward * settings.base_value_multipliers[next_level]
			return [
				"%d 糖果" % current if owned else "+%d 糖果" % (next - current),
				"当前 %d" % current
			]
		"pipe":
			var current: float = _run.get_pipe_capture_seconds()
			var next_level: int = mini(_run.pipe_level + 1, settings.pipe_capture_seconds.size() - 1)
			var next: float = settings.pipe_capture_seconds[next_level]
			return [
				"%s 秒" % String.num(current, 3) if owned else "−%s 秒" % String.num(current - next, 3),
				"当前 %s 秒" % String.num(current, 3)
			]
		"net_unlock", "net_capacity":
			var current: int = _run.get_net_capacity()
			var next_level: int = mini(_run.net_level + 1, settings.net_capacities.size() - 1)
			var next: int = settings.net_capacities[next_level if id == "net_capacity" else 0]
			return [
				"%d 只" % current if owned else "+%d 只" % (next - current),
				"当前 %d 只" % current
			]
		"combo_unlock", "combo_reward":
			var current: int = _run.get_combo_reward_percent()
			var next_level: int = mini(_run.combo_level + 1, settings.combo_reward_percentages.size() - 1)
			var next: int = settings.combo_reward_percentages[next_level]
			return [
				"+%d%%" % current if owned else "+%d%%" % (next - current),
				"当前 +%d%%" % current
			]
		"combo_interval":
			var current: float = _run.get_combo_window_seconds()
			var next_level: int = mini(
				_run.combo_interval_level + 1, settings.combo_interval_bonus_seconds.size() - 1
			)
			var next: float = settings.combo_window_seconds + settings.combo_interval_bonus_seconds[next_level]
			return [
				"%s 秒" % String.num(current, 1) if owned else "+%s 秒" % String.num(next - current, 1),
				"当前 %s 秒" % String.num(current, 1)
			]
		"valuable":
			return ["糖果 ×%d" % settings.valuable_reward_multiplier, "已解锁" if owned else "未解锁"]
		"giant":
			return ["%d → 1" % settings.giant_fusion_threshold, "已解锁" if owned else "未解锁"]
	return ["已解锁" if owned else "解锁", "已生效" if owned else "未解锁"]


func _note(id: String) -> String:
	match id:
		"base_value":
			return "黏液怪收益为 2 倍；全场个体与自动产糖同步提高。"
		"cultivation":
			return "在具体巢穴投入 %d 糖果建设。" % _run.settings.nest_upgrade_costs[0]
		"automation":
			return (
				"建成后停止产怪，每巢每秒 %.1f 糖果，随基础价值成长。清除场上所有怪物即可获胜。" % _run.get_automatic_income_per_nest()
			)
		"combo_unlock", "combo_reward", "combo_interval":
			return "仅吸管触发；小数奖励累计到账。"
		"net_unlock":
			return "冷却 %s 秒。" % String.num(_run.settings.net_cooldown_seconds, 1)
		"valuable":
			return "研究后出生的个体生效，包含新出现的巢穴。"
		"giant":
			return "全场生效，仍占原有名额；已有巨型不再融合。"
	return ""


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
	select_node(id)
	_detail.show()
	_place_details.call_deferred()


func _hide_node_details(id: String) -> void:
	if _hovered_key == id:
		_hide_details()


func _hide_details() -> void:
	_hovered_key = ""
	_detail.hide()


func _process(_delta: float) -> void:
	if _detail.visible:
		_place_details()


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventMouse:
		_pointer_position = (event as InputEventMouse).position


func _place_details() -> void:
	if _hovered_key.is_empty():
		return
	_detail.size = Vector2(320.0, 0.0)
	var body: Control = _detail.get_parent() as Control
	var to_local: Transform2D = body.get_global_transform_with_canvas().affine_inverse()
	var pointer: Vector2 = to_local * _pointer_position
	var icon_center: Vector2 = (
		to_local * _nodes[_hovered_key].get_global_transform_with_canvas() * NodeScript.ICON_CENTER
	)
	var gap: float = 20.0
	var margin: Vector2 = Vector2(16.0, 16.0)
	var target: Vector2 = pointer + Vector2.ONE * gap
	# Choose the quadrant from the icon so moving across a screen midpoint cannot flip it.
	if icon_center.x > body.size.x * 0.5 or icon_center.x + gap + _detail.size.x > body.size.x - margin.x:
		target.x = pointer.x - _detail.size.x - gap
	if icon_center.y > body.size.y * 0.5 or icon_center.y + gap + _detail.size.y > body.size.y - margin.y:
		target.y = pointer.y - _detail.size.y - gap
	_detail.position = target.clamp(margin, (body.size - _detail.size - margin).max(margin))
