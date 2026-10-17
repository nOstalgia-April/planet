extends Control

signal upgrade_requested(tool: int)
# A tool's upgrade became affordable and its quick-upgrade tab came up on its
# own (0 = vacuum, 1 = net). Once per offer: hovers and the tab returning
# after menus or view switches do not repeat it.
signal upgrade_offered(tool: int)

const Selection = preload("res://scripts/ui/dock_selection.gd")
const Cooldown = preload("res://scripts/ui/dock_cooldown.gd")
const TECHNOLOGY_NOTICE: Shader = preload("res://shaders/technology_notice.gdshader")

enum ToolState { HIDDEN, LOCKED_READY, LOCKED_SHORT, READY, SHORT, MAXED }

@export var reveal_seconds: float = 0.18
@export var hover_grace_seconds: float = 0.16
@export_range(0.01, 1.0, 0.01) var hover_fade_seconds: float = 0.12
@export_range(0.01, 1.0, 0.01) var view_fade_out_seconds: float = 0.14
@export_range(0.01, 1.0, 0.01) var view_fade_in_seconds: float = 0.20
@export var unlock_color: Color = Color("c86b22")

var states: Array[int] = [ToolState.SHORT, ToolState.HIDDEN]
var net_discovered: bool = false
var _run: PrototypeRun
var _accent: Color = Color("881e35")
var _hovered: Array[bool] = [false, false]
var _hover_remaining: Array[float] = [0.0, 0.0]
var _expanded: Array[bool] = [false, false]
# Whether the current affordable upgrade has been offered; cleared once it is
# bought or no longer affordable.
var _offered: Array[bool] = [false, false]
var _tweens: Array[Tween] = [null, null]
var _text_tweens: Array[Tween] = [null, null]
var _two_lines: Array[bool] = [false, false]
var _suppressed: bool = false
var _near_view: bool = true
var _pointer_position: Vector2 = Vector2.ZERO
var _view_transitioning: bool = false
var _view_fade: Tween

@onready var pipe_button: Button = $Pipe/Button
@onready var net_button: Button = $Net/Button
@onready var technology_button: Button = $Technology
@onready var badge: TextureRect = $Technology/Badge
@onready var buttons: Array[Button] = [pipe_button, net_button]
@onready var upgrades: Array[Button] = [$Pipe/Reveal/Purchase, $Net/Reveal/Purchase]
@onready var shortcuts: Array[Button] = [$Pipe/Shortcut, $Net/Shortcut]
@onready var net_cooldown: Cooldown = $Net/Button/Cooldown
@onready var surfaces: Array[Button] = [
	pipe_button, net_button, technology_button, upgrades[0], upgrades[1], shortcuts[0], shortcuts[1]
]


func _ready() -> void:
	var notice_material: ShaderMaterial = ShaderMaterial.new()
	notice_material.shader = TECHNOLOGY_NOTICE
	badge.material = notice_material
	badge.pivot_offset = badge.size * 0.5
	_pointer_position = get_viewport().get_mouse_position()
	for button: Button in surfaces:
		for style: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		var backing: TextureRect = button.get_node("Backing") as TextureRect
		backing.material = backing.material.duplicate()
	for index: int in range(2):
		shortcuts[index].pressed.connect(_select_shortcut.bind(index))
		upgrades[index].pressed.connect(_purchase.bind(index))
		buttons[index].mouse_entered.connect(show_upgrade.bind(index))
		buttons[index].focus_entered.connect(show_upgrade.bind(index))
	reset_notifications()


func reset_notifications() -> void:
	net_cooldown.reset()
	if _view_fade != null:
		_view_fade.kill()
	_view_transitioning = false
	modulate.a = 1.0
	for button: Button in surfaces:
		button.mouse_filter = Control.MOUSE_FILTER_STOP
	net_discovered = false
	for index: int in range(2):
		_hovered[index] = false
		_hover_remaining[index] = 0.0
		_expanded[index] = false
		if _tweens[index] != null:
			_tweens[index].kill()
		upgrades[index].position.y = (upgrades[index].get_parent() as Control).size.y
		upgrades[index].hide()
	$Net.hide()


func refresh(run: PrototypeRun) -> void:
	_run = run
	for index: int in range(2):
		_refresh_tool(index)
	refresh_timers(run)
	_refresh_visibility()


func set_technology_notification(available: bool, final_goal_available: bool) -> void:
	badge.visible = available
	badge.scale = Vector2.ONE * (1.65 if final_goal_available else 1.0)
	(badge.material as ShaderMaterial).set_shader_parameter("emphasized", final_goal_available)


func _refresh_tool(index: int) -> void:
	var locked: bool = index == 1 and not _run.net_unlocked
	var id: String = "pipe" if index == 0 else _run.get_net_quick_upgrade_id()
	var cost: int = _run.get_technology_cost(id)
	var allowed: bool = _run.get_technology_requirement(id).is_empty()
	var affordable: bool = allowed and cost >= 0 and _run.candy >= cost
	if index == 1:
		net_discovered = net_discovered or affordable or _run.net_unlocked
	if index == 1 and not net_discovered:
		states[index] = ToolState.HIDDEN
	elif locked:
		states[index] = ToolState.LOCKED_READY if affordable else ToolState.LOCKED_SHORT
	elif cost < 0:
		states[index] = ToolState.MAXED
	else:
		states[index] = ToolState.READY if affordable else ToolState.SHORT
	var button: Button = buttons[index]
	shortcuts[index].disabled = locked
	shortcuts[index].modulate.a = 0.45 if locked else 1.0
	(shortcuts[index].get_node("Backing").material as ShaderMaterial).set_shader_parameter(
		"selected", 1.0 if button.button_pressed and not locked else 0.0
	)
	var backing: TextureRect = button.get_node("Backing") as TextureRect
	var icon: TextureRect = button.get_node("Icon") as TextureRect
	backing.modulate = Color("8b8b8b") if locked else Color.WHITE
	icon.modulate = Color("8b8b8b") if locked else Color.WHITE
	(button.get_node("Selected") as Selection).set_selected(button.button_pressed and not locked)
	var status: Label = button.get_node("Status") as Label
	var show_net_size: bool = index == 1 and _run.net_unlocked and _run.net_size_level > 0
	status.add_theme_color_override("font_color", Color.WHITE)
	status.modulate = Color("ffbb79") if locked and affordable else Color("d8d8d8")
	if show_net_size:
		status.text = "大小 %d 级" % (_run.net_size_level + 1)
	else:
		status.text = "可解锁" if locked else "可升级"
	status.visible = affordable or show_net_size
	_set_text_layout(index, status.visible)
	button.tooltip_text = ""
	var purchase: Button = upgrades[index]
	purchase.disabled = not affordable
	purchase.tooltip_text = ""
	var upgrade_name: String = {
		"pipe": "吸取速率", "net_unlock": "解锁捕网", "net_capacity": "捕网扩容", "net_size": "捕网大小"
	}[id]
	(purchase.get_node("Caption/Level") as Label).text = upgrade_name + " ·"
	(purchase.get_node("Caption/Cost") as Label).text = str(maxi(0, cost))
	(purchase.get_node("Caption") as Control).modulate = (
		Color.WHITE if affordable else Color("d7a18f")
	)
	_update_accent(index)


func _set_text_layout(index: int, two_lines: bool) -> void:
	if _two_lines[index] == two_lines:
		return
	_two_lines[index] = two_lines
	if _text_tweens[index] != null:
		_text_tweens[index].kill()
	var detail: Label = buttons[index].get_node("Detail") as Label
	_text_tweens[index] = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_text_tweens[index].tween_property(
		detail, "position:y", 19.0 if two_lines else 28.0, reveal_seconds
	)


func refresh_timers(run: PrototypeRun) -> void:
	net_cooldown.sync(
		run.net_cooldown_remaining, run.settings.net_cooldown_seconds, run.net_unlocked
	)
	(pipe_button.get_node("Detail") as Label).text = "%d 级" % (run.pipe_level + 1)
	var detail: Label = net_button.get_node("Detail") as Label
	if not run.net_unlocked:
		detail.text = "未解锁"
	else:
		detail.text = "%d 级" % (run.net_level + 1)


func set_accent(color: Color) -> void:
	_accent = color
	for index: int in range(2):
		_update_accent(index)


func _update_accent(index: int) -> void:
	var backing_material: ShaderMaterial = (
		upgrades[index].get_node("Backing").material as ShaderMaterial
	)
	var locked: bool = states[index] in [ToolState.LOCKED_READY, ToolState.LOCKED_SHORT]
	var color: Color = unlock_color if locked else _accent
	backing_material.set_shader_parameter("accent", color)
	(upgrades[index].get_node("Caption") as Control).modulate = (
		Color.from_hsv(color.h, 0.24, 0.85) if upgrades[index].disabled else Color.WHITE
	)
	for label_name: String in ["Level", "Cost"]:
		var label: Label = upgrades[index].get_node("Caption/" + label_name) as Label
		label.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.04, 0.9))
		label.add_theme_constant_override("outline_size", 0 if upgrades[index].disabled else 2)
	(buttons[index].get_node("Selected") as Selection).self_modulate = Color.from_hsv(
		_accent.h, 0.58, 1.0
	)
	(shortcuts[index].get_node("Backing").material as ShaderMaterial).set_shader_parameter(
		"accent", Color.from_hsv(_accent.h, 0.58, 1.0)
	)
	if index == 1:
		net_cooldown.set_accent(Color.from_hsv(_accent.h, 0.4, 1.0))


func _select_shortcut(index: int) -> void:
	if not _suppressed and not _view_transitioning and _near_view:
		buttons[index].pressed.emit()


func _purchase(index: int) -> void:
	upgrade_requested.emit(index)


func show_upgrade(index: int) -> void:
	if not buttons[index].is_visible_in_tree() or _suppressed or _view_transitioning:
		return
	_hovered[index] = true
	_hover_remaining[index] = hover_grace_seconds
	_refresh_visibility()


func set_view_state(near_view: bool, transitioning: bool) -> void:
	if not transitioning:
		set_near_view(near_view)
	if _view_transitioning == transitioning:
		return
	_view_transitioning = transitioning
	if _view_fade != null:
		_view_fade.kill()
	for button: Button in surfaces:
		button.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE if transitioning else Control.MOUSE_FILTER_STOP
		)
	_hovered.fill(false)
	_refresh_visibility()
	_view_fade = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_view_fade.tween_property(
		self,
		"modulate:a",
		0.0 if transitioning else 1.0,
		view_fade_out_seconds if transitioning else view_fade_in_seconds
	)


func set_near_view(value: bool) -> void:
	_near_view = value
	if not value:
		_hovered.fill(false)
	_refresh_visibility()


func suppress(value: bool) -> void:
	if _suppressed == value:
		return
	_suppressed = value
	if value:
		for button: Button in surfaces:
			(button.get_node("Backing").material as ShaderMaterial).set_shader_parameter(
				"hover_amount", 0.0
			)
		for index: int in range(2):
			_hovered[index] = false
			_expanded[index] = false
			if _tweens[index] != null:
				_tweens[index].kill()
			upgrades[index].hide()
			upgrades[index].position.y = (upgrades[index].get_parent() as Control).size.y
	_refresh_visibility()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer_position = (event as InputEventMouse).position


func _process(delta: float) -> void:
	update_hover(delta, _pointer_position)
	_update_surface_hover(delta)


func _update_surface_hover(delta: float) -> void:
	for button: Button in surfaces:
		var hovered: bool = (
			not _suppressed
			and not _view_transitioning
			and not button.disabled
			and button.is_visible_in_tree()
			and button.get_global_rect().has_point(_pointer_position)
		)
		var backing_material: ShaderMaterial = button.get_node("Backing").material as ShaderMaterial
		var current: float = backing_material.get_shader_parameter("hover_amount")
		var target: float = 1.0 if hovered else 0.0
		if not is_equal_approx(current, target):
			backing_material.set_shader_parameter(
				"hover_amount", move_toward(current, target, delta / hover_fade_seconds)
			)


func update_hover(delta: float, pointer: Vector2) -> void:
	for index: int in range(2):
		if _suppressed or _view_transitioning or not buttons[index].is_visible_in_tree():
			_hovered[index] = false
			continue
		var area: Rect2 = buttons[index].get_global_rect()
		area = area.merge(shortcuts[index].get_global_rect())
		if _expanded[index]:
			area = area.merge((upgrades[index].get_parent() as Control).get_global_rect())
		if area.grow(3.0).has_point(pointer):
			_hovered[index] = true
			_hover_remaining[index] = hover_grace_seconds
		elif _hovered[index]:
			_hover_remaining[index] -= delta
			if _hover_remaining[index] <= 0.0:
				_hovered[index] = false
	_refresh_visibility()


func _refresh_visibility() -> void:
	$Pipe.visible = _near_view
	$Net.visible = _near_view and net_discovered
	for index: int in range(2):
		var available: bool = states[index] in [ToolState.READY, ToolState.LOCKED_READY]
		var has_next: bool = not states[index] in [ToolState.HIDDEN, ToolState.MAXED]
		if not available:
			_offered[index] = false
		_set_expanded(
			index,
			(
				_near_view
				and not _suppressed
				and not _view_transitioning
				and has_next
				and (available or _hovered[index])
			)
		)
		if available and _expanded[index] and not _offered[index] and is_visible_in_tree():
			_offered[index] = true
			upgrade_offered.emit(index)


func _set_expanded(index: int, expanded: bool) -> void:
	if _expanded[index] == expanded:
		return
	_expanded[index] = expanded
	var purchase: Button = upgrades[index]
	if _tweens[index] != null:
		_tweens[index].kill()
	purchase.show()
	purchase.mouse_filter = Control.MOUSE_FILTER_STOP if expanded else Control.MOUSE_FILTER_IGNORE
	_tweens[index] = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var target_y: float = 0.0 if expanded else (purchase.get_parent() as Control).size.y
	_tweens[index].tween_property(purchase, "position:y", target_y, reveal_seconds)
	if not expanded:
		_tweens[index].tween_callback(purchase.hide)


func contains_pointer(pointer: Vector2) -> bool:
	if _view_transitioning or not is_visible_in_tree():
		return false
	if technology_button.get_global_rect().has_point(pointer):
		return true
	for index: int in range(2):
		if (
			buttons[index].is_visible_in_tree()
			and (
				buttons[index].get_global_rect().has_point(pointer)
				or shortcuts[index].get_global_rect().has_point(pointer)
			)
		):
			return true
		if (
			_expanded[index]
			and (upgrades[index].get_parent() as Control).get_global_rect().has_point(pointer)
		):
			return true
	return false
