class_name PrototypeRun
extends Node

signal economy_changed
signal collection_changed
signal net_cooldown_changed
signal nest_added(nest: NestState)
signal nest_changed(nest: NestState)
signal slime_requested(nest_id: int)
signal goal_completed

@export var settings: PrototypeSettings

var candy: int = 0
var pipe_level: int = 0
var net_level: int = 0
var net_cooldown_remaining: float = 0.0
var nests: Array[NestState] = []
var generated_nests: int = 0
var completed_nests: int = 0
var is_complete: bool = false
var passive_remainder: float = 0.0
var pending_candy: int = 0
var pending_slime_count: int = 0

var _spawn_positions: Array[Vector2] = []


func start_run(spawn_positions: Array[Vector2]) -> void:
	assert(settings != null, "PrototypeRun requires a PrototypeSettings resource.")
	assert(spawn_positions.size() >= settings.nest_budget, "Each nest needs a spawn position.")
	assert(settings.nest_budget > 0 and settings.active_nest_limit > 0)
	assert(settings.nest_upgrade_costs.size() > 0)
	assert(settings.nest_upgrade_costs.size() == settings.spawn_intervals.size())
	assert(settings.nest_population_limits.size() == settings.spawn_intervals.size())
	assert(settings.pipe_capture_seconds.size() == settings.pipe_upgrade_costs.size() + 1)
	assert(settings.net_capacities.size() == settings.net_upgrade_costs.size() + 1)
	assert(settings.pipe_radius > 0.0 and settings.pipe_attraction_radius >= settings.pipe_radius)
	assert(settings.net_radius > 0.0 and settings.net_cooldown_seconds > 0.0)
	for capacity: int in settings.net_capacities:
		assert(capacity > 0, "Net capacities must be positive.")
	for interval: float in settings.spawn_intervals:
		assert(interval > 0.0, "Spawn intervals must be positive.")
	for population_limit: int in settings.nest_population_limits:
		assert(population_limit > 0, "Nest population limits must be positive.")
	_spawn_positions.assign(spawn_positions)
	candy = 0
	pipe_level = 0
	net_level = 0
	net_cooldown_remaining = 0.0
	nests.clear()
	generated_nests = 0
	completed_nests = 0
	is_complete = false
	passive_remainder = 0.0
	pending_candy = 0
	pending_slime_count = 0
	economy_changed.emit()
	collection_changed.emit()
	net_cooldown_changed.emit()
	var initial_count: int = mini(
		settings.initial_nests, mini(settings.nest_budget, settings.active_nest_limit)
	)
	for _index: int in range(initial_count):
		_add_nest()


func advance(delta: float) -> void:
	if is_complete or delta <= 0.0:
		return
	if net_cooldown_remaining > 0.0:
		net_cooldown_remaining = maxf(0.0, net_cooldown_remaining - delta)
		net_cooldown_changed.emit()
	passive_remainder += get_passive_income() * delta
	var income: int = int(floor(passive_remainder))
	if income > 0:
		passive_remainder -= float(income)
		candy += income
		economy_changed.emit()
	for nest: NestState in nests:
		if nest.is_tamed:
			continue
		var population_limit: int = get_nest_population_limit(nest.nest_id)
		if nest.alive_slimes >= population_limit:
			nest.spawn_clock = 0.0
			continue
		nest.spawn_clock += delta
		var interval: float = settings.spawn_intervals[nest.level]
		var spawned: bool = false
		while nest.spawn_clock >= interval:
			nest.spawn_clock -= interval
			nest.alive_slimes += 1
			spawned = true
			slime_requested.emit(nest.nest_id)
			if nest.alive_slimes >= population_limit:
				nest.spawn_clock = 0.0
				break
		if spawned:
			nest_changed.emit(nest)
	_fill_active_nests()


func collect_slime(nest_id: int) -> bool:
	if is_complete:
		return false
	var nest: NestState = get_nest(nest_id)
	if nest == null or nest.alive_slimes <= 0:
		return false
	nest.alive_slimes -= 1
	pending_slime_count += 1
	pending_candy += settings.slime_reward
	nest_changed.emit(nest)
	collection_changed.emit()
	return true


func settle_collection() -> int:
	if pending_candy == 0:
		return 0
	var reward: int = pending_candy
	candy += reward
	pending_candy = 0
	pending_slime_count = 0
	collection_changed.emit()
	economy_changed.emit()
	return reward


func collect_net_batch(nest_ids: Array[int]) -> int:
	if is_complete:
		return 0
	var collected_count: int = 0
	var changed_nests: Array[NestState] = []
	for nest_id: int in nest_ids:
		if collected_count >= get_net_capacity():
			break
		var nest: NestState = get_nest(nest_id)
		if nest == null or nest.alive_slimes <= 0:
			continue
		nest.alive_slimes -= 1
		collected_count += 1
		if not changed_nests.has(nest):
			changed_nests.append(nest)
	var reward: int = collected_count * settings.slime_reward
	if reward == 0:
		return 0
	candy += reward
	for nest: NestState in changed_nests:
		nest_changed.emit(nest)
	economy_changed.emit()
	return reward


func upgrade_pipe() -> bool:
	var cost: int = get_pipe_upgrade_cost()
	if is_complete or cost < 0 or candy < cost:
		return false
	candy -= cost
	pipe_level += 1
	economy_changed.emit()
	return true


func upgrade_net() -> bool:
	var cost: int = get_net_upgrade_cost()
	if is_complete or cost < 0 or candy < cost:
		return false
	candy -= cost
	net_level += 1
	economy_changed.emit()
	return true


func upgrade_nest(nest_id: int) -> bool:
	var nest: NestState = get_nest(nest_id)
	var cost: int = get_nest_upgrade_cost(nest_id)
	if is_complete or nest == null or cost < 0 or candy < cost:
		return false
	candy -= cost
	nest.level += 1
	if nest.level == settings.nest_upgrade_costs.size():
		nest.is_tamed = true
		nest.spawn_clock = 0.0
		completed_nests += 1
	nest_changed.emit(nest)
	economy_changed.emit()
	_fill_active_nests()
	if completed_nests == settings.nest_budget:
		settle_collection()
		is_complete = true
		goal_completed.emit()
	return true


func get_nest(nest_id: int) -> NestState:
	for nest: NestState in nests:
		if nest.nest_id == nest_id:
			return nest
	return null


func get_pipe_upgrade_cost() -> int:
	if pipe_level >= settings.pipe_upgrade_costs.size():
		return -1
	return settings.pipe_upgrade_costs[pipe_level]


func get_net_upgrade_cost() -> int:
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
	var level: int = clampi(nest.level, 0, settings.nest_population_limits.size() - 1)
	return settings.nest_population_limits[level]


func get_pipe_radius() -> float:
	return settings.pipe_radius


func get_pipe_capture_seconds() -> float:
	return settings.pipe_capture_seconds[pipe_level]


func get_pipe_attraction_radius() -> float:
	return settings.pipe_attraction_radius


func get_net_capacity() -> int:
	return settings.net_capacities[net_level]


func get_net_radius() -> float:
	return settings.net_radius


func can_cast_net() -> bool:
	return not is_complete and net_cooldown_remaining <= 0.0


func begin_net_cast() -> bool:
	if not can_cast_net():
		return false
	net_cooldown_remaining = settings.net_cooldown_seconds
	net_cooldown_changed.emit()
	return true


func get_passive_income() -> float:
	return float(completed_nests) * settings.passive_income_per_second


func _fill_active_nests() -> void:
	var active_count: int = 0
	for nest: NestState in nests:
		if not nest.is_tamed:
			active_count += 1
	while active_count < settings.active_nest_limit and generated_nests < settings.nest_budget:
		_add_nest()
		active_count += 1


func _add_nest() -> void:
	var nest: NestState = NestState.new()
	nest.nest_id = generated_nests + 1
	nest.position = _spawn_positions[generated_nests]
	nests.append(nest)
	generated_nests += 1
	nest_added.emit(nest)
