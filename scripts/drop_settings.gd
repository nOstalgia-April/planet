class_name DropSettings
extends Resource

@export_range(0.0, 1200.0, 10.0) var down_gravity: float = 260.0
@export_range(0.0, 4000.0, 25.0) var planet_gravity: float = 1400.0
@export_range(0.0, 600.0, 5.0) var release_down_speed: float = 80.0
@export_range(0.02, 0.5, 0.01) var settle_delay: float = 0.10
@export_range(0.001, 0.03, 0.001) var max_step: float = 1.0 / 120.0
