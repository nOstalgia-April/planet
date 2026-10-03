class_name PrototypeSettings
extends Resource

@export_range(1, 20, 1) var initial_nests: int = 3
@export_range(1, 20, 1) var nest_budget: int = 5
@export_range(1, 20, 1) var active_nest_limit: int = 3
@export var nest_upgrade_costs: PackedInt32Array = PackedInt32Array([20, 60, 180])
@export var spawn_intervals: PackedFloat32Array = PackedFloat32Array([0.5, 0.3, 0.18])
@export_range(0.0, 100.0, 0.1) var passive_income_per_second: float = 3.0
@export_range(1, 100, 1) var slime_reward: int = 2
@export var nest_population_limits: PackedInt32Array = PackedInt32Array([10, 40, 100])
@export var pipe_upgrade_costs: PackedInt32Array = PackedInt32Array([10, 30, 70])
@export var pipe_capture_seconds: PackedFloat32Array = PackedFloat32Array([0.6, 0.45, 0.32, 0.22])
@export_range(1.0, 100.0, 1.0) var pipe_radius: float = 24.0
@export_range(1.0, 200.0, 1.0) var pipe_attraction_radius: float = 70.0
@export var net_upgrade_costs: PackedInt32Array = PackedInt32Array([10, 30, 70])
@export var net_capacities: PackedInt32Array = PackedInt32Array([10, 20, 30, 40])
@export_range(1.0, 200.0, 1.0) var net_radius: float = 84.0
@export_range(0.1, 60.0, 0.1) var net_cooldown_seconds: float = 6.0
