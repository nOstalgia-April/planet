extends Sprite2D

## Orbit coordinates use the background's 1920 × 1080 reference canvas.
@export var orbit_center: Vector2 = Vector2(972.48, 1846.9088)
@export var start_position: Vector2 = Vector2(270.0, 232.0)
@export_range(1.0, 600.0, 1.0) var orbit_seconds: float = 60.0

var orbit_phase: float = 0.0


func _ready() -> void:
	_update_position()


func _process(delta: float) -> void:
	orbit_phase = fposmod(orbit_phase + delta * TAU / orbit_seconds, TAU)
	_update_position()


func _update_position() -> void:
	position = orbit_center + (start_position - orbit_center).rotated(orbit_phase)
