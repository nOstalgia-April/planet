class_name CollectionEffect
extends Node2D

@export_range(0.1, 1.5, 0.01) var duration: float = 0.48
@export var color: Color = Color("d7e8bb")
@export_range(0.4, 2.0, 0.05) var size: float = 1.0

var _destination: Vector2 = Vector2.ZERO
var _curve_control: Vector2 = Vector2.ZERO
var _tween: Tween
var _preview_mode: bool = false

@onready var _candy: Polygon2D = $Candy
@onready var _trail: Line2D = $Trail
@onready var _amount_label: Label = $AmountLabel


func _ready() -> void:
	_preview_mode = get_tree().current_scene == self
	if _preview_mode:
		_run_preview.call_deferred()


func play(origin: Vector2, destination: Vector2, amount: int) -> void:
	if _tween != null:
		_tween.kill()
	global_position = origin
	_destination = to_local(destination)
	_curve_control = _destination * 0.5 + Vector2(0.0, -maxf(28.0, _destination.length() * 0.22))
	_candy.color = color
	_candy.position = Vector2.ZERO
	_candy.scale = Vector2.ONE * size
	_candy.modulate.a = 1.0
	_trail.default_color = Color(color, 0.60)
	_trail.modulate.a = 1.0
	_amount_label.text = "+%d" % amount
	_amount_label.position = Vector2(-26.0, -44.0)
	_amount_label.modulate.a = 1.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(_set_flight, 0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_IN
	)
	(
		_tween
		. tween_property(_amount_label, "position:y", -65.0, duration + 0.16)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	_tween.tween_property(_amount_label, "modulate:a", 0.0, duration * 0.55).set_delay(
		duration * 0.65
	)
	_tween.tween_property(_trail, "modulate:a", 0.0, duration * 0.40).set_delay(duration * 0.75)
	_tween.tween_property(_candy, "modulate:a", 0.0, duration * 0.18).set_delay(duration * 0.88)
	_tween.chain().tween_callback(_finish)


func _set_flight(progress: float) -> void:
	_candy.position = _flight_point(progress)
	_candy.rotation = progress * 3.0
	_candy.scale = Vector2.ONE * size * lerpf(1.0, 0.48, progress)
	var trail_points: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(7):
		var sample_progress: float = maxf(0.0, progress - (1.0 - float(point_index) / 6.0) * 0.22)
		trail_points.append(_flight_point(sample_progress))
	_trail.points = trail_points


func _flight_point(progress: float) -> Vector2:
	return Vector2.ZERO.bezier_interpolate(_curve_control, _curve_control, _destination, progress)


func _finish() -> void:
	if _preview_mode:
		_tween = create_tween()
		_tween.tween_interval(0.75)
		_tween.tween_callback(_run_preview)
	else:
		queue_free()


func _run_preview() -> void:
	var viewport_center: Vector2 = get_viewport_rect().size / 2.0
	play(viewport_center + Vector2(-110.0, 35.0), viewport_center + Vector2(110.0, -65.0), 2)
