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
const EndingCredits = preload("res://scripts/ui/ending_credits.gd")
const VIEW_ZOOM_OUT: Texture2D = preload("res://assets/ui/game_menu/view_switch.tres")
const VIEW_ZOOM_IN: Texture2D = preload("res://assets/ui/game_menu/zoom_in.tres")

var dock_intro_progress: float = 1.0:
	set(value):
		dock_intro_progress = clampf(value, 0.0, 1.2)
		if is_node_ready():
			_place_tool_dock()

var _manual_pause: bool = false
var _presentation_paused: bool = false

var _shop_layout_queued: bool = false
var _nest_anchor: PackedVector2Array = PackedVector2Array()
var _nest_hover_polygon: PackedVector2Array = PackedVector2Array()
var _run: PrototypeRun

@onready var _nest_card: Control = $NestCard
@onready var _technology: PageScript = %Technology
@onready var _tool_dock: DockScript = $ToolDock
@onready var _technology_button: Button = $ToolDock/Technology
@onready var _technology_badge: TextureRect = $ToolDock/Technology/Badge
@onready var game_menu: GameMenu = $GameMenu
@onready var _completion: EndingCredits = %Completion
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
	_tool_dock.upgrade_requested.connect(quick_upgrade_requested.emit)
	_view_switch.pressed.connect(view_switch_requested.emit)
	_completion.visibility_changed.connect(_sync_completion_presentation)
	_sync_completion_presentation()


func _sync_completion_presentation() -> void:
	var ending: bool = _completion.is_visible_in_tree()
	$Economy.visible = not ending
	$StatusLabel.visible = not ending
	_tool_dock.visible = not ending
	game_menu.visible = not ending and not is_technology_open()
	if ending:
		_nest_card.hide()
		_tool_dock.suppress(true)
		_view_shortcut.hide()


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
	_place_tool_dock()
	_place_shops()
	return Rect2(
		Vector2(48.0, 72.0) * interface_scale,
		Vector2(size.x - 96.0, size.y - 144.0) * interface_scale
	)


func get_tool_clearance_rect() -> Rect2:
	return _tool_dock.get_global_rect().grow(32.0 * scale.x)


func _place_tool_dock() -> void:
	var dock_y: float = size.y - 82.0 + (1.0 - dock_intro_progress) * 130.0
	_place(_tool_dock, Rect2(size.x * 0.5 - 300.0, dock_y, 600.0, 76.0))


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
	if _nest_card.is_visible_in_tree():
		var local_pointer: Vector2 = (
			_nest_card.get_global_transform_with_canvas().affine_inverse() * viewport_position
		)
		if Rect2(Vector2.ZERO, _nest_card.size).has_point(local_pointer):
			return true
	var blocking_controls: Array[Control] = [$Economy, _view_shortcut]
	for panel: Control in blocking_controls:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(viewport_position):
			return true
	return false


func show_nest_details(anchor: PackedVector2Array) -> void:
	_nest_anchor = anchor
	_nest_card.visible = %NestButton.visible
	_place_shops()


func hide_nest_details() -> void:
	_nest_card.hide()


func is_over_nest_details(viewport_position: Vector2) -> bool:
	if not _nest_card.is_visible_in_tree():
		return false
	return Geometry2D.is_point_in_polygon(viewport_position, _nest_hover_polygon)


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
	if _completion.is_visible_in_tree():
		_completion.skip_credits()
	elif game_menu.is_open():
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


func set_presentation_paused(paused: bool) -> void:
	if _presentation_paused == paused:
		return
	_presentation_paused = paused
	_sync_pause()


func _sync_pause() -> void:
	var paused: bool = (
		_manual_pause or _presentation_paused or is_technology_open() or game_menu.is_open()
	)
	get_tree().paused = paused
	game_menu.visible = not is_technology_open() and not _completion.is_visible_in_tree()
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
	# A deferred layout can be flushed while the world releases rendering resources.
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_place_shops()


func _place_shops() -> void:
	if _nest_anchor.is_empty():
		return
	var to_local: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var local_anchor: PackedVector2Array = to_local * _nest_anchor
	var tangent: Vector2 = (local_anchor[1] - local_anchor[0]).normalized()
	var outward: Vector2 = Vector2(tangent.y, -tangent.x)
	var card_size: Vector2 = %NestButton.size
	var top_center: Vector2 = (local_anchor[0] + local_anchor[1]) * 0.5
	_nest_card.rotation = tangent.angle()
	_place(
		_nest_card,
		Rect2(top_center + outward * (card_size.y + 2.0) - tangent * card_size.x * 0.5, card_size)
	)
	# Convex hull joins the whole nest to the button, including diagonal pointer paths.
	var points: PackedVector2Array = _nest_anchor.duplicate()
	var button_transform: Transform2D = _nest_card.get_global_transform_with_canvas()
	var padded: Rect2 = Rect2(Vector2.ZERO, card_size).grow(10.0)
	var button_corners: PackedVector2Array = PackedVector2Array(
		[
			padded.position,
			Vector2(padded.end.x, padded.position.y),
			padded.end,
			Vector2(padded.position.x, padded.end.y),
		]
	)
	points.append_array(button_transform * button_corners)
	_nest_hover_polygon = Geometry2D.convex_hull(points)


func _place(control: Control, rectangle: Rect2) -> void:
	if not control.position.is_equal_approx(rectangle.position):
		control.position = rectangle.position
	if not control.size.is_equal_approx(rectangle.size):
		control.size = rectangle.size
