extends PanelContainer

signal upgrade_requested
signal scope_step_requested(direction: int)

@export var technology_id: String = "pipe"
@export var branch_title: String = "吸取管"
@export var branch_category: String = "基础工具"
@export var stage_names: PackedStringArray = PackedStringArray(["灵巧管路", "高速管路", "涡轮管路"])
@export_range(0, 4) var icon_index: int = 0
var _displayed_level: int = -99
var _stage_panels: Array[PanelContainer] = []
var _stage_styles: Array[StyleBoxFlat] = []

@onready var _title: Label = $Content/Identity/Title
@onready var _category: Label = $Content/Identity/Category
@onready var _stages: HBoxContainer = $Content/Progress/Stages
@onready var _description: Label = $Content/Progress/Description
@onready var _requirement: Label = $Content/Action/Requirement
@onready var _purchase: Button = $Content/Action/Purchase
@onready var _scope: HBoxContainer = $Content/Progress/Scope
@onready var _scope_label: Label = $Content/Progress/Scope/Region


func _ready() -> void:
	_title.text = branch_title
	_category.text = branch_category
	$Content/Icon.symbol = icon_index
	$Content/Icon.queue_redraw()
	_purchase.pressed.connect(func() -> void: upgrade_requested.emit())
	$Content/Progress/Scope/Previous.pressed.connect(func() -> void: scope_step_requested.emit(-1))
	$Content/Progress/Scope/Next.pressed.connect(func() -> void: scope_step_requested.emit(1))
	_prepare_stage_styles()
	configure_stages(stage_names)
	_scope.visible = technology_id == "valuable"


func configure_stages(names: PackedStringArray) -> void:
	if names == stage_names and _stage_panels.size() == names.size():
		return
	stage_names = names
	_displayed_level = -99
	var template: PanelContainer = _stages.get_node("Stage1") as PanelContainer
	for child: Node in _stages.get_children():
		if child != template:
			_stages.remove_child(child)
			child.queue_free()
	_stage_panels.clear()
	template.visible = not names.is_empty()
	for index: int in range(names.size()):
		var stage: PanelContainer = template
		if index > 0:
			var link: Label = Label.new()
			link.name = "Link%d" % index
			link.mouse_filter = Control.MOUSE_FILTER_IGNORE
			link.text = "—"
			link.add_theme_color_override("font_color", Color("b0baa6"))
			_stages.add_child(link)
			stage = template.duplicate() as PanelContainer
			stage.name = "Stage%d" % (index + 1)
			_stages.add_child(stage)
		(stage.get_node("Name") as Label).text = names[index]
		_stage_panels.append(stage)


func _prepare_stage_styles() -> void:
	for state: int in range(3):
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.set_corner_radius_all(7)
		style.content_margin_top = 7.0
		style.content_margin_bottom = 7.0
		style.content_margin_left = 7.0
		style.content_margin_right = 7.0
		style.bg_color = [Color("d8e7d6"), Color("f4dec4"), Color("ececdf")][state]
		if state == 1:
			style.set_border_width_all(1)
			style.border_color = Color("cb8c55")
		_stage_styles.append(style)


func refresh(level: int, cost: int, description: String, requirement: String, candy: int) -> void:
	_description.text = description
	var is_maximum: bool = cost < 0
	_purchase.disabled = is_maximum or not requirement.is_empty() or candy < cost
	_purchase.text = "已完成研究" if is_maximum else "研究 · %d 糖果" % cost
	_requirement.text = "" if is_maximum else requirement
	if not is_maximum and requirement.is_empty():
		_requirement.text = "" if candy >= cost else "还需 %d 糖果" % (cost - candy)
	if _displayed_level == level:
		return
	_displayed_level = level
	for index: int in range(stage_names.size()):
		var stage: PanelContainer = _stage_panels[index]
		var label: Label = stage.get_node("Name") as Label
		var state: int = 2
		if index < level:
			state = 0
			label.add_theme_color_override("font_color", Color("31594e"))
		elif index == level:
			state = 1
			label.add_theme_color_override("font_color", Color("8c572e"))
		else:
			label.add_theme_color_override("font_color", Color("8b927f"))
		stage.add_theme_stylebox_override("panel", _stage_styles[state])


func set_nest_scope(nest_name: String, can_cycle: bool) -> void:
	_scope_label.text = nest_name
	$Content/Progress/Scope/Previous.disabled = not can_cycle
	$Content/Progress/Scope/Next.disabled = not can_cycle
