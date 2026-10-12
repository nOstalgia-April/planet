extends Node

# Autoload "GameAudio": keeps the FMOD banks loaded for the whole session, so
# sounds survive scene changes, plays fire-and-forget events and one looping
# music track with crossfades. Every caller degrades to silence when banks or
# events are missing.

const BANK_ROOT: String = "res://bank/Desktop"
const BANK_NAMES: PackedStringArray = ["Master.strings.bank", "Master.bank", "ProjectVacuum.bank"]

const MAX_FADE_STEP: float = 1.0 / 30.0
# Near-view gameplay sounds. They keep running in the planet overview but are
# silenced there; music, UI and Earth_Rotate stay audible in both views.
const NEAR_VIEW_PREFIXES: PackedStringArray = [
	"event:/Monsters/",
	"event:/Vacuum/",
	"event:/Slime_",
	"event:/SuckUp_Pop",
	"event:/Candy_",
	"event:/Drill_Crawl",
]

@export_range(0.0, 10.0, 0.05) var music_fade_in_seconds: float = 0.3
@export_range(0.0, 10.0, 0.05) var music_fade_out_seconds: float = 0.3

var banks_loaded: bool = false
var _effects_elapsed: float = 0.0
var _effect_descriptions: Array[FmodEventDescription] = []
# Parallel to _effect_descriptions: whether each one is a near-view sound.
var _effect_is_near_view: Array[bool] = []
# 1 in the near view, 0 in the overview; follows the camera transition.
var _near_view_gain: float = 1.0

# Holding the references keeps the banks loaded; dropping them unloads.
var _banks: Array[FmodBank] = []
var _music: FmodEvent
var _music_path: String = ""
var _music_volume: float = 0.0
# Previous tracks still fading out: FmodEvent -> current volume.
var _fading_out: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bank_name: String in BANK_NAMES:
		if not FileAccess.file_exists(BANK_ROOT.path_join(bank_name)):
			push_warning("FMOD bank missing, FMOD audio disabled: %s" % bank_name)
			return
	for bank_name: String in BANK_NAMES:
		_banks.append(
			FmodServer.load_bank(
				BANK_ROOT.path_join(bank_name), FmodServer.FMOD_STUDIO_LOAD_BANK_NORMAL
			)
		)
	banks_loaded = true
	for bank: FmodBank in _banks:
		for description: FmodEventDescription in bank.get_description_list():
			var path: String = description.get_path()
			if not path.begins_with("event:/Mx_"):
				_effect_descriptions.append(description)
				_effect_is_near_view.append(_is_near_view(path))
	GamePreferences.changed.connect(_apply_preferences)
	_apply_preferences()


# Stop the music before dropping the banks at quit; dropping them unloads every event.
func _exit_tree() -> void:
	stop_music()
	for instance: FmodEvent in _fading_out:
		if instance.is_valid():
			instance.stop(FmodServer.FMOD_STUDIO_STOP_IMMEDIATE)
			instance.release()
	_fading_out.clear()
	_effect_descriptions.clear()
	_effect_is_near_view.clear()
	_banks.clear()
	banks_loaded = false


# Returns true only when every listed event exists in the loaded banks.
func has_events(event_paths: PackedStringArray) -> bool:
	if not banks_loaded:
		return false
	for event_path: String in event_paths:
		if not FmodServer.check_event_path(event_path):
			push_warning("FMOD event missing: %s" % event_path)
			return false
	return true


# Plays a one-shot event and pushes it to FMOD right away, so it sounds even if
# the main thread is about to block (for example on a scene change).
func play_now(event_path: String) -> void:
	play(event_path)
	if banks_loaded:
		FmodServer.update()


# Plays a one-shot event, optionally setting its local parameters first.
func play(event_path: String, parameters: Dictionary = {}) -> void:
	if not banks_loaded:
		return
	var instance: FmodEvent = FmodServer.create_event_instance(event_path)
	if instance == null:
		return
	for parameter_name: String in parameters:
		instance.set_parameter_by_name(parameter_name, float(parameters[parameter_name]))
	instance.set_volume(_effects_gain(_is_near_view(event_path)))
	instance.start()
	instance.release()


# Called every frame by the game scene with its near/overview blend. Silent
# near-view events still play, so their FMOD logic (commands, parameters) runs.
func set_near_view_gain(gain: float) -> void:
	gain = clampf(gain, 0.0, 1.0)
	if is_equal_approx(gain, _near_view_gain):
		return
	_near_view_gain = gain
	_apply_effects_volume()


func set_global(parameter_name: String, value: float) -> void:
	if banks_loaded:
		FmodServer.set_global_parameter_by_name(parameter_name, value)


# Starts a looping sound effect; the caller keeps the instance and stops it
# with stop_loop. Returns null when FMOD audio is unavailable.
func start_loop(event_path: String) -> FmodEvent:
	if not banks_loaded:
		return null
	var instance: FmodEvent = FmodServer.create_event_instance(event_path)
	if instance != null:
		instance.set_volume(_effects_gain(_is_near_view(event_path)))
		instance.start()
	return instance


# Stops a loop with its FMOD fade-out (AHDSR release) and frees it afterwards.
func stop_loop(instance: FmodEvent) -> void:
	if instance != null and instance.is_valid():
		instance.stop(FmodServer.FMOD_STUDIO_STOP_ALLOWFADEOUT)
		instance.release()


# Starts a looping music event and crossfades from any other music. Asking for
# the track that is already playing keeps it going.
func play_music(event_path: String) -> void:
	if event_path == _music_path and _music != null and _music.is_valid():
		return
	stop_music()
	if not has_events([event_path]):
		return
	_music = FmodServer.create_event_instance(event_path)
	if _music == null:
		return
	_music.set_volume(0.0)
	_music.start()
	_music_path = event_path
	_music_volume = 0.0


# Fades the current music out; it stops once silent.
func stop_music() -> void:
	if _music != null and _music.is_valid():
		_fading_out[_music] = _music_volume
	_music = null
	_music_path = ""


## Returns -1 when this track is unavailable. FMOD owns looping, pausing and seeking.
func get_music_position_seconds(event_path: String) -> float:
	if _music_path != event_path or _music == null or not _music.is_valid():
		return -1.0
	return float(_music.get_timeline_position()) / 1000.0


func _process(delta: float) -> void:
	_effects_elapsed += delta
	if _effects_elapsed >= 0.1:
		_effects_elapsed = 0.0
		_apply_effects_volume()
	# A blocking scene load arrives as one huge delta; cap it so fades stay audible.
	var step: float = minf(delta, MAX_FADE_STEP)
	if _music != null and _music_volume < 1.0:
		_music_volume = minf(1.0, _music_volume + step / maxf(music_fade_in_seconds, 0.01))
		if _music.is_valid():
			_music.set_volume(_music_volume * _music_gain())
	for instance: FmodEvent in _fading_out.keys():
		var volume: float = float(_fading_out[instance]) - step / maxf(music_fade_out_seconds, 0.01)
		if not instance.is_valid():
			_fading_out.erase(instance)
		elif volume <= 0.0:
			instance.stop(FmodServer.FMOD_STUDIO_STOP_IMMEDIATE)
			instance.release()
			_fading_out.erase(instance)
		else:
			instance.set_volume(volume * _music_gain())
			_fading_out[instance] = volume


func _music_gain() -> float:
	return GamePreferences.music_volume if GamePreferences.music_enabled else 0.0


func _apply_preferences() -> void:
	if _music != null and _music.is_valid():
		_music.set_volume(_music_volume * _music_gain())
	for instance: FmodEvent in _fading_out:
		if instance.is_valid():
			instance.set_volume(float(_fading_out[instance]) * _music_gain())
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(GamePreferences.effects_volume, 0.0001)))
	AudioServer.set_bus_mute(0, is_zero_approx(GamePreferences.effects_volume))
	_apply_effects_volume()


func _apply_effects_volume() -> void:
	# FMOD can spawn nested events (Vacuum_Loop) without a game-side play call.
	for index: int in range(_effect_descriptions.size()):
		var description: FmodEventDescription = _effect_descriptions[index]
		if description.get_instance_count() == 0:
			continue
		var gain: float = _effects_gain(_effect_is_near_view[index])
		for instance: FmodEvent in description.get_instance_list():
			instance.set_volume(gain)


func _effects_gain(near_view: bool) -> float:
	return GamePreferences.effects_volume * (_near_view_gain if near_view else 1.0)


func _is_near_view(event_path: String) -> bool:
	for prefix: String in NEAR_VIEW_PREFIXES:
		if event_path.begins_with(prefix):
			return true
	return false
