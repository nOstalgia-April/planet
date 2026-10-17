class_name PrototypeRun
extends Node

signal economy_changed
signal base_value_changed
signal net_cooldown_changed
signal nest_added(nest: NestState)
signal nest_changed(nest: NestState)
signal nest_spawn_requested(species: NestState.Species)
signal slime_requested(nest_id: int)
signal automatic_income_received(nest_id: int, amount: int)
signal combo_stage_completed(stage: int, bonus: int)
signal combo_progressed(capture_color: Color)
signal combo_interrupted
signal goal_completed
signal progress_committed

const SaveFields = preload("res://scripts/save_fields.gd")
const SAVE_FIELDS: PackedStringArray = [
	"candy",
	"base_value_level",
	"pipe_level",
	"net_level",
	"net_size_level",
	"net_unlocked",
	"governance_level",
	"valuable_level",
	"giant_unlocked",
	"combo_level",
	"combo_stage",
	"combo_stage_candy",
	"combo_count",
	"combo_remaining",
	"net_cooldown_remaining",
	"generated_nests",
	"completed_nests",
	"unlocked_colors",
	"is_complete",
	"generation_stage",
	"_nest_roll_clock",
	"_combo_reward_remainder",
	"_nest_spawn_cooldown_remaining",
	"_nest_initial_delay_remaining",
	"_pending_nest_species",
	"_nest_site_capacity",
]
const NEST_SAVE_FIELDS: PackedStringArray = [
	"nest_id",
	"species",
	"level",
	"position",
	"alive_slimes",
	"spawn_clock",
	"spawn_interval_offset",
	"income_remainder",
	"income_clock",
	"is_tamed",
	"is_discovering",
]

@export var settings: PrototypeSettings

var candy: int = 0
var base_value_level: int = 0
var pipe_level: int = 0
var net_level: int = 0
var net_size_level: int = 0
var net_unlocked: bool = false
var governance_level: int = 0
var valuable_level: int = 0
var giant_unlocked: bool = false
var combo_level: int = 0
var combo_stage: int = 0
var combo_stage_candy: int = 0
var combo_count: int = 0
var combo_remaining: float = 0.0
var net_cooldown_remaining: float = 0.0
var nests: Array[NestState] = []
var generated_nests: int = 0
var completed_nests: int = 0
var unlocked_colors: Array[int] = []
var is_complete: bool = false
var generation_stage: int = 0

var _nest_roll_clock: float = 0.0
# Earned fractional combo candy survives a broken streak; only a new run clears it.
var _combo_reward_remainder: int = 0
var _nest_spawn_cooldown_remaining: float = 0.0
var _nest_initial_delay_remaining: float = 0.0
var _pending_nest_species: int = -1
# Zero is an unbounded layout; finite layouts provide their site count at startup.
var _nest_site_capacity: int = 0
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


func start_run(spawn_positions: Array[Vector2], site_capacity: int = 0) -> void:
	assert(settings != null, "PrototypeRun requires a PrototypeSettings resource.")
	assert(settings.initial_nests == 2, "The opening needs two basic slime nests.")
	assert(spawn_positions.size() >= settings.initial_nests, "The opening needs two nest sites.")
	assert(settings.unlocked_species_weights.size() == 2)
	assert(settings.nest_minimum_counts.size() == 3)
	assert(site_capacity == 0 or site_capacity >= settings.initial_nests)
	var minimum_total: int = 0
	for species: int in range(3):
		assert(settings.nest_minimum_counts[species] >= 0)
		var minimum: int = settings.nest_minimum_counts[species]
		if species == NestState.Species.DRILL:
			minimum = mini(minimum, settings.drill_nest_limit)
			if settings.drill_discovery_weight <= 0.0:
				minimum = 0
		elif species == NestState.Species.SLIME:
			minimum = maxi(minimum, settings.initial_nests)
		minimum_total += minimum
	assert(site_capacity == 0 or minimum_total <= site_capacity, "Nest minima must fit the map.")
	_nest_site_capacity = site_capacity
	assert(settings.drill_population_limits.size() == 3)
	assert(settings.drill_discovery_weight >= 0.0)
	assert(settings.drill_spawn_interval > settings.spawn_interval_jitter)
	assert(
		settings.drill_reward_weights.size() == 3 and settings.drill_reward_multipliers.size() == 3
	)
	var treasure_weight: int = 0
	for weight: int in settings.drill_reward_weights:
		assert(weight >= 0)
		treasure_weight += weight
	assert(treasure_weight > 0)
	assert(settings.nest_roll_interval > 0.0)
	assert(settings.nest_spawn_cooldown_seconds >= 0.0)
	assert(settings.nest_initial_delay_seconds >= 0.0)
	assert(settings.nest_roll_chance_min >= 0.0)
	assert(settings.nest_roll_chance_max >= settings.nest_roll_chance_min)
	assert(settings.nest_roll_chance_max <= 1.0)
	assert(settings.same_species_near_weight > 0.0 and settings.same_species_near_weight <= 1.0)
	for first: int in range(settings.initial_nests):
		for second: int in range(first + 1, settings.initial_nests):
			assert(
				(
					spawn_positions[first].distance_to(spawn_positions[second])
					>= settings.nest_min_distance
				),
				"Opening sites must respect the hard nest spacing."
			)
	assert(settings.nest_upgrade_costs.size() > 0)
	assert(settings.nest_upgrade_costs.size() == settings.spawn_intervals.size())
	assert(settings.nest_population_limits.size() == settings.spawn_intervals.size())
	assert(settings.pipe_capture_seconds.size() == settings.pipe_upgrade_costs.size() + 1)
	assert(settings.net_capacities.size() == settings.net_upgrade_costs.size() + 1)
	assert(settings.net_size_multipliers.size() == settings.net_size_upgrade_costs.size() + 1)
	assert(is_equal_approx(settings.net_size_multipliers[0], 1.0))
	for multiplier: float in settings.net_size_multipliers:
		assert(multiplier > 0.0)
	assert(settings.pipe_radius > 0.0)
	assert(settings.net_radius > 0.0 and settings.net_cooldown_seconds > 0.0)
	assert(settings.governance_upgrade_costs.size() == 2)
	assert(settings.passive_income_per_second >= 0.0)
	assert(settings.automatic_income_interval > 0.0)
	assert(settings.base_value_multipliers.size() == settings.base_value_upgrade_costs.size() + 1)
	assert(settings.base_value_multipliers[0] == 1)
	assert(settings.combo_reward_percentages.size() == settings.combo_upgrade_costs.size())
	assert(settings.combo_stage_targets.size() == settings.combo_upgrade_costs.size())
	assert(settings.combo_window_seconds > 0.0)
	for target: int in settings.combo_stage_targets:
		assert(target > 0)
	assert(settings.spawn_burst_ratio_min > 0.0)
	assert(settings.spawn_burst_ratio_max >= settings.spawn_burst_ratio_min)
	assert(settings.spawn_burst_ratio_max <= 1.0)
	assert(settings.spawn_interval_jitter >= 0.0)
	assert(settings.giant_fusion_threshold >= 2 and settings.giant_check_interval > 0.0)
	assert(settings.giant_activity_radius_multiplier > 0.0)
	for weight: float in settings.unlocked_species_weights:
		assert(weight > 0.0, "Unlocked species need positive discovery weights.")
	for capacity: int in settings.net_capacities:
		assert(capacity > 0, "Net capacities must be positive.")
	for interval: float in settings.spawn_intervals:
		assert(
			interval > settings.spawn_interval_jitter, "Spawn intervals must exceed their jitter."
		)
	for population_limit: int in settings.nest_population_limits:
		assert(population_limit > 0, "Nest population limits must be positive.")
	_nest_roll_clock = 0.0
	_nest_spawn_cooldown_remaining = 0.0
	_nest_initial_delay_remaining = settings.nest_initial_delay_seconds
	_pending_nest_species = -1
	_random.randomize()
	candy = 0
	base_value_level = 0
	_combo_reward_remainder = 0
	pipe_level = 0
	net_level = 0
	net_size_level = 0
	net_unlocked = false
	governance_level = 0
	valuable_level = 0
	giant_unlocked = false
	combo_level = 0
	_reset_combo()
	net_cooldown_remaining = 0.0
	nests.clear()
	generated_nests = 0
	completed_nests = 0
	unlocked_colors.clear()
	is_complete = false
	generation_stage = 0
	economy_changed.emit()
	net_cooldown_changed.emit()
	for index: int in range(settings.initial_nests):
		_add_nest(NestState.Species.SLIME, spawn_positions[index])
	base_value_changed.emit()


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	if net_cooldown_remaining > 0.0:
		net_cooldown_remaining = maxf(0.0, net_cooldown_remaining - delta)
		net_cooldown_changed.emit()
	if combo_remaining > 0.0:
		combo_remaining = maxf(0.0, combo_remaining - delta)
		if combo_remaining == 0.0:
			_reset_combo()
			combo_interrupted.emit()
			economy_changed.emit()
	var current_nests: Array[NestState] = nests.duplicate()
	for nest: NestState in current_nests:
		_advance_nest_population(nest, delta)
		_advance_automatic_income(nest, delta)
	_advance_nest_roll(delta)


func collect_slime(
	nest_id: int,
	reward: int = -1,
	population: int = 1,
	valuable: bool = false,
	capture_color: Color = Color("ffa6c6")
) -> bool:
	return _collect_slime(nest_id, reward, population, valuable, capture_color, true)


func are_all_nests_automated() -> bool:
	if nests.is_empty():
		return false
	for nest: NestState in nests:
		if not nest.is_tamed or nest.is_discovering:
			return false
	return true


func collect_flower_target(nest_id: int, reward: int, population: int, valuable: bool) -> bool:
	if is_complete or not are_all_nests_automated():
		return false
	return _collect_slime(nest_id, reward, population, valuable, Color.WHITE, false)


func _collect_slime(
	nest_id: int,
	reward: int,
	population: int,
	valuable: bool,
	capture_color: Color,
	manual_capture: bool
) -> bool:
	var nest: NestState = get_nest(nest_id)
	if nest == null or population <= 0 or nest.alive_slimes < population:
		return false
	nest.alive_slimes -= population
	if nest.species == NestState.Species.DRILL:
		var multiplier: int = settings.valuable_reward_multiplier if valuable else 1
		candy += get_base_value() * roll_drill_treasure() * multiplier
		nest_changed.emit(nest)
		economy_changed.emit()
		_check_completion()
		return true
	var capture_reward: int = (
		get_capture_reward(nest.species) * population if reward < 0 else reward
	)
	candy += capture_reward
	if manual_capture:
		_register_manual_capture(capture_reward, capture_color)
	nest_changed.emit(nest)
	economy_changed.emit()
	_check_completion()
	return true


func collect_net_batch(
	nest_ids: Array[int],
	rewards: Array[int] = [],
	populations: Array[int] = [],
	valuables: Array[bool] = []
) -> int:
	var collected_count: int = 0
	var reward: int = 0
	var changed_nests: Array[NestState] = []
	for index: int in range(nest_ids.size()):
		if collected_count >= get_net_capacity():
			break
		var nest: NestState = get_nest(nest_ids[index])
		var population: int = populations[index] if index < populations.size() else 1
		if nest == null or population != 1 or nest.alive_slimes < population:
			continue
		nest.alive_slimes -= population
		collected_count += 1
		if nest.species == NestState.Species.DRILL:
			var valuable: bool = index < valuables.size() and valuables[index]
			var multiplier: int = settings.valuable_reward_multiplier if valuable else 1
			reward += get_base_value() * roll_drill_treasure() * multiplier
		else:
			reward += (
				maxi(0, rewards[index])
				if index < rewards.size()
				else get_capture_reward(nest.species) * population
			)
		if not changed_nests.has(nest):
			changed_nests.append(nest)
	if collected_count == 0:
		return 0
	candy += reward
	for nest: NestState in changed_nests:
		nest_changed.emit(nest)
	economy_changed.emit()
	_check_completion()
	return reward


func purchase_technology(id: String) -> bool:
	id = _resolve_technology_action(id)
	var cost: int = get_technology_cost(id)
	if cost < 0 or candy < cost or not get_technology_requirement(id).is_empty():
		return false
	candy -= cost
	match id:
		"base_value":
			base_value_level += 1
			base_value_changed.emit()
		"pipe":
			pipe_level += 1
		"net_unlock":
			net_unlocked = true
			generation_stage = 1
		"net_capacity":
			net_level += 1
		"net_size":
			net_size_level += 1
		"cultivation":
			governance_level = 1
		"automation":
			governance_level = 3
		"valuable":
			valuable_level += 1
		"giant":
			giant_unlocked = true
		"combo_unlock":
			combo_level += 1
	economy_changed.emit()
	progress_committed.emit()
	return true


func upgrade_pipe() -> bool:
	return purchase_technology("pipe")


func upgrade_net() -> bool:
	return purchase_technology("net")


func upgrade_nest(nest_id: int) -> bool:
	var nest: NestState = get_nest(nest_id)
	var cost: int = get_nest_upgrade_cost(nest_id)
	if (
		nest == null
		or cost < 0
		or candy < cost
		or not get_nest_upgrade_requirement(nest_id).is_empty()
	):
		return false
	candy -= cost
	nest.level += 1
	if nest.level == settings.nest_upgrade_costs.size():
		nest.is_tamed = true
		nest.spawn_clock = 0.0
		nest.income_remainder = 0.0
		nest.income_clock = 0.0
		completed_nests += 1
	nest_changed.emit(nest)
	economy_changed.emit()
	_check_completion()
	progress_committed.emit()
	return true


func get_nest(nest_id: int) -> NestState:
	for nest: NestState in nests:
		if nest.nest_id == nest_id:
			return nest
	return null


func get_species_population(species: int) -> int:
	var population: int = 0
	for nest: NestState in nests:
		if nest.species == species:
			population += nest.alive_slimes
	return population


func get_technology_level(id: String) -> int:
	match id:
		"valuable":
			return valuable_level
		"giant":
			return 1 if giant_unlocked else 0
		"base_value":
			return base_value_level
		"pipe":
			return pipe_level
		"net":
			return net_level
		"governance":
			return governance_level
		"combo":
			return combo_level
		"net_unlock":
			return 1 if net_unlocked else 0
		"net_capacity":
			return net_level
		"net_size":
			return net_size_level
		"cultivation":
			return 1 if governance_level >= 1 else 0
		"automation":
			return 1 if governance_level >= 3 else 0
		"combo_unlock":
			return combo_level
	return -1


func get_technology_cost(id: String) -> int:
	id = _resolve_technology_action(id)
	match id:
		"giant":
			return -1 if giant_unlocked else settings.giant_unlock_cost
		"net_unlock":
			return -1 if net_unlocked else settings.net_unlock_cost
		"cultivation":
			return -1 if governance_level >= 1 else settings.governance_upgrade_costs[0]
		"automation":
			return -1 if governance_level >= 3 else settings.governance_upgrade_costs[1]
		"combo_unlock":
			return (
				-1
				if combo_level >= settings.combo_upgrade_costs.size()
				else settings.combo_upgrade_costs[combo_level]
			)
	var costs: PackedInt32Array = _get_technology_costs(id)
	var level: int = get_technology_level(id)
	if level < 0 or level >= costs.size():
		return -1
	return costs[level]


func get_technology_requirement(id: String) -> String:
	id = _resolve_technology_action(id)
	if get_technology_level(id) < 0:
		return "未知科技"
	var prerequisites: Dictionary[String, int] = get_technology_prerequisites(id)
	for prerequisite: String in prerequisites:
		if get_technology_level(prerequisite) < prerequisites[prerequisite]:
			match prerequisite:
				"pipe":
					return "需要吸取速率 %d 级" % (prerequisites[prerequisite] + 1)
				"net_unlock":
					return "需要解锁捕网"
				"net_capacity":
					return "需要捕网扩容满级（%d 级）" % settings.net_capacities.size()
				"cultivation":
					return "需要巢穴培育"
	return ""


# Cross-branch prerequisites are shared by purchase validation and the tree view.
# Earlier levels within each branch are already enforced by sequential purchasing.
func get_technology_prerequisites(id: String) -> Dictionary[String, int]:
	id = _resolve_technology_action(id)
	var prerequisites: Dictionary[String, int] = {}
	match id:
		"net_unlock", "combo_unlock":
			prerequisites["pipe"] = 1
		"net_capacity":
			prerequisites["net_unlock"] = 1
		"net_size":
			prerequisites["net_unlock"] = 1
			prerequisites["net_capacity"] = settings.net_upgrade_costs.size()
		"automation", "valuable", "giant":
			prerequisites["cultivation"] = 1
	return prerequisites


# Existing tool shortcuts keep choosing the next action in their own branch.
func _resolve_technology_action(id: String) -> String:
	match id:
		"net":
			return "net_capacity" if net_unlocked else "net_unlock"
		"governance":
			return "automation" if governance_level > 0 else "cultivation"
		"combo":
			return "combo_unlock"
	return id


func get_technology_description(id: String) -> String:
	id = _resolve_technology_action(id)
	match id:
		"base_value":
			return "让每次捕获都带回更多糖果。"
		"pipe":
			return "更快吸入眼前的怪物，接连收走整群。"
		"net_unlock":
			return "解锁捕网，一次捕获成群的史莱姆。"
		"net_capacity":
			return "让一张捕网装下更多目标，收走更大的群落。"
		"net_size":
			return "扩大捕网范围，网住分布更散的目标。"
		"cultivation":
			return "解锁巢穴培育升级，让巢穴能容纳更多怪物。"
		"automation":
			return "恢复巢穴为小花，自动产糖，最终帮助星球自愈！"
		"combo_unlock":
			return "每成功连续吸取史莱姆，就结算一次额外糖果！"
		"valuable":
			return "怪物中会出现高价值个体，有机会赚取多倍糖果。"
		"giant":
			return "屏幕外的小怪现在会聚集成巨型史莱姆！"
	return ""


func get_technology_gain(id: String) -> String:
	id = _resolve_technology_action(id)
	match id:
		"base_value":
			var next_level: int = mini(
				base_value_level + 1, settings.base_value_multipliers.size() - 1
			)
			return _upgrade_percent(
				"糖果收益",
				get_base_value(),
				settings.slime_reward * settings.base_value_multipliers[next_level]
			)
		"pipe":
			var next_level: int = mini(pipe_level + 1, settings.pipe_capture_seconds.size() - 1)
			return _upgrade_percent(
				"吸取速率",
				1.0 / get_pipe_capture_seconds(),
				1.0 / settings.pipe_capture_seconds[next_level]
			)
		"net_unlock":
			return (
				"每网最多 %d 只 · 冷却 %s 秒"
				% [
					settings.net_capacities[net_level],
					String.num(settings.net_cooldown_seconds, 1).trim_suffix(".0")
				]
			)
		"net_capacity":
			var next_level: int = mini(net_level + 1, settings.net_capacities.size() - 1)
			return _upgrade_percent(
				"捕网容量", settings.net_capacities[net_level], settings.net_capacities[next_level]
			)
		"net_size":
			var next_level: int = mini(net_size_level + 1, settings.net_size_multipliers.size() - 1)
			return _upgrade_percent(
				"捕网半径",
				settings.net_size_multipliers[net_size_level],
				settings.net_size_multipliers[next_level]
			)
		"combo_unlock":
			var stage: int = mini(combo_level, settings.combo_stage_targets.size() - 1)
			return (
				"第 %d 段 · %d 只 → 额外 +%d%%"
				% [
					stage + 1,
					settings.combo_stage_targets[stage],
					settings.combo_reward_percentages[stage]
				]
			)
		"valuable":
			return "高价值个体收益 ×%d" % settings.valuable_reward_multiplier
	return ""


# Compare the next tier with the current tier; rates use the inverse of duration.
func _upgrade_percent(label: String, current: float, next: float) -> String:
	if is_equal_approx(current, next):
		return ""
	return "%s +%s%%" % [label, String.num((next / current - 1.0) * 100.0, 1).trim_suffix(".0")]


func get_nest_upgrade_requirement(nest_id: int) -> String:
	var nest: NestState = get_nest(nest_id)
	if nest == null:
		return "选择一个生态区"
	if nest.is_tamed:
		return ""
	if get_technology_level("cultivation") == 0:
		return "先研究巢穴培育"
	if (
		nest.level == settings.nest_upgrade_costs.size() - 1
		and get_technology_level("automation") == 0
	):
		return "先研究完全治理"
	return ""


func get_pipe_upgrade_cost() -> int:
	if pipe_level >= settings.pipe_upgrade_costs.size():
		return -1
	return settings.pipe_upgrade_costs[pipe_level]


func get_net_quick_upgrade_id() -> String:
	if not net_unlocked:
		return "net_unlock"
	return "net_capacity" if net_level < settings.net_upgrade_costs.size() else "net_size"


func get_net_upgrade_cost() -> int:
	if not net_unlocked:
		return settings.net_unlock_cost
	if net_level >= settings.net_upgrade_costs.size():
		return -1
	return settings.net_upgrade_costs[net_level]


func get_nest_upgrade_cost(nest_id: int) -> int:
	var nest: NestState = get_nest(nest_id)
	if nest == null or nest.is_tamed:
		return -1
	return settings.nest_upgrade_costs[nest.level]


func get_nest_population_limit(nest_id: int) -> int:
	var nest: NestState = get_nest(nest_id)
	if nest == null:
		return 0
	if nest.species == NestState.Species.DRILL:
		return settings.drill_population_limits[mini(nest.level, 2)]
	return settings.nest_population_limits[mini(
		nest.level, settings.nest_population_limits.size() - 1
	)]


func get_nest_spawn_interval(nest_id: int) -> float:
	var nest: NestState = get_nest(nest_id)
	if nest == null:
		return 0.0
	if nest.species == NestState.Species.DRILL:
		return settings.drill_spawn_interval + nest.spawn_interval_offset
	return (
		settings.spawn_intervals[mini(nest.level, settings.spawn_intervals.size() - 1)]
		+ nest.spawn_interval_offset
	)


func schedule_next_spawn(nest_id: int, delay_seconds: float) -> void:
	var nest: NestState = get_nest(nest_id)
	assert(nest != null, "Scheduling a spawn requires an existing nest.")
	assert(delay_seconds >= 0.0, "A spawn delay cannot be negative.")
	# Only the next burst moves; later bursts retain the normal sampled cooldowns.
	nest.spawn_clock = get_nest_spawn_interval(nest_id) - delay_seconds


func get_pipe_radius() -> float:
	return settings.pipe_radius


func get_pipe_capture_seconds() -> float:
	return settings.pipe_capture_seconds[pipe_level]


func get_net_capacity() -> int:
	return settings.net_capacities[net_level] if net_unlocked else 0


func get_net_radius() -> float:
	return settings.net_radius * settings.net_size_multipliers[net_size_level]


func can_cast_net() -> bool:
	return net_unlocked and net_cooldown_remaining <= 0.0


func begin_net_cast() -> bool:
	if not can_cast_net():
		return false
	net_cooldown_remaining = settings.net_cooldown_seconds
	net_cooldown_changed.emit()
	return true


func get_base_value() -> int:
	return settings.slime_reward * settings.base_value_multipliers[base_value_level]


func get_capture_reward(species: NestState.Species, valuable: bool = false) -> int:
	return get_base_value() * get_capture_value_units(species, valuable)


func get_capture_value_units(species: NestState.Species, valuable: bool = false) -> int:
	var units: int = 2 if species == NestState.Species.MUCUS else 1
	return units * settings.valuable_reward_multiplier if valuable else units


# The scene supplies real offscreen individuals. This transaction moves their
# population to the chosen host without awarding candy or freeing its occupancy.
func fuse_population(contributions: Dictionary[int, int], owner_id: int) -> bool:
	if not giant_unlocked or not contributions.has(owner_id):
		return false
	var total: int = 0
	for source_id: int in contributions:
		var source: NestState = get_nest(source_id)
		var count: int = contributions[source_id]
		if source == null or count <= 0 or count > source.alive_slimes:
			return false
		if count > contributions[owner_id]:
			return false
		total += count
	if total != settings.giant_fusion_threshold:
		return false
	for source_id: int in contributions:
		get_nest(source_id).alive_slimes -= contributions[source_id]
	get_nest(owner_id).alive_slimes += total
	for source_id: int in contributions:
		nest_changed.emit(get_nest(source_id))
	return true


func get_automatic_income_per_nest() -> float:
	return settings.passive_income_per_second * settings.base_value_multipliers[base_value_level]


func get_passive_income() -> float:
	return float(completed_nests) * get_automatic_income_per_nest()


func _get_technology_costs(id: String) -> PackedInt32Array:
	match id:
		"valuable":
			return settings.valuable_upgrade_costs
		"base_value":
			return settings.base_value_upgrade_costs
		"pipe":
			return settings.pipe_upgrade_costs
		"net_capacity":
			return settings.net_upgrade_costs
		"net_size":
			return settings.net_size_upgrade_costs
	return PackedInt32Array()


func get_combo_window_seconds() -> float:
	return settings.combo_window_seconds


func get_combo_target() -> int:
	return settings.combo_stage_targets[combo_stage]


func get_combo_reward_percent() -> int:
	return settings.combo_reward_percentages[combo_stage] if combo_level > 0 else 0


func _reset_combo() -> void:
	combo_stage = 0
	combo_count = 0
	combo_stage_candy = 0
	combo_remaining = 0.0


func _register_manual_capture(reward: int, capture_color: Color) -> void:
	if combo_level == 0:
		return
	if combo_remaining <= 0.0:
		combo_remaining = get_combo_window_seconds()
	combo_count += 1
	combo_stage_candy += reward
	combo_progressed.emit(capture_color)
	if combo_count < get_combo_target():
		return
	_combo_reward_remainder += combo_stage_candy * get_combo_reward_percent()
	@warning_ignore("integer_division")
	var bonus: int = _combo_reward_remainder / 100
	_combo_reward_remainder %= 100
	candy += bonus
	var completed_stage: int = combo_stage
	if combo_stage + 1 >= combo_level:
		_reset_combo()
	else:
		combo_stage += 1
		combo_count = 0
		combo_stage_candy = 0
		combo_remaining = get_combo_window_seconds()
	combo_stage_completed.emit(completed_stage + 1, bonus)


func _advance_nest_population(nest: NestState, delta: float) -> void:
	if nest.is_tamed or nest.is_discovering or is_complete:
		nest.spawn_clock = 0.0
		return
	var population_limit: int = get_nest_population_limit(nest.nest_id)
	if nest.alive_slimes >= population_limit:
		nest.spawn_clock = 0.0
		return
	nest.spawn_clock += delta
	var interval: float = get_nest_spawn_interval(nest.nest_id)
	var spawned: bool = false
	while nest.spawn_clock >= interval:
		nest.spawn_clock -= interval
		_roll_nest_spawn_interval(nest)
		interval = get_nest_spawn_interval(nest.nest_id)
		var burst_count: int = 1
		if nest.species != NestState.Species.DRILL:
			var burst_min: int = ceili(float(population_limit) * settings.spawn_burst_ratio_min)
			var burst_max: int = floori(float(population_limit) * settings.spawn_burst_ratio_max)
			burst_count = mini(
				_random.randi_range(burst_min, burst_max), population_limit - nest.alive_slimes
			)
		for _index: int in range(burst_count):
			nest.alive_slimes += 1
			slime_requested.emit(nest.nest_id)
		spawned = true
		if nest.alive_slimes >= population_limit:
			nest.spawn_clock = 0.0
			break
	if spawned:
		nest_changed.emit(nest)


func _roll_nest_spawn_interval(nest: NestState) -> void:
	nest.spawn_interval_offset = _random.randf_range(
		-settings.spawn_interval_jitter, settings.spawn_interval_jitter
	)


func _advance_automatic_income(nest: NestState, delta: float) -> void:
	if not nest.is_tamed or delta <= 0.0:
		return
	var remaining_delta: float = delta
	while remaining_delta > 0.0:
		var step: float = minf(
			remaining_delta, settings.automatic_income_interval - nest.income_clock
		)
		nest.income_clock += step
		nest.income_remainder += get_automatic_income_per_nest() * step
		remaining_delta -= step
		if nest.income_clock < settings.automatic_income_interval:
			continue
		nest.income_clock = 0.0
		var amount: int = floori(nest.income_remainder)
		if amount <= 0:
			continue
		nest.income_remainder -= float(amount)
		candy += amount
		automatic_income_received.emit(nest.nest_id, amount)
		economy_changed.emit()


func get_average_governance() -> float:
	if nests.is_empty():
		return 0.0
	var total_levels: int = 0
	for nest: NestState in nests:
		total_levels += nest.level
	return float(total_levels) / float(nests.size() * settings.nest_upgrade_costs.size())


func get_nest_roll_chance() -> float:
	return lerpf(
		settings.nest_roll_chance_min, settings.nest_roll_chance_max, get_average_governance()
	)


func resolve_nest_spawn(
	position: Vector2, site_available: bool = true, defer_population: bool = false
) -> bool:
	if _pending_nest_species < 0:
		return false
	var species: NestState.Species = _pending_nest_species as NestState.Species
	_pending_nest_species = -1
	if not site_available or is_complete:
		return false
	if species == NestState.Species.DRILL and not can_discover_drill_nest():
		return false
	_nest_roll_clock = 0.0
	_nest_spawn_cooldown_remaining = settings.nest_spawn_cooldown_seconds
	_add_nest(species, position, defer_population)
	if not defer_population:
		schedule_next_spawn(nests.back().nest_id, _random.randf_range(0.0, 1.0))
	return true


func finish_nest_discovery(nest_id: int) -> void:
	var nest: NestState = get_nest(nest_id)
	assert(nest != null)
	nest.is_discovering = false
	schedule_next_spawn(nest_id, _random.randf_range(0.0, 1.0))


func record_flower(nest_id: int) -> void:
	var nest: NestState = get_nest(nest_id)
	assert(nest != null and nest.is_tamed, "Only an automated nest can reveal a flower.")
	if nest.species in unlocked_colors:
		return
	unlocked_colors.append(nest.species)
	_check_completion()


func _check_completion() -> void:
	if is_complete or nests.is_empty() or unlocked_colors.size() != NestState.Species.size():
		return
	for nest: NestState in nests:
		if not nest.is_tamed or nest.alive_slimes > 0:
			return
	is_complete = true
	_nest_roll_clock = 0.0
	_nest_spawn_cooldown_remaining = 0.0
	_nest_initial_delay_remaining = 0.0
	_pending_nest_species = -1
	goal_completed.emit()


func _advance_nest_roll(delta: float) -> void:
	if is_complete:
		_nest_roll_clock = 0.0
		_nest_spawn_cooldown_remaining = 0.0
		_nest_initial_delay_remaining = 0.0
		return
	if _nest_site_capacity > 0 and nests.size() >= _nest_site_capacity:
		return
	var remaining_delta: float = delta
	if _nest_initial_delay_remaining > 0.0:
		var delay_step: float = minf(remaining_delta, _nest_initial_delay_remaining)
		_nest_initial_delay_remaining -= delay_step
		remaining_delta -= delay_step
	if not net_unlocked:
		_nest_roll_clock = 0.0
		_nest_spawn_cooldown_remaining = 0.0
		return
	if remaining_delta <= 0.0 or _pending_nest_species >= 0:
		return
	while remaining_delta > 0.0:
		if _nest_spawn_cooldown_remaining > 0.0:
			var cooldown_step: float = minf(remaining_delta, _nest_spawn_cooldown_remaining)
			_nest_spawn_cooldown_remaining -= cooldown_step
			remaining_delta -= cooldown_step
			if remaining_delta <= 0.0:
				return
		var roll_step: float = minf(remaining_delta, settings.nest_roll_interval - _nest_roll_clock)
		_nest_roll_clock += roll_step
		remaining_delta -= roll_step
		if _nest_roll_clock < settings.nest_roll_interval:
			return
		_nest_roll_clock = 0.0
		if _random.randf() >= get_nest_roll_chance():
			continue
		_pending_nest_species = _choose_spawn_species()
		nest_spawn_requested.emit(_pending_nest_species as NestState.Species)
		if (
			_pending_nest_species >= 0
			or is_complete
			or (_nest_site_capacity > 0 and nests.size() >= _nest_site_capacity)
		):
			return


func _choose_spawn_species() -> int:
	# Opening and automated nests occupy sites and count toward the minimum.
	var weights: PackedFloat32Array = settings.unlocked_species_weights.duplicate()
	weights.append(get_drill_discovery_weight())
	var counts: PackedInt32Array = PackedInt32Array([0, 0, 0])
	for nest: NestState in nests:
		counts[nest.species] += 1
	var deficits: PackedInt32Array = PackedInt32Array([0, 0, 0])
	var total_deficit: int = 0
	for species: int in range(weights.size()):
		if weights[species] > 0.0:
			var minimum: int = settings.nest_minimum_counts[species]
			if species == NestState.Species.DRILL:
				minimum = mini(minimum, settings.drill_nest_limit)
			deficits[species] = maxi(0, minimum - counts[species])
			total_deficit += deficits[species]
	var reserve_sites: bool = (
		_nest_site_capacity > 0 and _nest_site_capacity - nests.size() <= total_deficit
	)
	var total_weight: float = 0.0
	for species: int in range(weights.size()):
		if reserve_sites and deficits[species] == 0:
			weights[species] = 0.0
		total_weight += weights[species]
	assert(total_weight > 0.0, "Discovery needs an eligible species and a free site.")
	var roll: float = _random.randf() * total_weight
	var last_eligible: int = NestState.Species.SLIME
	for species: int in range(weights.size()):
		if weights[species] <= 0.0:
			continue
		last_eligible = species
		roll -= weights[species]
		if roll < 0.0:
			return species
	return last_eligible


func can_discover_drill_nest() -> bool:
	return get_drill_nest_count() < settings.drill_nest_limit


func get_drill_discovery_weight() -> float:
	if not can_discover_drill_nest():
		return 0.0
	return settings.drill_discovery_weight


func get_drill_nest_count() -> int:
	var count: int = 0
	for nest: NestState in nests:
		if nest.species == NestState.Species.DRILL:
			count += 1
	return count


func roll_drill_treasure() -> int:
	var total: int = 0
	for weight: int in settings.drill_reward_weights:
		total += weight
	var roll: int = _random.randi_range(0, total - 1)
	for index: int in range(settings.drill_reward_weights.size()):
		roll -= settings.drill_reward_weights[index]
		if roll < 0:
			return settings.drill_reward_multipliers[index]
	return settings.drill_reward_multipliers[-1]


func _add_nest(
	species: NestState.Species, position: Vector2, defer_population: bool = false
) -> void:
	var nest: NestState = NestState.new()
	nest.nest_id = generated_nests + 1
	nest.species = species
	nest.position = position
	nest.is_discovering = defer_population
	_roll_nest_spawn_interval(nest)
	nests.append(nest)
	generated_nests += 1
	nest_added.emit(nest)


func capture_save() -> Dictionary:
	var data: Dictionary = SaveFields.capture(self, SAVE_FIELDS)
	data["random_state"] = _random.state
	var saved_nests: Array[Dictionary] = []
	for nest: NestState in nests:
		saved_nests.append(SaveFields.capture(nest, NEST_SAVE_FIELDS))
	data["nests"] = saved_nests
	return data


func accepts_save(data: Dictionary) -> bool:
	if not SaveFields.matches(self, data, SAVE_FIELDS) or not data.get("nests") is Array:
		return false
	var limits: Dictionary = {
		"base_value_level": settings.base_value_upgrade_costs.size(),
		"pipe_level": settings.pipe_upgrade_costs.size(),
		"net_level": settings.net_upgrade_costs.size(),
		"net_size_level": settings.net_size_upgrade_costs.size(),
		"valuable_level": settings.valuable_upgrade_costs.size(),
		"combo_level": settings.combo_upgrade_costs.size(),
		"governance_level": 3,
	}
	for field: String in limits:
		if data[field] < 0 or data[field] > limits[field]:
			return false
	if (
		data.candy < 0
		or data.combo_stage < 0
		or data.combo_stage >= settings.combo_stage_targets.size()
	):
		return false
	if data.nests.size() < settings.initial_nests or data.nests.size() > _nest_site_capacity:
		return false
	if data.generated_nests != data.nests.size() or not data.get("random_state") is int:
		return false
	var template: NestState = NestState.new()
	for index: int in range(data.nests.size()):
		var nest: Variant = data.nests[index]
		if not nest is Dictionary or not SaveFields.matches(template, nest, NEST_SAVE_FIELDS):
			return false
		if nest.nest_id != index + 1 or nest.species < 0 or nest.species > 2:
			return false
		if (
			nest.level < 0
			or nest.level > settings.nest_upgrade_costs.size()
			or nest.alive_slimes < 0
		):
			return false
		if (
			not nest.position.is_finite()
			or nest.income_clock < 0.0
			or nest.income_clock >= settings.automatic_income_interval
		):
			return false
	return true


func restore_save(data: Dictionary) -> void:
	assert(accepts_save(data))
	SaveFields.restore(self, data, SAVE_FIELDS)
	_random.state = data.random_state
	nests.clear()
	for saved: Dictionary in data.nests:
		var nest: NestState = NestState.new()
		SaveFields.restore(nest, saved, NEST_SAVE_FIELDS)
		# Appearance can settle on reload; population must no longer wait on its old animation.
		nest.is_discovering = false
		nests.append(nest)
