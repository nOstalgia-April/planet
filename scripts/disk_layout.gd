class_name DiskDemoLayout
extends Control

signal interaction_panel_changed
signal quick_upgrade_requested(tool: int)
signal technology_upgrade_requested(id: String)
signal nest_technology_upgrade_requested(nest_id: int, id: String)

const DESIGN_SIZE: Vector2 = Vector2(1280.0, 800.0)
const BRANCH_IDS: PackedStringArray = ["pipe", "net", "governance", "combo"]
const PageScript = preload("res://scripts/ui/technology_page.gd")

var selected_technology_nest_id: int = 1
var _shop_layout_queued: bool = false
var _quick_layout_queued: bool = false
var _nest_anchor: Rect2 = Rect2()
var _run: PrototypeRun
var _hovered_tool: int = -1
var _hover_close_remaining: float = 0.0

@onready var _nest_card: Control = $NestCard
@onready var _technology: PageScript = %Technology
@onready var _technology_button: Button = %TechnologyButton
@onready var _tool_dock: Control = $ToolDock
@onready var _quick_tools: HBoxContainer = $ToolDock/Content/QuickTools
@onready var _restart: Button = %RestartButton
@onready var _completion: Control = %Completion
@onready var _quick_buttons: Array[Button] = [%QuickPipeButton, %QuickNetButton]
@onready var _upgrade_panels: Array[PanelContainer] = [$PipeUpgrade, $NetUpgrade]
@onready var _combo_label: Label = %ComboLabel
@onready var _combo_timer: ProgressBar = %ComboTimerBar
@onready var _net_timer_label: Label = %QuickNetButton.get_node("Visual/Text/Detail")


func _ready() -> void:
	_technology.hide()
	_nest_card.hide()
	_technology_button.pressed.connect(_show_technology)
	_technology.close_requested.connect(close_panels)
	_technology.technology_upgrade_requested.connect(technology_upgrade_requested.emit)
	_technology.nest_technology_upgrade_requested.connect(nest_technology_upgrade_requested.emit)
	_technology.nest_selected.connect(_set_technology_nest)
	%CloseNestButton.pressed.connect(close_panels)
	_nest_card.minimum_size_changed.connect(_queue_shop_layout)
	for index: int in range(2):
		_upgrade_panels[index].minimum_size_changed.connect(_queue_quick_layout)
		_quick_buttons[index].mouse_entered.connect(_show_quick_upgrade.bind(index))
		_quick_buttons[index].focus_entered.connect(_show_quick_upgrade.bind(index))
		var purchase: Button = _upgrade_panels[index].get_node("Content/Purchase") as Button
		purchase.pressed.connect(_request_quick_upgrade.bind(index))


func _process(delta: float) -> void:
	_update_quick_hover(delta, get_viewport().get_mouse_position())


func _update_quick_hover(delta: float, pointer: Vector2) -> void:
	if _hovered_tool < 0:
		return
	if is_technology_open() or _completion.is_visible_in_tree():
		_hide_quick_upgrades()
		return
	if _quick_hover_rect().has_point(pointer):
		_hover_close_remaining = 0.16
	else:
		_hover_close_remaining -= delta
		if _hover_close_remaining <= 0.0:
			_hide_quick_upgrades()


func apply_layout(viewport_size: Vector2) -> Rect2:
	var interface_scale: float = minf(
		viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y
	)
	scale = Vector2.ONE * interface_scale
	position = Vector2.ZERO
	size = viewport_size / interface_scale
	_place($EconomyCard, Rect2(28.0, 24.0, 334.0, 99.0))
	_place($GameName, Rect2(50.0, 38.0, 290.0, 24.0))
	_place($Economy, Rect2(49.0, 69.0, 290.0, 38.0))
	_place($ComboChip, Rect2(29.0, 134.0, 246.0, 58.0))
	_place($GoalCard, Rect2(size.x - 365.0, 24.0, 337.0, 108.0))
	_place($Goal, Rect2(size.x - 343.0, 40.0, 293.0, 74.0))
	_place($StatusLabel, Rect2(270.0, size.y - 160.0, size.x - 540.0, 30.0))
	_place($InputHint, Rect2(size.x * 0.5 - 335.0, size.y - 114.0, 670.0, 22.0))
	_place(_tool_dock, Rect2(size.x * 0.5 - 299.0, size.y - 91.0, 598.0, 86.0))
	_place(_restart, Rect2(size.x - 150.0, size.y - 66.0, 122.0, 42.0))
	_place_shops()
	_place_quick_upgrades.call_deferred()
	return Rect2(
		Vector2(48.0, 72.0) * interface_scale,
		Vector2(size.x - 96.0, size.y - 144.0) * interface_scale
	)


func refresh_progression(run: PrototypeRun) -> void:
	_run = run
	_technology.refresh(run, selected_technology_nest_id)
	var active_count: int = 0
	var partial_count: int = 0
	var managed_count: int = 0
	for nest: NestState in run.nests:
		if nest.is_tamed:
			managed_count += 1
		elif nest.level == 2:
			partial_count += 1
		else:
			active_count += 1
	%GovernanceLabel.text = (
		"活跃 %d  ·  半治理 %d  ·  已治理 %d" % [active_count, partial_count, managed_count]
	)
	var combo_hint: String = (
		"连续吸入 %d 只后，每只额外获得糖果；每次吸入刷新 %.0f 秒。捕网和自动采集不刷新。"
		% [run.settings.combo_target, run.get_combo_window_seconds()]
	)
	$ComboChip.tooltip_text = combo_hint
	for index: int in range(2):
		_refresh_quick_tool(index)
	refresh_timers(run)
	_queue_shop_layout()


func refresh_timers(run: PrototypeRun) -> void:
	$ComboChip.visible = run.combo_level > 0
	if run.combo_count >= run.settings.combo_target and run.combo_remaining > 0.0:
		_combo_label.text = "连击 +%d · %.1f 秒" % [run.combo_level, run.combo_remaining]
	elif run.combo_remaining > 0.0:
		_combo_label.text = (
			"连吸 %d / %d · %.1f 秒"
			% [run.combo_count, run.settings.combo_target, run.combo_remaining]
		)
	else:
		_combo_label.text = "连吸 0 / %d" % run.settings.combo_target
	_combo_timer.max_value = run.get_combo_window_seconds()
	_combo_timer.value = run.combo_remaining
	if not run.net_unlocked:
		_net_timer_label.text = "尚未解锁"
	elif run.net_cooldown_remaining > 0.0:
		_net_timer_label.text = "冷却 %.1f 秒" % run.net_cooldown_remaining
	else:
		_net_timer_label.text = "就绪 · %d 只" % run.get_net_capacity()


func _refresh_quick_tool(index: int) -> void:
	var id: String = BRANCH_IDS[index]
	var button: Button = _quick_buttons[index]
	var text_root: VBoxContainer = button.get_node("Visual/Text") as VBoxContainer
	var detail: Label = text_root.get_node("Detail") as Label
	detail.text = (
		"%s 秒 / 只" % String.num(_run.get_pipe_capture_seconds(), 3)
		if index == 0
		else "容量 %d 只" % _run.get_net_capacity()
	)
	if index == 1 and not _run.net_unlocked:
		detail.text = "尚未解锁"
	var ink: Color = Color("fbf7e9") if button.button_pressed else Color("31594e")
	for label: Label in text_root.get_children():
		label.add_theme_color_override("font_color", ink)
	(button.get_node("Visual/Shortcut") as Label).add_theme_color_override("font_color", ink)
	button.get_node("Visual/Icon").ink = ink
	button.get_node("Visual/Icon").queue_redraw()
	var popup: PanelContainer = _upgrade_panels[index]
	var level: int = _run.get_technology_level(id)
	(popup.get_node("Content/Title") as Label).text = (
		"%s · Lv.%d" % ["吸取管" if index == 0 else "捕网", level + 1]
	)
	if index == 1 and not _run.net_unlocked:
		(popup.get_node("Content/Title") as Label).text = "解锁捕网"
	(popup.get_node("Content/Effect") as Label).text = _run.get_technology_description(id)
	var purchase: Button = popup.get_node("Content/Purchase") as Button
	var cost: int = _run.get_technology_cost(id)
	var requirement: String = _run.get_technology_requirement(id)
	purchase.disabled = cost < 0 or _run.candy < cost or not requirement.is_empty()
	purchase.text = "已升至最高级" if cost < 0 else "升级 · %d 糖果" % cost
	if index == 1 and not _run.net_unlocked:
		purchase.text = "解锁 · %d 糖果" % cost
	purchase.tooltip_text = ""
	if cost >= 0 and _run.candy < cost:
		purchase.tooltip_text = "还需 %d 糖果" % (cost - _run.candy)
	if not requirement.is_empty():
		purchase.text = requirement
		purchase.tooltip_text = requirement


func _request_quick_upgrade(tool: int) -> void:
	quick_upgrade_requested.emit(tool)
	_hover_close_remaining = 0.16


func _set_technology_nest(nest_id: int) -> void:
	selected_technology_nest_id = nest_id


func _show_quick_upgrade(tool: int) -> void:
	if is_technology_open() or _completion.is_visible_in_tree():
		return
	_hovered_tool = tool
	_hover_close_remaining = 0.16
	for index: int in range(2):
		_upgrade_panels[index].visible = index == tool
	_place_quick_upgrades()


func _hide_quick_upgrades() -> void:
	_hovered_tool = -1
	for panel: PanelContainer in _upgrade_panels:
		panel.hide()


func _quick_hover_rect() -> Rect2:
	if _hovered_tool < 0:
		return Rect2()
	var button_rect: Rect2 = _quick_buttons[_hovered_tool].get_global_rect()
	var popup_rect: Rect2 = _upgrade_panels[_hovered_tool].get_global_rect()
	return button_rect.merge(popup_rect).grow(5.0)


func _place_quick_upgrades() -> void:
	for index: int in range(2):
		var button_rect: Rect2 = (
			get_global_transform_with_canvas().affine_inverse()
			* _quick_buttons[index].get_global_rect()
		)
		_place(
			_upgrade_panels[index],
			Rect2(button_rect.get_center().x - 145.0, button_rect.position.y - 157.0, 290.0, 146.0)
		)
		# Wrapped labels settle after the panel acquires its final width.
		_upgrade_panels[index].position.y = (
			button_rect.position.y - _upgrade_panels[index].size.y - 11.0
		)


func _queue_quick_layout() -> void:
	if _quick_layout_queued:
		return
	_quick_layout_queued = true
	_settle_quick_layout.call_deferred()


func _settle_quick_layout() -> void:
	_quick_layout_queued = false
	_place_quick_upgrades()


func is_over_ui(viewport_position: Vector2) -> bool:
	if _completion.is_visible_in_tree() or is_technology_open():
		return true
	if _hovered_tool >= 0 and _quick_hover_rect().has_point(viewport_position):
		return true
	var blocking_controls: Array[Control] = [
		_nest_card, _tool_dock, _restart, $EconomyCard, $GoalCard, $ComboChip
	]
	for panel: Control in blocking_controls:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(viewport_position):
			return true
	return false


func get_overview_obstacles() -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	var controls: Array[Control] = [$EconomyCard, $GoalCard, $ComboChip, _tool_dock, _restart]
	for panel: Control in controls:
		if panel.is_visible_in_tree():
			rectangles.append(panel.get_global_rect())
	for panel: PanelContainer in _upgrade_panels:
		if panel.is_visible_in_tree():
			rectangles.append(panel.get_global_rect())
	return rectangles


func show_nest_details(anchor: Rect2) -> void:
	_nest_anchor = anchor
	_nest_card.show()
	_place_shops()


func hide_nest_details() -> void:
	_nest_card.hide()


func is_over_nest_details(viewport_position: Vector2) -> bool:
	return (
		_nest_card.is_visible_in_tree()
		and _nest_card.get_global_rect().has_point(viewport_position)
	)


func close_panels() -> void:
	_technology.hide()
	_nest_card.hide()
	_hide_quick_upgrades()
	interaction_panel_changed.emit()


func is_technology_open() -> bool:
	return _technology.is_visible_in_tree()


func _show_technology() -> void:
	_nest_card.hide()
	_hide_quick_upgrades()
	_technology.show()
	_place_shops()
	interaction_panel_changed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
		return
	if is_technology_open() or _nest_card.is_visible_in_tree():
		close_panels()
		get_viewport().set_input_as_handled()


func _queue_shop_layout() -> void:
	if _shop_layout_queued:
		return
	_shop_layout_queued = true
	_settle_shop_layout.call_deferred()


func _settle_shop_layout() -> void:
	_shop_layout_queued = false
	_place_shops()


func _place_shops() -> void:
	if not _nest_anchor.has_area():
		_place(_nest_card, Rect2(size.x - 368.0, size.y * 0.5 - 150.0, 320.0, 300.0))
		return
	var local_anchor: Rect2 = get_global_transform_with_canvas().affine_inverse() * _nest_anchor
	var card_size: Vector2 = Vector2(320.0, 300.0)
	var card_position: Vector2 = Vector2(
		local_anchor.end.x - 4.0, local_anchor.get_center().y - card_size.y * 0.5
	)
	if card_position.x + card_size.x > size.x - 16.0:
		card_position.x = local_anchor.position.x - card_size.x + 4.0
	card_position = card_position.clamp(Vector2.ONE * 16.0, size - card_size - Vector2.ONE * 16.0)
	_place(_nest_card, Rect2(card_position.round(), card_size))


func _place(control: Control, rectangle: Rect2) -> void:
	if not control.position.is_equal_approx(rectangle.position):
		control.position = rectangle.position
	if not control.size.is_equal_approx(rectangle.size):
		control.size = rectangle.size
