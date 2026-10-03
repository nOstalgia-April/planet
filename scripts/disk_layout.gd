class_name DiskDemoLayout
extends Control

const DESIGN_SIZE: Vector2 = Vector2(1280.0, 800.0)

var _shop_layout_queued: bool = false

@onready var _tool_card: Control = $ToolCard
@onready var _nest_card: Control = $NestCard
@onready var _restart: Button = %RestartButton
@onready var _completion: Control = %Completion


func _ready() -> void:
	_tool_card.minimum_size_changed.connect(_queue_shop_layout)
	_nest_card.minimum_size_changed.connect(_queue_shop_layout)


func apply_layout(viewport_size: Vector2) -> Rect2:
	var interface_scale: float = minf(
		viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y
	)
	scale = Vector2.ONE * interface_scale
	position = Vector2.ZERO
	size = viewport_size / interface_scale
	_place_shops()
	_place($Goal, Rect2(size.x - 655.0, 40.0, 220.0, 55.0))
	_place($StatusLabel, Rect2(48.0, size.y - 97.0, size.x - 481.0, 30.0))
	_place($InputHint, Rect2(48.0, size.y - 56.0, size.x - 456.0, 30.0))
	_place(_restart, Rect2(size.x - 207.0, size.y - 70.0, 167.0, 48.0))
	return Rect2(
		Vector2(48.0, 112.0) * interface_scale,
		Vector2(size.x - 456.0, size.y - 208.0) * interface_scale
	)


func is_over_ui(viewport_position: Vector2) -> bool:
	if _completion.visible:
		return true
	for panel: Control in [_tool_card, _nest_card, _restart]:
		if panel.get_global_rect().has_point(viewport_position):
			return true
	return false


func _queue_shop_layout() -> void:
	# Wrapped text can briefly enlarge a card before its width is settled.
	if _shop_layout_queued:
		return
	_shop_layout_queued = true
	_settle_shop_layout.call_deferred()


func _settle_shop_layout() -> void:
	_shop_layout_queued = false
	_place_shops()


func _place_shops() -> void:
	var card_left: float = size.x - 360.0
	_place(_tool_card, Rect2(card_left, 136.0, 320.0, 278.0))
	_place(_nest_card, Rect2(card_left, 438.0, 320.0, size.y - 527.0))


func _place(control: Control, rectangle: Rect2) -> void:
	if not control.position.is_equal_approx(rectangle.position):
		control.position = rectangle.position
	if not control.size.is_equal_approx(rectangle.size):
		control.size = rectangle.size
