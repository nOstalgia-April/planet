class_name PrototypeSettings
extends Resource

@export_range(1, 20, 1) var initial_nests: int = 2
# Weighted random discovery; minimum counts reserve the last available sites.
@export var unlocked_species_weights: PackedFloat32Array = PackedFloat32Array([2.0, 1.0])
@export var nest_minimum_counts: PackedInt32Array = PackedInt32Array([4, 2, 1])
@export_group("Drill treasure")
@export_range(0, 20, 1) var drill_nest_limit: int = 4
@export_range(0.0, 5.0, 0.1) var drill_discovery_weight: float = 0.5
@export var drill_population_limits: PackedInt32Array = PackedInt32Array([1, 2, 4])
@export_range(2.0, 60.0, 0.5) var drill_spawn_interval: float = 8.0
@export var drill_reward_weights: PackedInt32Array = PackedInt32Array([70, 25, 5])
@export var drill_reward_multipliers: PackedInt32Array = PackedInt32Array([10, 30, 100])
@export_group("Nests")
@export_range(0.1, 60.0, 0.1) var nest_roll_interval: float = 5.0
@export_range(0.0, 1.0, 0.01) var nest_roll_chance_min: float = 0.25
@export_range(0.0, 1.0, 0.01) var nest_roll_chance_max: float = 0.55
@export_range(0.0, 300.0, 0.1) var nest_spawn_cooldown_seconds: float = 20.0
@export_range(0.0, 600.0, 0.1) var nest_initial_delay_seconds: float = 60.0
@export_range(0.0, 240.0, 1.0) var nest_min_distance: float = 64.0
@export_range(0.0, 120.0, 1.0) var nest_spacing_margin: float = 20.0
@export_range(1.0, 480.0, 1.0) var same_species_soft_distance: float = 180.0
@export_range(0.01, 1.0, 0.01) var same_species_near_weight: float = 0.45
@export var nest_upgrade_costs: PackedInt32Array = PackedInt32Array([50, 600, 2500])
@export var spawn_intervals: PackedFloat32Array = PackedFloat32Array([4.0, 5.0, 6.0])
@export_range(0.0, 60.0, 0.1) var spawn_interval_jitter: float = 1.0
@export_range(0.01, 1.0, 0.01) var spawn_burst_ratio_min: float = 0.2
@export_range(0.01, 1.0, 0.01) var spawn_burst_ratio_max: float = 0.3
@export_range(0.0, 100.0, 0.1) var passive_income_per_second: float = 1.5
@export_range(0.1, 60.0, 0.1) var automatic_income_interval: float = 3.0
@export_range(1, 100, 1) var slime_reward: int = 1
@export var base_value_multipliers: PackedInt32Array = PackedInt32Array([1, 2, 5, 10])
@export var base_value_upgrade_costs: PackedInt32Array = PackedInt32Array([40, 180, 900])
@export var nest_population_limits: PackedInt32Array = PackedInt32Array([10, 30, 60])
@export
var pipe_upgrade_costs: PackedInt32Array = PackedInt32Array([10, 20, 50, 300, 800, 1600, 3000])
@export var pipe_capture_seconds: PackedFloat32Array = PackedFloat32Array(
	[0.6, 0.4, 0.3, 0.22, 0.15, 0.12, 0.1, 0.08]
)
@export_range(1.0, 100.0, 0.1) var pipe_radius: float = 9.6
@export var net_upgrade_costs: PackedInt32Array = PackedInt32Array([50, 300, 1200])
@export_range(1, 1000, 1) var net_unlock_cost: int = 15
@export var net_capacities: PackedInt32Array = PackedInt32Array([5, 10, 20, 30])
@export_range(1.0, 200.0, 0.1) var net_radius: float = 33.6
@export var net_size_upgrade_costs: PackedInt32Array = PackedInt32Array([1500, 3000, 5000])
@export var net_size_multipliers: PackedFloat32Array = PackedFloat32Array([1.0, 1.25, 1.5, 1.75])
@export_range(0.1, 60.0, 0.1) var net_cooldown_seconds: float = 6.0
@export_group("Research")
@export var governance_upgrade_costs: PackedInt32Array = PackedInt32Array([50, 4500])
@export var combo_upgrade_costs: PackedInt32Array = PackedInt32Array([20, 150, 800, 1800])
@export var combo_reward_percentages: PackedInt32Array = PackedInt32Array([25, 50, 75, 100])
@export var combo_stage_targets: PackedInt32Array = PackedInt32Array([3, 5, 7, 10])
@export var valuable_upgrade_costs: PackedInt32Array = PackedInt32Array([120])
@export_range(1, 10000, 1) var giant_unlock_cost: int = 120
@export_range(0.1, 30.0, 0.1) var combo_window_seconds: float = 5.0
@export_group("Living regions")
@export_range(2, 50, 1) var valuable_spawn_every: int = 8
@export_range(2, 10, 1) var valuable_reward_multiplier: int = 3
@export_group("Giant fusion")
@export_range(2, 200, 1) var giant_fusion_threshold: int = 36
@export_range(0.1, 10.0, 0.1) var giant_check_interval: float = 1.0
@export_range(0.25, 2.0, 0.05) var giant_activity_radius_multiplier: float = 1.0
@export_group("Living regions")
@export_range(1.0, 4.0, 0.1) var mucus_nest_coverage_multiplier: float = 2.0
@export_group("Ground mucus trail")
@export_range(1.0, 16.0, 0.1) var mucus_trail_half_width: float = 2.8
@export_range(1.0, 20.0, 0.5) var mucus_trail_lifetime: float = 7.0
@export_range(0.5, 8.0, 0.1) var mucus_trail_sample_spacing: float = 1.0
# Retained-history budget; every active emitter keeps its own continuous ribbon.
@export_range(1, 160, 1) var mucus_trail_limit: int = 80
@export_range(8.0, 140.0, 0.1) var mucus_trail_max_length: float = 28.8
