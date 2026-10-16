extends Node

# FMOD events for monsters and candy collection.

const SPECIES_EVENTS: Dictionary = {
	NestState.Species.DRILL:
	{
		"nest_appear": "event:/Nest/Drill_NestAppear",
		"trigger": "event:/Monsters/DrillMon_Trigger",
		"rand": "event:/Monsters/DrillMon_Rand",
	},
	NestState.Species.SLIME:
	{
		"nest_appear": "event:/Nest/Slime_NestAppear",
		"trigger": "event:/Monsters/SlimeMon_Trigger",
		"rand": "event:/Monsters/SlimeMon_Rand",
	},
	NestState.Species.MUCUS:
	{
		"nest_appear": "event:/Nest/Mucus_NestAppear",
		"trigger": "event:/Monsters/MucusMon_Trigger",
		"rand": "event:/Monsters/MucusMon_Rand",
	},
}
const SUCK_UP_EVENT: String = "event:/Vacuum/SuckUp_Pop"
# Drill monsters play their own suck-up sound in place of SuckUp_Pop.
const DRILL_SUCK_UP_EVENT: String = "event:/Vacuum/DrillMon_SuckUp"
# Combo ladder: StageClear plays as each stage's burst shows (Combo_Stage 1-4);
# Break plays when a stage times out and the ladder drops back to stage 1.
const COMBO_CLEAR_EVENT: String = "event:/Candy/Combo_StageClear"
const COMBO_BREAK_EVENT: String = "event:/Candy/Combo_Break"
const COMBO_STAGE_PARAMETER: String = "Combo_Stage"
const CANDY_EVENT: String = "event:/Candy/Candy_Acquire"
const NET_CAST_EVENT: String = "event:/Net/Net_Cast"
const GOLDEN_EVENT: String = "event:/Candy/Golden_Mon"
# Plays with the new-nest presentation (slow-down, planet turn, close-up).
const NEW_NEST_EVENT: String = "event:/Nest/New_Nest"
const NET_CAPTURE_EVENT: String = "event:/Net/Net_Capture"
# Indexed by the nest's new level - 1; the last one is the upgrade that tames it.
const NEST_LEVEL_UP_EVENTS: PackedStringArray = [
	"event:/Nest/Nest_Lvlup_Stage01",
	"event:/Nest/Nest_Lvlup_Stage02",
	"event:/Nest/Nest_Lvlup_Stage03",
]
const CANDY_COMBO_PARAMETER: String = "Candy_Combo"
const CANDY_VALUE_PARAMETER: String = "Candy_Value"

# Random chatter per species: each monster on the surface adds this many calls
# per second on average, capped so a crowded planet does not turn into noise.
@export_range(0.0, 1.0, 0.01) var chatter_per_monster: float = 0.06
@export_range(0.1, 5.0, 0.1) var chatter_max_per_second: float = 1.2
@export_range(0.0, 2.0, 0.05) var chatter_min_gap_seconds: float = 0.25

# Spawn bursts: a nest can spit out up to ~18 monsters in one frame. Instead of
# stacking one Trigger per monster, each burst plays a few staggered voices, and
# a global cap keeps several nests bursting together from piling up.
@export_range(1, 8, 1) var burst_max_voices: int = 3
@export_range(0.0, 0.3, 0.01) var burst_stagger_seconds: float = 0.08
@export_range(1, 16, 1) var trigger_max_per_window: int = 4
@export_range(0.1, 2.0, 0.05) var trigger_window_seconds: float = 0.5
# No two Trigger voices start closer than this; a voice pushed back further
# than trigger_max_delay_seconds is dropped instead of arriving late.
@export_range(0.0, 0.2, 0.01) var trigger_min_gap_seconds: float = 0.05
@export_range(0.05, 1.0, 0.05) var trigger_max_delay_seconds: float = 0.3

# Candy payouts play Candy_Acquire once per monster caught, so a giant (worth
# several monsters) or a full net plays a run: the first right away, then gaps
# starting at candy_first_gap_seconds and shrinking by candy_gap_decay down to
# candy_min_gap_seconds, each voice candy_volume_decay quieter than the last.
# candy_max_voices caps the voices waiting at once across all payouts.
@export_range(1, 64, 1) var candy_max_voices: int = 12
# After SuckUp_Pop, the pipe's candy run starts this much later; net payouts
# have no pop and start right away.
@export_range(0.0, 1.0, 0.01) var candy_after_pop_seconds: float = 0.15
@export_range(0.02, 1.0, 0.01) var candy_first_gap_seconds: float = 0.15
@export_range(0.5, 1.0, 0.01) var candy_gap_decay: float = 0.85
@export_range(0.02, 0.5, 0.01) var candy_min_gap_seconds: float = 0.05
@export_range(0.5, 1.0, 0.01) var candy_volume_decay: float = 0.94
# Candy per monster that maps to the top of the Candy_Value parameter; the
# mapping is logarithmic, so 1 candy is the bottom and this value the top.
@export_range(2, 10000, 1) var candy_value_full: int = 250

var _ready_to_play: bool = false
# Checked apart from _ready_to_play so a bank without these newer events keeps
# the older monster sounds working.
var _net_events_ready: bool = false
var _nest_level_up_ready: bool = false
var _golden_ready: bool = false
var _drill_suck_ready: bool = false
var _combo_clear_ready: bool = false
var _combo_clear_has_stage: bool = false
var _combo_break_ready: bool = false
# Stage clears played so far; lets checks confirm the timing without audio.
var _combo_clear_count: int = 0
var _new_nest_ready: bool = false
var _new_nest: FmodEvent
var _chatter_cooldowns: Dictionary = {}
var _clock: float = 0.0
# species -> monsters spawned since the last frame.
var _pending_spawns: Dictionary = {}
# Staggered Trigger voices waiting to play: {"time": float, "species": int}.
var _scheduled_triggers: Array[Dictionary] = []
# Play times of recent Trigger voices, oldest first, for the global cap.
var _recent_triggers: Array[float] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Candy voices waiting to play: {"time", "combo", "value", "volume"}, by time.
var _scheduled_candy: Array[Dictionary] = []
# Candy_Value's range on Candy_Acquire; empty until FMOD defines the parameter.
var _candy_value_range: Vector2 = Vector2.ZERO
var _has_candy_value: bool = false
# Candy_Value may be authored as a global parameter; then it is set globally
# right before each candy voice instead of on the instance.
var _candy_value_global: bool = false


func _ready() -> void:
	var event_paths: PackedStringArray = [SUCK_UP_EVENT, CANDY_EVENT]
	for events: Dictionary in SPECIES_EVENTS.values():
		for event_path: String in events.values():
			event_paths.append(event_path)
	_ready_to_play = GameAudio.has_events(event_paths)
	_net_events_ready = GameAudio.has_events([NET_CAST_EVENT, NET_CAPTURE_EVENT])
	_nest_level_up_ready = GameAudio.has_events(NEST_LEVEL_UP_EVENTS)
	_golden_ready = GameAudio.has_events([GOLDEN_EVENT])
	_drill_suck_ready = GameAudio.has_events([DRILL_SUCK_UP_EVENT])
	_combo_clear_ready = GameAudio.has_events([COMBO_CLEAR_EVENT])
	_combo_clear_has_stage = (
		_combo_clear_ready and _has_parameter(COMBO_CLEAR_EVENT, COMBO_STAGE_PARAMETER)
	)
	_combo_break_ready = GameAudio.has_events([COMBO_BREAK_EVENT])
	_new_nest_ready = GameAudio.has_events([NEW_NEST_EVENT])
	if _ready_to_play:
		_find_candy_value_parameter()
	_rng.randomize()


func is_ready() -> bool:
	return _ready_to_play


func nest_appeared(species: int) -> void:
	_play_species(species, "nest_appear")


# A monster leaves its nest hole. Spawns are collected and played as bursts.
func monster_spawned(species: int) -> void:
	if _ready_to_play and SPECIES_EVENTS.has(species):
		_pending_spawns[species] = int(_pending_spawns.get(species, 0)) + 1


func _process(delta: float) -> void:
	_clock += delta
	if not _pending_spawns.is_empty():
		_schedule_spawn_bursts()
	if not _scheduled_triggers.is_empty():
		_play_due_triggers()
	if not _scheduled_candy.is_empty():
		_play_due_candy()


func _schedule_spawn_bursts() -> void:
	for species: int in _pending_spawns:
		var voices: int = mini(int(_pending_spawns[species]), burst_max_voices)
		for index: int in range(voices):
			# Slight jitter keeps a burst from sounding like a metronome.
			var jitter: float = (
				0.0 if index == 0 else _rng.randf_range(0.0, burst_stagger_seconds * 0.3)
			)
			_scheduled_triggers.append(
				{"time": _clock + index * burst_stagger_seconds + jitter, "species": species}
			)
	_pending_spawns.clear()


func _play_due_triggers() -> void:
	while (
		not _recent_triggers.is_empty()
		and _clock - _recent_triggers[0] >= trigger_window_seconds
	):
		_recent_triggers.pop_front()
	var waiting: Array[Dictionary] = []
	for trigger: Dictionary in _scheduled_triggers:
		var due: float = float(trigger["time"])
		if due > _clock:
			waiting.append(trigger)
		elif _recent_triggers.size() >= trigger_max_per_window:
			continue  # Over the global cap: drop rather than pile up later.
		elif (
			not _recent_triggers.is_empty()
			and _clock - _recent_triggers.back() < trigger_min_gap_seconds
		):
			if _clock - due < trigger_max_delay_seconds:
				waiting.append(trigger)
		else:
			_recent_triggers.append(_clock)
			_play_species(int(trigger["species"]), "trigger")
	_scheduled_triggers = waiting


# A monster was sucked up by the pipe: its suck-up sound now, its candy run
# shortly after. combo is the Candy_Combo pitch (0-1). A giant counts as the
# number of monsters it is worth.
func monster_sucked(combo: float, candy: int, monsters: int = 1, drill: bool = false) -> void:
	if not _ready_to_play:
		return
	GameAudio.play(DRILL_SUCK_UP_EVENT if drill and _drill_suck_ready else SUCK_UP_EVENT)
	_queue_candy(monsters, candy, clampf(combo, 0.0, 1.0), candy_after_pop_seconds)


func combo_stage_cleared(stage: int) -> void:
	if not _combo_clear_ready:
		return
	var parameters: Dictionary = {}
	if _combo_clear_has_stage:
		parameters[COMBO_STAGE_PARAMETER] = stage
	GameAudio.play(COMBO_CLEAR_EVENT, parameters)
	_combo_clear_count += 1


func combo_broken() -> void:
	if _combo_break_ready:
		GameAudio.play(COMBO_BREAK_EVENT)


# A net catch paid out candy. The net never builds a combo.
func candy_from_net(candy: int, monsters: int) -> void:
	if _ready_to_play:
		_queue_candy(monsters, candy, 0.0)


func _queue_candy(monsters: int, candy: int, combo: float, delay: float = 0.0) -> void:
	if candy <= 0 or monsters <= 0:
		return
	var voices: int = mini(monsters, candy_max_voices - _scheduled_candy.size())
	var value: float = _candy_value(float(candy) / monsters)
	var time: float = _clock + delay
	var gap: float = candy_first_gap_seconds
	var volume: float = 1.0
	for index: int in range(voices):
		_scheduled_candy.append({"time": time, "combo": combo, "value": value, "volume": volume})
		time += gap
		gap = maxf(candy_min_gap_seconds, gap * candy_gap_decay)
		volume *= candy_volume_decay
	_scheduled_candy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] < b["time"])
	_play_due_candy()


func _play_due_candy() -> void:
	while not _scheduled_candy.is_empty() and float(_scheduled_candy[0]["time"]) <= _clock:
		var voice: Dictionary = _scheduled_candy.pop_front()
		var parameters: Dictionary = {CANDY_COMBO_PARAMETER: voice["combo"]}
		if _candy_value_global:
			GameAudio.set_global(CANDY_VALUE_PARAMETER, voice["value"])
		elif _has_candy_value:
			parameters[CANDY_VALUE_PARAMETER] = voice["value"]
		GameAudio.play(CANDY_EVENT, parameters, float(voice["volume"]))


# Logarithmic: 1 candy per monster is the bottom of the range, candy_value_full
# and above the top.
func _candy_value(candy_per_monster: float) -> float:
	var amount: float = clampf(
		log(maxf(candy_per_monster, 1.0)) / log(float(candy_value_full)), 0.0, 1.0
	)
	return lerpf(_candy_value_range.x, _candy_value_range.y, amount)


func _has_parameter(event_path: String, parameter_name: String) -> bool:
	var description: FmodEventDescription = FmodServer.get_event(
		GameAudio.resolve_event_path(event_path)
	)
	if description == null:
		return false
	for index: int in range(description.get_parameter_count()):
		if description.get_parameter_by_index(index).get_name() == parameter_name:
			return true
	return false


func _find_candy_value_parameter() -> void:
	for global: Dictionary in FmodServer.get_global_parameter_desc_list():
		if global["name"] == CANDY_VALUE_PARAMETER:
			_candy_value_range = Vector2(global["minimum"], global["maximum"])
			_candy_value_global = true
			return
	var description: FmodEventDescription = FmodServer.get_event(
		GameAudio.resolve_event_path(CANDY_EVENT)
	)
	if description == null:
		return
	for index: int in range(description.get_parameter_count()):
		var parameter: FmodParameterDescription = description.get_parameter_by_index(index)
		if parameter.get_name() == CANDY_VALUE_PARAMETER:
			_candy_value_range = Vector2(parameter.get_minimum(), parameter.get_maximum())
			_has_candy_value = true
			return


# The new-nest presentation began: the warning bubble shows and time slows.
func new_nest_discovered() -> void:
	if _new_nest_ready:
		stop_new_nest()
		_new_nest = GameAudio.start_event(NEW_NEST_EVENT)


# Cuts the presentation sound short, e.g. on restart; it otherwise plays out.
func stop_new_nest() -> void:
	if _new_nest != null and _new_nest.is_valid():
		_new_nest.stop(FmodServer.FMOD_STUDIO_STOP_ALLOWFADEOUT)
	_new_nest = null


func _exit_tree() -> void:
	stop_new_nest()


# A golden (high-value) monster was collected; once per pipe capture or net.
func golden_collected() -> void:
	if _golden_ready:
		GameAudio.play(GOLDEN_EVENT)


func net_cast() -> void:
	if _net_events_ready:
		GameAudio.play(NET_CAST_EVENT)


# The net closed on at least one monster.
func net_captured() -> void:
	if _net_events_ready:
		GameAudio.play(NET_CAPTURE_EVENT)


# Returns false when the event is unavailable, so the caller can fall back.
func nest_leveled_up(level: int) -> bool:
	if not _nest_level_up_ready or level < 1 or level > NEST_LEVEL_UP_EVENTS.size():
		return false
	GameAudio.play(NEST_LEVEL_UP_EVENTS[level - 1])
	return true


# population: species -> number of monsters currently roaming the surface.
func update_chatter(delta: float, population: Dictionary) -> void:
	if not _ready_to_play or delta <= 0.0:
		return
	for species: int in SPECIES_EVENTS:
		var cooldown: float = maxf(0.0, float(_chatter_cooldowns.get(species, 0.0)) - delta)
		_chatter_cooldowns[species] = cooldown
		var count: int = int(population.get(species, 0))
		if count <= 0 or cooldown > 0.0:
			continue
		var rate: float = minf(chatter_per_monster * count, chatter_max_per_second)
		if _rng.randf() < rate * delta:
			_chatter_cooldowns[species] = chatter_min_gap_seconds
			_play_species(species, "rand")


func _play_species(species: int, kind: String) -> void:
	if not _ready_to_play or not SPECIES_EVENTS.has(species):
		return
	GameAudio.play(SPECIES_EVENTS[species][kind])
