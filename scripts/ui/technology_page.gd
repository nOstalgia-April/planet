extends Control

signal close_requested
signal technology_upgrade_requested(id: String)
signal nest_technology_upgrade_requested(nest_id: int, id: String)
signal nest_selected(nest_id: int)

const NodeScene: PackedScene = preload("res://scenes/ui/technology_node.tscn")
const NodeScript = preload("res://scripts/ui/technology_node.gd")
const GraphScript = preload("res://scripts/ui/technology_graph.gd")
const GlyphScript = preload("res://scripts/ui/technology_glyph.gd")
const GRAPH_SIZE: Vector2 = Vector2(1280.0, 660.0)
const TECHNOLOGIES: PackedStringArray = [
	"pipe",
	"cultivation",
	"automation",
	"valuable",
	"combo_unlock",
	"combo_reward",
	"combo_interval",
	"net_unlock",
	"net_capacity"
]
const TITLES: PackedStringArray = [
	"吸取速率", "巢穴培育", "完全自动化", "高价值个体", "连击解锁", "连击奖励", "连击间隔", "捕网解锁", "捕网扩容"
]
const SYMBOLS: PackedInt32Array = [0, 2, 7, 4, 3, 6, 5, 1, 8]
const COLORS: Array[Color] = [
	Color("79acd8"),
	Color("83bea2"),
	Color("83bea2"),
	Color("d49c79"),
	Color("d3b575"),
	Color("d3b575"),
	Color("d3b575"),
	Color("b39ada"),
	Color("b39ada")
]

var selected_key: String = "pipe"
var selected_nest_id: int = 1
var _run: PrototypeRun
var _nodes: Dictionary[String, NodeScript] = {}

@onready var graph: GraphScript = %Graph
@onready var purchase: Button = %Purchase
@onready var _canvas: Control = %Canvas
@onready var _wallet: Label = %Wallet
@onready var _detail_icon: GlyphScript = %DetailIcon
@onready var _detail_title: Label = %DetailTitle
@onready var _detail_level: Label = %DetailLevel
@onready var _detail_state: Label = %DetailState
@onready var _detail_effect: Label = %DetailEffect
@onready var _detail_note: Label = %DetailNote
@onready var _requirements: VBoxContainer = %Requirements
@onready var _scope: OptionButton = %Scope


func _ready() -> void:
	%Close.pressed.connect(func() -> void: close_requested.emit())
	purchase.pressed.connect(_purchase_selected)
	_scope.item_selected.connect(_select_scope)
	_canvas.resized.connect(_fit_graph)
	_fit_graph.call_deferred()


func refresh(run: PrototypeRun, nest_id: int = 1) -> void:
	_run = run
	selected_nest_id = clampi(nest_id, 1, maxi(1, run.nests.size()))
	if _nodes.is_empty():
		_build_graph()
	_wallet.text = "%d 糖果" % run.candy
	for id: String in _nodes:
		_nodes[id].refresh(_state_for(id), id == selected_key, _current_level(id))
	_refresh_scope()
	_refresh_details()
	graph.queue_redraw()


func select_node(id: String) -> void:
	assert(_nodes.has(id), "Technology selection must name an existing upgrade item.")
	selected_key = id
	refresh(_run, selected_nest_id)


func _build_graph() -> void:
	for index: int in range(TECHNOLOGIES.size()):
		var id: String = TECHNOLOGIES[index]
		var node: NodeScript = NodeScene.instantiate() as NodeScript
		node.name = id
		graph.add_child(node)
		node.configure(id, TITLES[index], SYMBOLS[index], COLORS[index])
		node.position = _node_position(id) - NodeScript.ICON_CENTER
		node.pressed.connect(select_node.bind(id))
		_nodes[id] = node
	graph.nodes = _nodes
	graph.node_keys = TECHNOLOGIES
	for id: String in TECHNOLOGIES:
		for prerequisite: String in _node_prerequisites(id):
			graph.links.append(Vector2i(TECHNOLOGIES.find(prerequisite), TECHNOLOGIES.find(id)))
	_fit_graph()


func _node_position(id: String) -> Vector2:
	match id:
		"pipe":
			return Vector2(640.0, 562.0)
		"cultivation":
			return Vector2(640.0, 285.0)
		"automation":
			return Vector2(640.0, 74.0)
		"valuable":
			return Vector2(830.0, 285.0)
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
		"pipe":
			return _run.pipe_level + 1
		"net_capacity":
			return _run.net_level + 1 if _run.net_unlocked else 0
		"combo_interval":
			return _run.combo_interval_level + 1 if _run.combo_level > 0 else 0
		"valuable":
			var nest: NestState = _run.get_nest(selected_nest_id)
			return nest.valuable_level if nest != null else 0
	return _run.get_technology_level(id)


func _max_level(id: String) -> int:
	match id:
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
	if id == "valuable":
		return _run.get_nest_technology_cost(selected_nest_id, id)
	return _run.get_technology_cost(id)


func _node_prerequisites(id: String) -> Dictionary[String, int]:
	var result: Dictionary[String, int] = _run.get_technology_prerequisites(id)
	# The initial tool anchors the central path without adding a research gate.
	if id == "cultivation":
		result["pipe"] = 0
	return result


func _state_for(id: String) -> NodeScript.State:
	if _current_level(id) >= _max_level(id):
		return NodeScript.State.PURCHASED
	var requirement: String = (
		_run.get_nest_technology_requirement(selected_nest_id, id)
		if id == "valuable"
		else _run.get_technology_requirement(id)
	)
	if not requirement.is_empty():
		return NodeScript.State.LOCKED
	return NodeScript.State.AVAILABLE if _run.candy >= _cost(id) else NodeScript.State.UNAFFORDABLE


func _refresh_scope() -> void:
	if _scope.item_count != _run.nests.size():
		_scope.clear()
		for nest: NestState in _run.nests:
			_scope.add_item(
				(
					"巢穴 %02d · %s"
					% [nest.nest_id, "史莱姆" if nest.species == NestState.Species.SLIME else "黏液怪"]
				),
				nest.nest_id
			)
	if not _run.nests.is_empty():
		_scope.select(_scope.get_item_index(selected_nest_id))
	_scope.visible = selected_key == "valuable"


func _refresh_details() -> void:
	var id: String = selected_key
	var node: NodeScript = _nodes[id]
	_detail_icon.symbol = node.glyph.symbol
	_detail_icon.ink = node.accent
	_detail_icon.queue_redraw()
	_detail_title.text = node.title_label.text
	_detail_level.text = "当前等级 %d / %d" % [_current_level(id), _max_level(id)]
	_detail_state.text = ["已完成", "可购买", "糖果不足", "前置未满足"][node.state]
	_detail_state.add_theme_color_override(
		"font_color", Color("f3cc67") if node.state == NodeScript.State.AVAILABLE else node.accent
	)
	_detail_effect.text = _effect(id)
	_detail_note.text = _note(id)
	_detail_note.visible = not _detail_note.text.is_empty()
	for child: Node in _requirements.get_children():
		_requirements.remove_child(child)
		child.queue_free()
	var prerequisites: Dictionary[String, int] = _run.get_technology_prerequisites(id)
	%RequirementHeading.visible = not prerequisites.is_empty()
	for prerequisite: String in prerequisites:
		var required_level: int = prerequisites[prerequisite]
		var fulfilled: bool = _run.get_technology_level(prerequisite) >= required_level
		var label: Label = Label.new()
		label.text = "%s  %s" % ["✓" if fulfilled else "○", _nodes[prerequisite].title_label.text]
		if prerequisite == "pipe":
			label.text += " · %d级" % (required_level + 1)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override(
			"font_color", Color("8dbca8") if fulfilled else Color("8b9ba2")
		)
		_requirements.add_child(label)
	%Cost.text = "" if node.state == NodeScript.State.PURCHASED else "%d 糖果" % _cost(id)
	purchase.disabled = node.state != NodeScript.State.AVAILABLE
	match node.state:
		NodeScript.State.PURCHASED:
			purchase.text = "已达最高等级" if _max_level(id) > 1 else "已完成"
		NodeScript.State.AVAILABLE:
			purchase.text = "解锁" if id in ["net_unlock", "combo_unlock"] else "研究"
		NodeScript.State.UNAFFORDABLE:
			purchase.text = "还需 %d 糖果" % (_cost(id) - _run.candy)
		NodeScript.State.LOCKED:
			purchase.text = "需要前置科技"


func _effect(id: String) -> String:
	if _state_for(id) == NodeScript.State.PURCHASED:
		match id:
			"pipe":
				return "每只 %s 秒" % String.num(_run.get_pipe_capture_seconds(), 3)
			"net_capacity":
				return "一次捕获 %d 只" % _run.get_net_capacity()
			"combo_reward":
				return "连续吸入 %d 只后\n每只额外 +%d 糖果" % [_run.settings.combo_target, _run.combo_level]
			"combo_interval":
				return "续接间隔 %s 秒" % String.num(_run.get_combo_window_seconds(), 1)
	if id == "net_unlock":
		return (
			"一次捕获 %d 只\n冷却 %s 秒"
			% [_run.settings.net_capacities[0], String.num(_run.settings.net_cooldown_seconds, 1)]
		)
	if id == "combo_reward" and _run.combo_level == 0:
		return "提高连击后的额外糖果奖励。"
	return _run.get_technology_description(id)


func _note(id: String) -> String:
	match id:
		"net_unlock":
			return "解锁时发现一座黏液巢穴。"
		"cultivation":
			return "在具体巢穴投入 %d 糖果建设。" % _run.settings.nest_upgrade_costs[0]
		"automation":
			return "各巢穴仍需逐步建设；全部自动化即可达成目标。"
		"combo_unlock", "combo_reward", "combo_interval":
			return "吸管每次吸入续接连击；捕网与自动采集不计入。"
		"valuable":
			return "只影响选中巢穴此后刷新的个体。"
	return ""


func _purchase_selected() -> void:
	if _state_for(selected_key) != NodeScript.State.AVAILABLE:
		return
	if selected_key == "valuable":
		nest_technology_upgrade_requested.emit(selected_nest_id, selected_key)
	else:
		technology_upgrade_requested.emit(selected_key)


func _select_scope(index: int) -> void:
	selected_nest_id = _scope.get_item_id(index)
	nest_selected.emit(selected_nest_id)
	refresh(_run, selected_nest_id)
