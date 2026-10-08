class_name PrototypeSettings
extends Resource

@export_range(1, 20, 1) var initial_nests: int = 2
@export var unlocked_species_weights: PackedFloat32Array = PackedFloat32Array([2.0, 1.0])
@export_range(0.1, 60.0, 0.1) var nest_roll_interval: float = 5.0
@export_range(0.0, 1.0, 0.01) var nest_roll_chance_min: float = 0.05
@export_range(0.0, 1.0, 0.01) var nest_roll_chance_max: float = 0.35
@export_range(0.0, 240.0, 1.0) var nest_min_distance: float = 64.0
@export_range(1, 128, 1) var nest_site_samples: int = 48
@export_range(1.0, 480.0, 1.0) var same_species_soft_distance: float = 180.0
@export_range(0.01, 1.0, 0.01) var same_species_near_weight: float = 0.45
@export var nest_upgrade_costs: PackedInt32Array = PackedInt32Array([16, 32, 64])
@export var spawn_intervals: PackedFloat32Array = PackedFloat32Array([4.0, 5.0, 6.0])
@export_range(0.01, 1.0, 0.01) var spawn_burst_ratio_min: float = 0.2
@export_range(0.01, 1.0, 0.01) var spawn_burst_ratio_max: float = 0.3
@export_range(0.0, 100.0, 0.1) var passive_income_per_second: float = 3.0
@export_range(1, 100, 1) var slime_reward: int = 2
@export var nest_population_limits: PackedInt32Array = PackedInt32Array([10, 30, 60])
@export var pipe_upgrade_costs: PackedInt32Array = PackedInt32Array([10, 30, 70, 120, 180, 260])
@export var pipe_capture_seconds: PackedFloat32Array = PackedFloat32Array(
	[0.6, 0.45, 0.32, 0.22, 0.17, 0.135, 0.11]
)
@export_range(1.0, 100.0, 1.0) var pipe_radius: float = 24.0
@export var net_upgrade_costs: PackedInt32Array = PackedInt32Array([10, 30, 70])
@export_range(1, 1000, 1) var net_unlock_cost: int = 10
@export var net_capacities: PackedInt32Array = PackedInt32Array([5, 10, 20, 30])
@export_range(1.0, 200.0, 1.0) var net_radius: float = 84.0
@export_range(0.1, 60.0, 0.1) var net_cooldown_seconds: float = 6.0
@export_group("Research")
@export var governance_upgrade_costs: PackedInt32Array = PackedInt32Array([20, 100])
@export var combo_upgrade_costs: PackedInt32Array = PackedInt32Array([15, 40, 80])
@export var combo_interval_upgrade_costs: PackedInt32Array = PackedInt32Array([15, 40, 80])
@export
var combo_interval_bonus_seconds: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 2.0, 3.0])
@export var valuable_upgrade_costs: PackedInt32Array = PackedInt32Array([65])
@export_range(1, 20, 1) var combo_target: int = 5
@export_range(0.1, 30.0, 0.1) var combo_window_seconds: float = 3.0
@export_group("Living regions")
@export var automatic_capture_intervals: PackedFloat32Array = PackedFloat32Array([0, 0, 1.15, 0.5])
@export_range(2, 50, 1) var valuable_spawn_every: int = 8
@export_range(2, 10, 1) var valuable_reward_multiplier: int = 3
@export_range(1.0, 5.0, 0.05) var mucus_slow_multiplier: float = 1.65
@export_range(1.0, 4.0, 0.1) var mucus_nest_coverage_multiplier: float = 2.0
@export_group("Ground mucus trail")
@export_range(2.0, 16.0, 0.5) var mucus_trail_half_width: float = 7.0
@export_range(1.0, 20.0, 0.5) var mucus_trail_lifetime: float = 7.0
@export_range(1.0, 8.0, 0.5) var mucus_trail_sample_spacing: float = 2.5
# Retained-history budget; every active emitter keeps its own continuous ribbon.
@export_range(1, 160, 1) var mucus_trail_limit: int = 80
@export_range(20.0, 140.0, 1.0) var mucus_trail_max_length: float = 72.0
