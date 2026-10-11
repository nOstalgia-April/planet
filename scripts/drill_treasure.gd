extends Node2D

signal arrived

@export_range(0.1, 1.0, 0.05) var burst_seconds: float = 0.35
@export_range(0.2, 2.0, 0.05) var return_seconds: float = 0.7
@export_range(20.0, 160.0, 1.0) var scatter_radius: float = 85.0

var _origin: Vector2
var _destination: Vector2
var _offsets: PackedVector2Array = PackedVector2Array()
var _elapsed: float = 0.0
var _playing: bool = false
var _preview: bool = false


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


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	queue_redraw()
	if _elapsed >= burst_seconds + return_seconds + 0.22:
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
