extends Node

# FMOD events for monsters and candy collection. Drill events exist in the bank
# but the demo has no drill species yet; add a row to SPECIES_EVENTS when it does.

const SPECIES_EVENTS: Dictionary = {
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
const CANDY_COMBO_PARAMETER: String = "Candy_Combo"
const COMBO_FOR_MAX_PITCH: int = 10

# Random chatter per species: each monster on the surface adds this many calls
# per second on average, capped so a crowded planet does not turn into noise.
@export_range(0.0, 1.0, 0.01) var chatter_per_monster: float = 0.06
@export_range(0.1, 5.0, 0.1) var chatter_max_per_second: float = 1.2
@export_range(0.0, 2.0, 0.05) var chatter_min_gap_seconds: float = 0.25

var _ready_to_play: bool = false
var _chatter_cooldowns: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	var event_paths: PackedStringArray = [SUCK_UP_EVENT, CANDY_EVENT]
	for events: Dictionary in SPECIES_EVENTS.values():
		for event_path: String in events.values():
			event_paths.append(event_path)
	_ready_to_play = GameAudio.has_events(event_paths)
	_rng.randomize()


func is_ready() -> bool:
	return _ready_to_play


func nest_appeared(species: int) -> void:
	_play_species(species, "nest_appear")


# A monster leaves its nest hole.
func monster_spawned(species: int) -> void:
	_play_species(species, "trigger")


# A monster was sucked up by the pipe.
func monster_sucked() -> void:
	if _ready_to_play:
		GameAudio.play(SUCK_UP_EVENT)


# Candy reached the counter; pitch rises with the combo and peaks at 10.
func candy_acquired(combo_count: int) -> void:
	if not _ready_to_play:
		return
	var combo: float = clampf(float(combo_count) / COMBO_FOR_MAX_PITCH, 0.0, 1.0)
	GameAudio.play(CANDY_EVENT, {CANDY_COMBO_PARAMETER: combo})


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
