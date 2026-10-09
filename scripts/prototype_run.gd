class_name PrototypeRun
extends Node

signal economy_changed
signal net_cooldown_changed
signal nest_added(nest: NestState)
signal nest_changed(nest: NestState)
signal nest_spawn_requested(species: NestState.Species)
signal slime_requested(nest_id: int)
signal automatic_income_received(nest_id: int, amount: int)
signal goal_completed

@export var settings: PrototypeSettings

var candy: int = 0
var pipe_level: int = 0
var net_level: int = 0
var net_unlocked: bool = false
var governance_level: int = 0
var combo_level: int = 0
var combo_interval_level: int = 0
var combo_count: int = 0
var combo_remaining: float = 0.0
var net_cooldown_remaining: float = 0.0
var nests: Array[NestState] = []
var generated_nests: int = 0
var completed_nests: int = 0
var is_complete: bool = false
var generation_stage: int = 0

var _nest_roll_clock: float = 0.0
var _pending_nest_species: int = -1
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


func start_run(spawn_positions: Array[Vector2]) -> void:
	assert(settings != null, "PrototypeRun requires a PrototypeSettings resource.")
	assert(settings.initial_nests == 2, "The opening needs two basic slime nests.")
	assert(spawn_positions.size() >= settings.initial_nests, "The opening needs two nest sites.")
	assert(settings.unlocked_species_weights.size() == 2)
	assert(settings.nest_roll_interval > 0.0)
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
	assert(settings.pipe_radius > 0.0)
	assert(settings.net_radius > 0.0 and settings.net_cooldown_seconds > 0.0)
	assert(settings.governance_upgrade_costs.size() == 2)
	assert(settings.passive_income_per_second >= 0.0)
	assert(settings.combo_target > 0 and settings.combo_window_seconds > 0.0)
	assert(
		(
			settings.combo_interval_bonus_seconds.size()
			== settings.combo_interval_upgrade_costs.size() + 1
		)
	)
	assert(settings.spawn_burst_ratio_min > 0.0)
	assert(settings.spawn_burst_ratio_max >= settings.spawn_burst_ratio_min)
	assert(settings.spawn_burst_ratio_max <= 1.0)
	for weight: float in settings.unlocked_species_weights:
		assert(weight > 0.0, "Unlocked species need positive discovery weights.")
	for capacity: int in settings.net_capacities:
		assert(capacity > 0, "Net capacities must be positive.")
	for interval: float in settings.spawn_intervals:
		assert(interval > 0.0, "Spawn intervals must be positive.")
	for population_limit: int in settings.nest_population_limits:
		assert(population_limit > 0, "Nest population limits must be positive.")
	_nest_roll_clock = 0.0
	_pending_nest_species = -1
	_random.randomize()
	candy = 0
	pipe_level = 0
	net_level = 0
	net_unlocked = false
	governance_level = 0
	combo_level = 0
	combo_interval_level = 0
	combo_count = 0
	combo_remaining = 0.0
	net_cooldown_remaining = 0.0
	nests.clear()
	generated_nests = 0
	completed_nests = 0
	is_complete = false
	generation_stage = 0
	economy_changed.emit()
	net_cooldown_changed.emit()
	for index: int in range(settings.initial_nests):
		_add_nest(NestState.Species.SLIME, spawn_positions[index])


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	if net_cooldown_remaining > 0.0:
		net_cooldown_remaining = maxf(0.0, net_cooldown_remaining - delta)
		net_cooldown_changed.emit()
	if combo_remaining > 0.0:
		combo_remaining = maxf(0.0, combo_remaining - delta)
		if combo_remaining == 0.0 and combo_count > 0:
			combo_count = 0
			economy_changed.emit()
	var current_nests: Array[NestState] = nests.duplicate()
	for nest: NestState in current_nests:
		_advance_nest_population(nest, delta)
		_advance_automatic_income(nest, delta)
	_advance_nest_roll(delta)


func collect_slime(nest_id: int, reward: int = -1) -> bool:
	var nest: NestState = get_nest(nest_id)
	if nest == null or nest.alive_slimes <= 0:
		return false
	nest.alive_slimes -= 1
	candy += settings.slime_reward if reward < 0 else reward
	candy += _register_manual_capture()
	nest_changed.emit(nest)
	economy_changed.emit()
	return true


func collect_net_batch(nest_ids: Array[int], rewards: Array[int] = []) -> int:
	var collected_count: int = 0
	var reward: int = 0
	var changed_nests: Array[NestState] = []
	for index: int in range(nest_ids.size()):
		if collected_count >= get_net_capacity():
			break
		var nest: NestState = get_nest(nest_ids[index])
		if nest == null or nest.alive_slimes <= 0:
			continue
		nest.alive_slimes -= 1
		collected_count += 1
		reward += maxi(0, rewards[index]) if index < rewards.size() else settings.slime_reward
		if not changed_nests.has(nest):
			changed_nests.append(nest)
	if collected_count == 0:
		return 0
	candy += reward
	for nest: NestState in changed_nests:
		nest_changed.emit(nest)
	economy_changed.emit()
	return reward


func purchase_technology(id: String) -> bool:
	id = _resolve_technology_action(id)
	var cost: int = get_technology_cost(id)
	if cost < 0 or candy < cost or not get_technology_requirement(id).is_empty():
		return false
	candy -= cost
	match id:
		"pipe":
			pipe_level += 1
		"net_unlock":
			net_unlocked = true
			generation_stage = 1
		"net_capacity":
			net_level += 1
		"cultivation":
			governance_level = 1
		"automation":
			governance_level = 3
		"combo_unlock", "combo_reward":
			combo_level += 1
		"combo_interval":
			combo_interval_level += 1
	economy_changed.emit()
	return true


func purchase_nest_technology(nest_id: int, id: String) -> bool:
	var cost: int = get_nest_technology_cost(nest_id, id)
	if cost < 0 or candy < cost or not get_nest_technology_requirement(nest_id, id).is_empty():
		return false
	var nest: NestState = get_nest(nest_id)
	candy -= cost
	nest.valuable_level += 1
	nest_changed.emit(nest)
	economy_changed.emit()
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
		completed_nests += 1
	_check_completion()
	nest_changed.emit(nest)
	economy_changed.emit()
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
		"cultivation":
			return 1 if governance_level >= 1 else 0
		"automation":
			return 1 if governance_level >= 3 else 0
		"combo_unlock":
			return 1 if combo_level > 0 else 0
		"combo_reward":
			return combo_level
		"combo_interval":
			return combo_interval_level
	return -1


func get_technology_cost(id: String) -> int:
	id = _resolve_technology_action(id)
	match id:
		"net_unlock":
			return -1 if net_unlocked else settings.net_unlock_cost
		"cultivation":
			return -1 if governance_level >= 1 else settings.governance_upgrade_costs[0]
		"automation":
			return -1 if governance_level >= 3 else settings.governance_upgrade_costs[1]
		"combo_unlock":
			return -1 if combo_level > 0 else settings.combo_upgrade_costs[0]
	var costs: PackedInt32Array = _get_technology_costs(id)
	var level: int = get_technology_level(id)
	if id == "combo_reward":
		level = maxi(1, level)
	if level < 0 or level >= costs.size():
		return -1
	return costs[level]


func get_technology_requirement(id: String) -> String:
	id = _resolve_technology_action(id)
	if id == "valuable":
		return "选择一个生态区"
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
				"combo_unlock":
					return "需要解锁连击"
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
		"combo_reward", "combo_interval":
			prerequisites["combo_unlock"] = 1
		"automation", "valuable":
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
			return "combo_reward" if combo_level > 0 else "combo_unlock"
	return id


func get_technology_description(id: String) -> String:
	id = _resolve_technology_action(id)
	match id:
		"pipe":
			var next_level: int = mini(pipe_level + 1, settings.pipe_capture_seconds.size() - 1)
			return (
				"每只 %s 秒 → %s 秒"
				% [
					String.num(get_pipe_capture_seconds(), 3),
					String.num(settings.pipe_capture_seconds[next_level], 3)
				]
			)
		"net_unlock":
			return "解锁捕网 · 每次 %d 只" % settings.net_capacities[0]
		"net_capacity":
			var next_level: int = mini(net_level + 1, settings.net_capacities.size() - 1)
			return (
				"一次 %d 只 → %d 只"
				% [settings.net_capacities[net_level], settings.net_capacities[next_level]]
			)
		"cultivation":
			return "开放各巢穴的培育建设"
		"automation":
			return "开放各巢穴的自动化建设"
		"combo_unlock":
			return "连续吸入 %d 只后，每只额外 +1 糖果" % settings.combo_target
		"combo_reward":
			var next_level: int = mini(combo_level + 1, settings.combo_upgrade_costs.size())
			return "连续吸入 %d 只后，每只额外 +%d → +%d 糖果" % [settings.combo_target, combo_level, next_level]
		"combo_interval":
			var next_level: int = mini(
				combo_interval_level + 1, settings.combo_interval_bonus_seconds.size() - 1
			)
			return (
				"续接间隔 %s → %s 秒"
				% [
					String.num(get_combo_window_seconds(), 1),
					String.num(
						(
							settings.combo_window_seconds
							+ settings.combo_interval_bonus_seconds[next_level]
						),
						1
					)
				]
			)
		"valuable":
			return (
				"每 %d 只新生个体出现 1 只 · 糖果 ×%d"
				% [settings.valuable_spawn_every, settings.valuable_reward_multiplier]
			)
	return ""


func get_nest_technology_cost(nest_id: int, id: String) -> int:
	var nest: NestState = get_nest(nest_id)
	if (
		nest == null
		or id != "valuable"
		or nest.valuable_level >= settings.valuable_upgrade_costs.size()
	):
		return -1
	return settings.valuable_upgrade_costs[nest.valuable_level]


func get_nest_technology_requirement(nest_id: int, id: String) -> String:
	var nest: NestState = get_nest(nest_id)
	if nest == null:
		return "选择一个生态区"
	if id != "valuable":
		return "未知科技"
	if nest.is_tamed:
		return "已自动化，停止产怪"
	return "需要巢穴培育" if governance_level < 1 else ""


func get_nest_upgrade_requirement(nest_id: int) -> String:
	var nest: NestState = get_nest(nest_id)
	if nest == null:
		return "选择一个生态区"
	if nest.is_tamed or nest.level < governance_level:
		return ""
	return "先研究巢穴培育" if nest.level == 0 else "先研究完全自动化"


func get_pipe_upgrade_cost() -> int:
	if pipe_level >= settings.pipe_upgrade_costs.size():
		return -1
	return settings.pipe_upgrade_costs[pipe_level]


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
	return settings.nest_population_limits[mini(
		nest.level, settings.nest_population_limits.size() - 1
	)]


func get_nest_spawn_interval(nest_id: int) -> float:
	var nest: NestState = get_nest(nest_id)
	return (
		settings.spawn_intervals[mini(nest.level, settings.spawn_intervals.size() - 1)]
		if nest != null
		else 0.0
	)


func get_pipe_radius() -> float:
	return settings.pipe_radius


func get_pipe_capture_seconds() -> float:
	return settings.pipe_capture_seconds[pipe_level]


func get_net_capacity() -> int:
	return settings.net_capacities[net_level] if net_unlocked else 0


func get_net_radius() -> float:
	return settings.net_radius


func can_cast_net() -> bool:
	return net_unlocked and net_cooldown_remaining <= 0.0


func begin_net_cast() -> bool:
	if not can_cast_net():
		return false
	net_cooldown_remaining = settings.net_cooldown_seconds
	net_cooldown_changed.emit()
	return true


func get_passive_income() -> float:
	return float(completed_nests) * settings.passive_income_per_second


func _get_technology_costs(id: String) -> PackedInt32Array:
	match id:
		"pipe":
			return settings.pipe_upgrade_costs
		"net_capacity":
			return settings.net_upgrade_costs
		"combo_reward":
			return settings.combo_upgrade_costs
		"combo_interval":
			return settings.combo_interval_upgrade_costs
	return PackedInt32Array()


func get_combo_window_seconds() -> float:
	return (
		settings.combo_window_seconds + settings.combo_interval_bonus_seconds[combo_interval_level]
	)


func _register_manual_capture() -> int:
	if combo_level == 0:
		return 0
	combo_remaining = get_combo_window_seconds()
	combo_count += 1
	if combo_count <= settings.combo_target:
		return 0
	return combo_level


func _advance_nest_population(nest: NestState, delta: float) -> void:
	if nest.is_tamed:
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
		var burst_min: int = ceili(float(population_limit) * settings.spawn_burst_ratio_min)
		var burst_max: int = floori(float(population_limit) * settings.spawn_burst_ratio_max)
		var burst_count: int = mini(
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


func _advance_automatic_income(nest: NestState, delta: float) -> void:
	if not nest.is_tamed:
		return
	nest.income_remainder += settings.passive_income_per_second * delta
	var amount: int = floori(nest.income_remainder)
	if amount <= 0:
		return
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


func resolve_nest_spawn(position: Vector2, site_available: bool = true) -> bool:
	if _pending_nest_species < 0:
		return false
	var species: NestState.Species = _pending_nest_species as NestState.Species
	_pending_nest_species = -1
	if not site_available or is_complete:
		return false
	_add_nest(species, position)
	return true


func _check_completion() -> void:
	if is_complete or nests.is_empty() or completed_nests != nests.size():
		return
	is_complete = true
	_nest_roll_clock = 0.0
	_pending_nest_species = -1
	goal_completed.emit()


func _advance_nest_roll(delta: float) -> void:
	if not net_unlocked or is_complete:
		_nest_roll_clock = 0.0
		return
	if _pending_nest_species >= 0:
		return
	_nest_roll_clock += delta
	while _nest_roll_clock >= settings.nest_roll_interval:
		_nest_roll_clock -= settings.nest_roll_interval
		if _random.randf() >= get_nest_roll_chance():
			continue
		_pending_nest_species = _choose_spawn_species()
		nest_spawn_requested.emit(_pending_nest_species as NestState.Species)
		if _pending_nest_species >= 0 or is_complete:
			return


func _choose_spawn_species() -> int:
	var total_weight: float = 0.0
	for weight: float in settings.unlocked_species_weights:
		total_weight += weight
	var roll: float = _random.randf() * total_weight
	for species: int in range(settings.unlocked_species_weights.size()):
		roll -= settings.unlocked_species_weights[species]
		if roll <= 0.0:
			return species
	return settings.unlocked_species_weights.size() - 1


func _add_nest(species: NestState.Species, position: Vector2) -> void:
	var nest: NestState = NestState.new()
	nest.nest_id = generated_nests + 1
	nest.species = species
	nest.position = position
	nests.append(nest)
	generated_nests += 1
	nest_added.emit(nest)
