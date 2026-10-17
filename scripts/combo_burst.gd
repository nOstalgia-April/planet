extends Node2D

const CandyScene: PackedScene = preload("res://scenes/effects/collection_effect.tscn")

@export_range(0.3, 2.0, 0.05) var duration: float = 0.85
@export_range(20.0, 200.0, 1.0) var spread: float = 72.0
@export_range(20, 60, 1) var amount_font_size: int = 32
@export_range(1, 20, 1) var stage_font_growth: int = 10
@export var amount_offset: Vector2 = Vector2(58.0, -16.0)
@export_range(10.0, 100.0, 1.0) var amount_rise: float = 40.0

@onready var _ring: Line2D = $Ring
@onready var _crown: Line2D = $Crown
@onready var _amount: Label = $Amount


func _ready() -> void:
	if get_tree().current_scene == self:
		position = get_viewport_rect().size * 0.5
		play.call_deferred(4, 25)


static func capture_accent(colors: PackedColorArray) -> Color:
	if colors.is_empty():
		return Color("ff85bb")
	# Each captured monster contributes once, matching the combo strip's weights.
	var mixed: Color = Color(0.0, 0.0, 0.0, 0.0)
	for color: Color in colors:
		mixed += color
	mixed /= float(colors.size())
	return Color.from_hsv(mixed.h, maxf(mixed.s, 0.55), maxf(mixed.v, 0.95))


func play(stage: int, bonus: int, accent: Color = Color("ff85bb")) -> void:
	var strength: float = 0.7 + stage * 0.2
	_amount.text = "+%d" % bonus
	_amount.label_settings = _amount.label_settings.duplicate() as LabelSettings
	_amount.label_settings.font_size = amount_font_size + (stage - 1) * stage_font_growth
	_amount.label_settings.font_color = accent
	_amount.reset_size()
	_amount.pivot_offset = _amount.size * 0.5
	_place_amount()
	_amount.scale = Vector2.ONE * 0.6
	_crown.visible = stage == 4
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(49):
		points.append(Vector2.from_angle(TAU * index / 48.0) * 22.0)
	_ring.points = points
	var count: int = 4 + stage * 3
	for index: int in range(count):
		var candy: CollectionEffect = CandyScene.instantiate() as CollectionEffect
		candy.color = Color.from_hsv(float(index) / count, 0.48, 1.0)
		candy.size = strength * 0.7
		candy.duration = duration
		candy.flight_ease = Tween.EASE_OUT
		$Candies.add_child(candy)
		var direction: Vector2 = Vector2.from_angle(TAU * index / count)
		candy.play(global_position, global_position + direction * spread * strength, 0)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_ring, "scale", Vector2.ONE * strength * 3.0, duration)
	tween.tween_property(_ring, "modulate:a", 0.0, duration)
	tween.tween_property(_crown, "scale", Vector2.ONE * 1.5, duration)
	tween.tween_property(_crown, "modulate:a", 0.0, duration)
	tween.tween_property(_amount, "position:y", _amount.position.y - amount_rise, duration)
	tween.tween_property(_amount, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	var pop: Tween = create_tween()
	(
		pop
		. tween_property(_amount, "scale", Vector2.ONE * 1.18, 0.14)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	pop.tween_property(_amount, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tween.chain().tween_interval(0.25)
	tween.chain().tween_callback(queue_free)


func _place_amount() -> void:
	var screen_origin: Vector2 = get_global_transform_with_canvas().origin
	var half_size: Vector2 = _amount.size * 0.7
	var viewport_size: Vector2 = get_viewport_rect().size
	var side_distance: float = amount_offset.x + half_size.x
	var center: Vector2 = screen_origin + Vector2(side_distance, amount_offset.y)
	if center.x + half_size.x > viewport_size.x - 12.0:
		center.x = screen_origin.x - side_distance
	center = center.clamp(
		half_size + Vector2(12.0, amount_rise + 12.0),
		viewport_size - half_size - Vector2.ONE * 12.0
	)
	_amount.position = center - screen_origin - _amount.pivot_offset
