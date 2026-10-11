extends Node

# Autoload "GameAudio": keeps the FMOD banks loaded for the whole session, so
# sounds survive scene changes, plays fire-and-forget events and one looping
# music track with crossfades. Every caller degrades to silence when banks or
# events are missing.

const BANK_ROOT: String = "res://bank/Desktop"
const BANK_NAMES: PackedStringArray = ["Master.strings.bank", "Master.bank", "ProjectVacuum.bank"]

const MAX_FADE_STEP: float = 1.0 / 30.0

@export_range(0.0, 10.0, 0.05) var music_fade_in_seconds: float = 0.3
@export_range(0.0, 10.0, 0.05) var music_fade_out_seconds: float = 0.3

var banks_loaded: bool = false

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


# Stop the music before dropping the banks at quit; dropping them unloads every event.
func _exit_tree() -> void:
	stop_music()
	for instance: FmodEvent in _fading_out:
		if instance.is_valid():
			instance.stop(FmodServer.FMOD_STUDIO_STOP_IMMEDIATE)
			instance.release()
	_fading_out.clear()
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
	instance.start()
	instance.release()


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


func _process(delta: float) -> void:
	# A blocking scene load arrives as one huge delta; cap it so fades stay audible.
	var step: float = minf(delta, MAX_FADE_STEP)
	if _music != null and _music_volume < 1.0:
		_music_volume = minf(1.0, _music_volume + step / maxf(music_fade_in_seconds, 0.01))
		if _music.is_valid():
			_music.set_volume(_music_volume)
	for instance: FmodEvent in _fading_out.keys():
		var volume: float = float(_fading_out[instance]) - step / maxf(music_fade_out_seconds, 0.01)
		if not instance.is_valid():
			_fading_out.erase(instance)
		elif volume <= 0.0:
			instance.stop(FmodServer.FMOD_STUDIO_STOP_IMMEDIATE)
			instance.release()
			_fading_out.erase(instance)
		else:
			instance.set_volume(volume)
			_fading_out[instance] = volume
