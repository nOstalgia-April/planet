extends Node2D

signal arrived

@export_range(0.1, 1.0, 0.05) var burst_seconds: float = 0.35
@export_range(0.2, 2.0, 0.05) var return_seconds: float = 0.7
@export_range(20.0, 160.0, 1.0) var scatter_radius: float = 85.0
@export_range(0.3, 2.0, 0.05) var amount_duration: float = 0.85
@export var amount_offset: Vector2 = Vector2(58.0, -16.0)
@export_range(10.0, 100.0, 1.0) var amount_rise: float = 40.0

var _origin: Vector2
var _destination: Vector2
var _offsets: PackedVector2Array = PackedVector2Array()
var _elapsed: float = 0.0
var _playing: bool = false
var _preview: bool = false

@onready var _amount: Label = $Amount


func _ready() -> void:
	_preview = get_tree().current_scene == self
	if _preview:
		var center: Vector2 = get_viewport_rect().size * 0.5
		play(center, center + Vector2(220, -100), 60, 2)


func play(origin: Vector2, destination: Vector2, amount: int, base_value: int) -> void:
	_origin = to_local(origin)
	_destination = to_local(destination)
	_elapsed = 0.0
	_playing = true
	_offsets.clear()
	var count: int = 18 if amount < base_value * 30 else (32 if amount < base_value * 100 else 52)
	for index: int in range(count):
		var angle: float = float(index) * 2.399963
		_offsets.append(
			Vector2.from_angle(angle) * randf_range(scatter_radius * 0.35, scatter_radius)
		)
	_play_amount(amount)


func _play_amount(amount: int) -> void:
	_amount.text = "+%d" % amount
	_amount.reset_size()
	_amount.pivot_offset = _amount.size * 0.5
	_amount.scale = Vector2.ONE * 0.6
	_amount.modulate.a = 1.0
	var screen_origin: Vector2 = get_global_transform_with_canvas() * _origin
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
	_amount.position = (
		get_global_transform_with_canvas().affine_inverse() * center - _amount.pivot_offset
	)
	var float_tween: Tween = create_tween().set_parallel(true)
	float_tween.tween_property(
		_amount, "position:y", _amount.position.y - amount_rise, amount_duration
	)
	float_tween.tween_property(_amount, "modulate:a", 0.0, amount_duration * 0.5).set_delay(
		amount_duration * 0.5
	)
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


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	queue_redraw()
	if _elapsed >= maxf(burst_seconds + return_seconds + 0.22, amount_duration):
		_playing = false
		arrived.emit()
		if _preview:
			play(to_global(_origin), to_global(_destination), 60, 2)
		else:
			queue_free()


func _draw() -> void:
	if not _playing:
		return
	for index: int in range(_offsets.size()):
		var offset: Vector2 = _offsets[index]
		var burst: float = clampf(_elapsed / burst_seconds, 0.0, 1.0)
		var point: Vector2 = _origin + offset * (1.0 - pow(1.0 - burst, 3.0))
		var flight: float = clampf(
			(_elapsed - burst_seconds - float(index % 5) * 0.045) / return_seconds, 0.0, 1.0
		)
		point = point.lerp(_destination, flight * flight)
		var color: Color = [Color("ffce62"), Color("ffa6c6"), Color("a9e3ec")][index % 3]
		color.a = 1.0 - pow(flight, 8.0)
		draw_circle(point, lerpf(4.5, 2.0, flight), color)
