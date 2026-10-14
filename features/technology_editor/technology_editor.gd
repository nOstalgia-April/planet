extends Control

const PageScript = preload("res://features/github_tech_tree_preview/github_technology_page.gd")
const GROUPS: PackedStringArray = [
	"基础价值", "吸取速率", "巢穴培育", "完全治理", "高价值个体", "巨型史莱姆", "连击爬梯", "捕网", "捕网大小"
]
const TECHNOLOGY_IDS: PackedStringArray = [
	"base_value",
	"pipe",
	"cultivation",
	"automation",
	"valuable",
	"giant",
	"combo_unlock",
	"net_unlock",
	"net_size"
]

@export_file("*.tres") var settings_path: String = "res://resources/prototype_settings.tres"

var settings: PrototypeSettings
var _changed: Dictionary[String, bool] = {}
var _group: int = 0

@onready var run: PrototypeRun = $Run
@onready var page: PageScript = %TechnologyPage
@onready var _tabs: TabContainer = %Tabs
@onready var _fields: VBoxContainer = %Fields
@onready var _status: Label = %Status
@onready var _preview_canvas: Control = %PreviewCanvas
@onready var _save: Button = %Save


func _ready() -> void:
	for title: String in GROUPS:
		%Groups.add_item(title)
	%Groups.select(0)
	%Groups.item_selected.connect(_show_group)
	_save.pressed.connect(save_settings)
	%Reload.pressed.connect(reload_settings)
	%ResetProgress.pressed.connect(reset_preview)
	%AddCandy.pressed.connect(_add_candy)
	_tabs.tab_changed.connect(_tab_changed)
	page.close_requested.connect(func() -> void: _tabs.current_tab = 0)
	page.technology_upgrade_requested.connect(_purchase)
	_preview_canvas.resized.connect(_layout_preview)
	reload_settings()
	_layout_preview.call_deferred()


func reload_settings() -> void:
	var source: PrototypeSettings = (
		ResourceLoader.load(settings_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		as PrototypeSettings
	)
	if source == null:
		_status.text = "读取失败，请检查配置文件：" + settings_path
		_save.disabled = true
		return
	settings = source.duplicate(true) as PrototypeSettings
	_changed.clear()
	_save.disabled = true
	run.settings = settings
	reset_preview()
	_show_group(_group)
	_status.text = "已读取已保存配置。修改后可先试买，再保存到游戏。"


func _show_group(index: int) -> void:
	_group = index
	for child: Node in _fields.get_children():
		_fields.remove_child(child)
		child.queue_free()
	%Heading.text = GROUPS[index]
	%FieldScroll.scroll_vertical = 0
	match index:
		0:
			_scalar("slime_reward", "初始史莱姆价值（糖果）", 1)
			_values("base_value_upgrade_costs", "研究费用（糖果）", 0, 1, 2)
			_values("base_value_multipliers", "价值倍率（初始固定 ×1）", 1, 1, 1, true)
		1:
			_values("pipe_upgrade_costs", "研究费用（糖果）", 0, 1, 2)
			_values("pipe_capture_seconds", "每只吸取时间（秒）", 0.001, 0.001)
			_scalar("pipe_radius", "吸取半径", 0.1, 0.1)
		2:
			_element("governance_upgrade_costs", 0, "培育研究费用（糖果）", 0)
			_values("nest_upgrade_costs", "各巢穴建设费用（糖果）", 0, 1, 0)
			_values("nest_population_limits", "巢穴人口上限", 1, 1, 0)
			_note("建设费用依次为培育、强化培育、完全治理；人口依次为野生、培育、强化培育。")
		3:
			_element("governance_upgrade_costs", 1, "自动化研究费用（糖果）", 0)
			_element("nest_upgrade_costs", 2, "每巢自动化建设费用（糖果）", 0)
			_scalar("passive_income_per_second", "每巢基础产糖（糖果／秒）", 0, 0.1)
			_scalar("automatic_income_interval", "产糖结算间隔（秒）", 0.1, 0.1)
			_note("实际产糖速度还会乘以当前基础价值倍率。")
		4:
			_values("valuable_upgrade_costs", "研究费用（糖果）", 0)
			_scalar("valuable_spawn_every", "每出生多少只出现一只金色个体", 2)
			_scalar("valuable_reward_multiplier", "金色个体价值倍率", 2)
		5:
			_scalar("giant_unlock_cost", "研究费用（糖果）", 0)
			_scalar("giant_fusion_threshold", "每次融合个体数", 2)
			_scalar("giant_check_interval", "融合检查间隔（秒）", 0.1, 0.1)
			_scalar("giant_activity_radius_multiplier", "融合范围倍率", 0.05, 0.05)
		6:
			_values("combo_upgrade_costs", "各段解锁费用（糖果）", 0)
			_values("combo_reward_percentages", "各段额外糖果（%）", 0)
			_values("combo_stage_targets", "各段吸入目标（只）", 1)
			_scalar("combo_window_seconds", "每段限时（秒）", 0.1, 0.1)
			_note("每段独立计数，达标按该段全部糖果结算；巨型计 1 只。")
		7:
			_scalar("net_unlock_cost", "捕网解锁费用（糖果）", 0)
			_values("net_upgrade_costs", "扩容费用（糖果）", 0, 1, 2)
			_values("net_capacities", "一次捕获数量", 1)
			_scalar("net_cooldown_seconds", "冷却时间（秒）", 0.1, 0.1)
			_scalar("net_radius", "捕网半径", 0.1, 0.1)
		8:
			_values("net_size_upgrade_costs", "大小升级费用（糖果）", 0, 1, 2)
			_values("net_size_multipliers", "半径倍率（初始固定 ×1）", 1, 0.05, 1, true)
			_note("捕网扩容满级后开放；实际半径 = 基础捕网半径 × 当前倍率。")


func _scalar(property: String, title: String, minimum: float, step: float = 1.0) -> void:
	_element(property, -1, title, minimum, step)


func _values(
	property: String,
	title: String,
	minimum: float,
	step: float = 1.0,
	first_level: int = 1,
	lock_first: bool = false
) -> void:
	_note(title)
	var values: Variant = settings.get(property)
	for index: int in range(values.size()):
		var label: String = "第 %d 项" % (index + 1)
		if first_level > 0:
			label = "%d 级" % (index + first_level)
		_element(property, index, label, minimum, step, lock_first and index == 0)


func _note(message: String) -> void:
	var label: Label = Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("93bccb"))
	_fields.add_child(label)


func _element(
	property: String,
	index: int,
	title: String,
	minimum: float,
	step: float = 1.0,
	locked: bool = false
) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_fields.add_child(row)
	var label: Label = Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var input: SpinBox = SpinBox.new()
	input.name = property + ("_%d" % index if index >= 0 else "")
	input.custom_minimum_size.x = 180
	input.min_value = minimum
	input.max_value = 1000000
	input.allow_greater = true
	input.step = step
	var stored: Variant = settings.get(property)
	input.value = float(stored[index]) if index >= 0 else float(stored)
	input.editable = not locked
	input.tooltip_text = "初始基准固定" if locked else "输入数值后按 Enter 或点击其他位置确认"
	row.add_child(input)
	input.value_changed.connect(_change_value.bind(property, index))


func _change_value(value: float, property: String, index: int) -> void:
	var stored: Variant = settings.get(property)
	if index >= 0:
		stored[index] = int(value) if typeof(stored) == TYPE_PACKED_INT32_ARRAY else value
		settings.set(property, stored)
	else:
		settings.set(property, int(value) if typeof(stored) == TYPE_INT else value)
	_changed[property] = true
	_save.disabled = false
	_status.text = "尚未保存 · %d 项参数已修改 · 科技树试买已使用新数值" % _changed.size()
	page.refresh(run)


func save_settings() -> Error:
	if _changed.is_empty():
		return OK
	# Merge edited fields into the latest file so other tuning work is retained.
	var latest: PrototypeSettings = (
		ResourceLoader.load(settings_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		as PrototypeSettings
	)
	if latest == null:
		return _save_failed(ERR_CANT_OPEN)
	var backup_path: String = (
		"user://%s.before_technology_save.tres" % settings_path.get_file().get_basename()
	)
	var result: Error = ResourceSaver.save(latest, backup_path)
	if result != OK:
		return _save_failed(result)
	for property: String in _changed:
		latest.set(property, settings.get(property))
	var temporary_path: String = settings_path.get_basename() + ".technology_pending.tres"
	result = ResourceSaver.save(latest, temporary_path)
	if result != OK:
		return _save_failed(result)
	result = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(settings_path)
	)
	if result != OK:
		return _save_failed(result)
	# Refresh the shared resource for a new game in this same application session.
	ResourceLoader.load(settings_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	_changed.clear()
	_save.disabled = true
	_status.text = "已保存到游戏配置。新开一局生效；保存前的配置已备份。"
	return OK


func _save_failed(result: Error) -> Error:
	_status.text = "保存失败（%s），修改仍保留，请重试。" % error_string(result)
	return result


func reset_preview() -> void:
	run.start_run([Vector2(-200, -180), Vector2(200, -180)])
	run.candy = 10000
	page.refresh(run)


func _add_candy() -> void:
	run.candy += 10000
	page.refresh(run)


func _purchase(id: String) -> void:
	run.purchase_technology(id)
	page.refresh(run)


func _tab_changed(index: int) -> void:
	if index == 1:
		page.select_node(TECHNOLOGY_IDS[_group])
		_layout_preview.call_deferred()


func _layout_preview() -> void:
	var factor: float = minf(_preview_canvas.size.x / 1280.0, _preview_canvas.size.y / 800.0)
	page.scale = Vector2.ONE * maxf(factor, 0.1)
	page.size = _preview_canvas.size / page.scale
