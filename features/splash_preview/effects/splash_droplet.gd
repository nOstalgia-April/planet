extends Node2D

@export_range(-180.0, 180.0, 1.0) var direction_degrees: float = -45.0
@export_range(0.0, 0.3, 0.01) var launch_delay: float = 0.08
@export_range(0.2, 1.2, 0.01) var travel_distance: float = 0.68
@export_range(0.01, 0.12, 0.001) var drop_size: float = 0.035
@export_range(-1.0, 1.0, 0.01) var curve: float = 0.2

@onready var _shape: Polygon2D = $Shape


func _ready() -> void:
	var outline: PackedVector2Array = PackedVector2Array()
	for index in range(32):
		var angle: float = TAU * float(index) / 32.0
		var round_head: float = cos(angle)
		outline.append(
			Vector2(
				0.5 * round_head - 0.08 * (1.0 - round_head),
				0.5 * sin(angle) * (0.9 + 0.1 * round_head)
			)
		)
	_shape.polygon = outline
	_shape.antialiased = true


func show_pose(progress: float, size: float, strength: float, color: Color) -> void:
	var travel: float = clampf((progress - launch_delay) / 0.55, 0.0, 1.0)
	var direction: Vector2 = Vector2.from_angle(deg_to_rad(direction_degrees))
	var perpendicular: Vector2 = direction.orthogonal()
	var eased_travel: float = 1.0 - pow(1.0 - travel, 2.4)
	var radius: float = size * (0.24 + travel_distance * eased_travel * strength)
	position = direction * radius + perpendicular * size * curve * sin(travel * PI)
	rotation = direction.angle() + curve * (0.5 - travel)
	var fade: float = smoothstep(0.0, 0.055, travel) * (1.0 - smoothstep(0.55, 1.0, travel))
	var stretch: float = 1.0 + (1.0 - travel) * minf(strength, 1.0)
	var width: float = 1.0 - (1.0 - travel) * 0.08
	scale = Vector2(stretch, width) * size * drop_size
	_shape.color = Color(color, color.a * fade)
	visible = fade > 0.001 and strength > 0.0
