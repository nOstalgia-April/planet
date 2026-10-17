extends Node2D

@export_range(0.1, 1.0, 0.05) var duration: float = 0.4
@export_range(1.0, 30.0, 0.5) var flash_radius: float = 8.0
@export var preview_color: Color = Color("e00064")

var _tween: Tween

@onready var _beam: Line2D = $Beam
@onready var _source: Polygon2D = $SourceFlash
@onready var _impact: Line2D = $ImpactRing
@onready var _sparks: CPUParticles2D = $Sparks


func _ready() -> void:
	if get_tree().current_scene == self:
		_run_preview.call_deferred()


func play(origin: Vector2, target: Vector2, color: Color) -> void:
	if _tween != null:
		_tween.kill()
	modulate.a = 1.0
	_beam.points = PackedVector2Array([origin, target])
	_beam.default_color = color.lightened(0.25)
	_source.position = origin
	_source.color = color.lightened(0.45)
	_source.scale = Vector2.ONE
	_impact.position = target
	_impact.default_color = color
	_impact.scale = Vector2.ONE * 0.3
	var ring: PackedVector2Array = PackedVector2Array()
	for index: int in range(33):
		ring.append(Vector2.from_angle(TAU * float(index) / 32.0) * flash_radius)
	_impact.points = ring
	_sparks.position = target
	_sparks.color = color.lightened(0.25)
	_sparks.restart()
	_sparks.emitting = true
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_source, "scale", Vector2.ONE * 0.1, duration)
	_tween.tween_property(_impact, "scale", Vector2.ONE * 1.6, duration)
	_tween.tween_property(self, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD)
	_tween.chain().tween_callback(_finish)


func _finish() -> void:
	if get_tree().current_scene == self:
		_tween = create_tween()
		_tween.tween_interval(0.9)
		_tween.tween_callback(_run_preview)
	else:
		queue_free()


func _run_preview() -> void:
	position = get_viewport_rect().size * 0.5
	scale = Vector2.ONE * 3.0
	play(Vector2(-35, -10), Vector2(35, 10), preview_color)
