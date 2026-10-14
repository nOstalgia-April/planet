extends Node2D

const CandyScene: PackedScene = preload("res://scenes/effects/collection_effect.tscn")

@export_range(0.3, 2.0, 0.05) var duration: float = 0.85
@export_range(20.0, 200.0, 1.0) var spread: float = 72.0

@onready var _ring: Line2D = $Ring
@onready var _crown: Line2D = $Crown
@onready var _amount: Label = $Amount


func _ready() -> void:
	if get_tree().current_scene == self:
		position = get_viewport_rect().size * 0.5
		play.call_deferred(4, 25)


func play(stage: int, bonus: int) -> void:
	var strength: float = 0.7 + stage * 0.2
	_amount.text = "+%d" % bonus
	_amount.visible = bonus > 0
	_amount.scale = Vector2.ONE * strength
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
	tween.tween_property(_amount, "position:y", -135.0, duration)
	tween.tween_property(_amount, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	tween.chain().tween_interval(0.25)
	tween.chain().tween_callback(queue_free)
