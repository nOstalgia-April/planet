class_name DiskDemoLayout
extends Control

signal restart_requested
signal interaction_panel_changed
signal quick_upgrade_requested(tool: int)
signal technology_upgrade_requested(id: String)
signal view_switch_requested

const DESIGN_SIZE: Vector2 = Vector2(1280.0, 800.0)
const BRANCH_IDS: PackedStringArray = ["pipe", "net", "governance", "combo"]
const PageScript = preload("res://scripts/ui/technology_page.gd")
const DockScript = preload("res://scripts/ui/bottom_dock.gd")
const GameMenu = preload("res://scripts/ui/game_menu.gd")
const VIEW_ZOOM_OUT: Texture2D = preload("res://assets/ui/game_menu/view_switch.tres")
const VIEW_ZOOM_IN: Texture2D = preload("res://assets/ui/game_menu/zoom_in.tres")

var _manual_pause: bool = false

var _shop_layout_queued: bool = false
var _nest_anchor: Rect2 = Rect2()
var _run: PrototypeRun

@onready var _nest_card: Control = $NestCard
@onready var _technology: PageScript = %Technology
@onready var _tool_dock: DockScript = $ToolDock
@onready var _technology_button: Button = $ToolDock/Technology
@onready var _technology_badge: TextureRect = $ToolDock/Technology/Badge
@onready var game_menu: GameMenu = $GameMenu
@onready var _completion: Control = %Completion
@onready var _view_shortcut: Control = $ViewShortcut
@onready var _view_switch: TextureButton = $ViewShortcut/Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_technology.hide()
	_nest_card.hide()
	_tool_dock.suppress(true)
	game_menu.pause_toggled.connect(_toggle_pause)
	game_menu.settings_changed.connect(_sync_pause)
	game_menu.restart_requested.connect(restart_requested.emit)
	game_menu.menu_requested.connect(_return_to_menu)
	_technology_button.pressed.connect(_show_technology)
	_technology.close_requested.connect(close_panels)
	_technology.technology_upgrade_requested.connect(technology_upgrade_requested.emit)
	%CloseNestButton.pressed.connect(close_panels)
	_nest_card.minimum_size_changed.connect(_queue_shop_layout)
	_tool_dock.upgrade_requested.connect(quick_upgrade_requested.emit)
	_view_switch.pressed.connect(view_switch_requested.emit)


func _process(_delta: float) -> void:
	_view_shortcut.visible = not is_view_switch_blocked()
	_tool_dock.suppress(
		get_tree().paused or is_technology_open() or _completion.is_visible_in_tree()
	)


func _show_quick_upgrade(tool: int) -> void:
	_tool_dock.show_upgrade(tool)


func set_near_view(value: bool, transitioning: bool = false) -> void:
	_tool_dock.set_view_state(value, transitioning)
	_view_switch.texture_normal = VIEW_ZOOM_OUT if value else VIEW_ZOOM_IN
	_view_switch.tooltip_text = "切换至%s · Tab" % ("远景" if value else "近景")


func is_view_switch_blocked() -> bool:
	return get_tree().paused or is_technology_open() or _completion.is_visible_in_tree()


func set_view_switch_enabled(value: bool) -> void:
	_view_switch.disabled = not value
	_view_shortcut.modulate.a = 1.0 if value else 0.4


func apply_layout(viewport_size: Vector2) -> Rect2:
	var interface_scale: float = minf(
		viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y
	)
	scale = Vector2.ONE * interface_scale
	position = Vector2.ZERO
	size = viewport_size / interface_scale
	_place($Economy, Rect2(28.0, 24.0, 210.0, 34.0))
	_place(_view_shortcut, Rect2(24.0, size.y * 0.5 - 44.0, 64.0, 88.0))
	_place($StatusLabel, Rect2(270.0, size.y - 160.0, size.x - 540.0, 30.0))
	_place(_tool_dock, Rect2(size.x * 0.5 - 300.0, size.y - 82.0, 600.0, 76.0))
	_place_shops()
	return Rect2(
		Vector2(48.0, 72.0) * interface_scale,
		Vector2(size.x - 96.0, size.y - 144.0) * interface_scale
	)


func get_tool_clearance_rect() -> Rect2:
	return _tool_dock.get_global_rect().grow(32.0 * scale.x)


func refresh_progression(run: PrototypeRun) -> void:
	_run = run
	_technology.refresh(run)
	_technology_badge.visible = _technology.has_unlocked_candidate()
	_tool_dock.refresh(run)
	refresh_timers(run)
	_queue_shop_layout()


func refresh_timers(run: PrototypeRun) -> void:
	_tool_dock.refresh_timers(run)


func is_over_ui(viewport_position: Vector2) -> bool:
	if (
		game_menu.contains_pointer(viewport_position)
		or _completion.is_visible_in_tree()
		or is_technology_open()
	):
		return true
	if _tool_dock.contains_pointer(viewport_position):
		return true
	var blocking_controls: Array[Control] = [_nest_card, $Economy, _view_shortcut]
	for panel: Control in blocking_controls:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(viewport_position):
			return true
	return false


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
	_tool_dock.suppress(true)
	_sync_pause()


func is_technology_open() -> bool:
	return _technology.is_visible_in_tree()


func _show_technology() -> void:
	_nest_card.hide()
	_tool_dock.suppress(true)
	_technology.show()
	_place_shops()
	_sync_pause()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
		return
	if game_menu.is_open():
		game_menu.handle_escape()
	elif is_technology_open() or _nest_card.is_visible_in_tree():
		close_panels()
	else:
		_toggle_pause()
	get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	_manual_pause = not _manual_pause
	_sync_pause()


func reset_pause() -> void:
	_tool_dock.reset_notifications()
	_manual_pause = false
	game_menu.set_open(false)
	_sync_pause()


func _sync_pause() -> void:
	var paused: bool = _manual_pause or is_technology_open() or game_menu.is_open()
	get_tree().paused = paused
	game_menu.visible = not is_technology_open()
	game_menu.set_paused(paused)
	if paused:
		_nest_card.hide()
		_tool_dock.suppress(true)
	interaction_panel_changed.emit()


func _return_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred("res://scenes/主菜单/主菜单.tscn")


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
