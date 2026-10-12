extends Node

# FMOD events for monsters and candy collection.

const SPECIES_EVENTS: Dictionary = {
	NestState.Species.DRILL:
	{
		"nest_appear": "event:/Monsters/Drill_NestAppear",
		"trigger": "event:/Monsters/DrillMon_Trigger",
		"rand": "event:/Monsters/DrillMon_Rand",
	},
	NestState.Species.SLIME:
	{
		"nest_appear": "event:/Monsters/Slime_NestAppear",
		"trigger": "event:/Monsters/SlimeMon_Trigger",
		"rand": "event:/Monsters/SlimeMon_Rand",
	},
	NestState.Species.MUCUS:
	{
		"nest_appear": "event:/Monsters/Mucus_NestAppear",
		"trigger": "event:/Monsters/MucusMon_Trigger",
		"rand": "event:/Monsters/MucusMon_Rand",
	},
}
const SUCK_UP_EVENT: String = "event:/SuckUp_Pop"
const CANDY_EVENT: String = "event:/Candy_Acquire"
const NET_CANDY_EVENT: String = "event:/Candy_Nest"
const CANDY_COMBO_PARAMETER: String = "Candy_Combo"
const COMBO_FOR_MAX_PITCH: int = 10

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

var _ready_to_play: bool = false
var _chatter_cooldowns: Dictionary = {}
var _clock: float = 0.0
# species -> monsters spawned since the last frame.
var _pending_spawns: Dictionary = {}
# Staggered Trigger voices waiting to play: {"time": float, "species": int}.
var _scheduled_triggers: Array[Dictionary] = []
# Play times of recent Trigger voices, oldest first, for the global cap.
var _recent_triggers: Array[float] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	var event_paths: PackedStringArray = [SUCK_UP_EVENT, CANDY_EVENT, NET_CANDY_EVENT]
	for events: Dictionary in SPECIES_EVENTS.values():
		for event_path: String in events.values():
			event_paths.append(event_path)
	_ready_to_play = GameAudio.has_events(event_paths)
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


# A monster was sucked up by the pipe: the pop and its candy sound together.
# The candy pitch rises with the combo and peaks at 10.
func monster_sucked(combo_count: int) -> void:
	if not _ready_to_play:
		return
	GameAudio.play(SUCK_UP_EVENT)
	var combo: float = clampf(float(combo_count) / COMBO_FOR_MAX_PITCH, 0.0, 1.0)
	GameAudio.play(CANDY_EVENT, {CANDY_COMBO_PARAMETER: combo})


# A net catch paid out candy.
func candy_from_net() -> void:
	if _ready_to_play:
		GameAudio.play(NET_CANDY_EVENT)


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
