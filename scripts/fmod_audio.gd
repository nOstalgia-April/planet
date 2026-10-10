extends Node

# Autoload "GameAudio": keeps the FMOD banks loaded for the whole session, so
# sounds survive scene changes, plays fire-and-forget events and one looping
# music track. Every caller degrades to silence when banks or events are missing.

const BANK_ROOT: String = "res://bank/Desktop"
const BANK_NAMES: PackedStringArray = ["Master.strings.bank", "Master.bank", "ProjectVacuum.bank"]

var banks_loaded: bool = false

# Holding the references keeps the banks loaded; dropping them unloads.
var _banks: Array[FmodBank] = []
var _music: FmodEvent
var _music_path: String = ""


func _ready() -> void:
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


# Starts a looping music event, replacing (with its FMOD fade-out) any other
# music. Asking for the track that is already playing keeps it going.
func play_music(event_path: String) -> void:
	if event_path == _music_path and _music != null and _music.is_valid():
		return
	stop_music()
	if not has_events([event_path]):
		return
	_music = FmodServer.create_event_instance(event_path)
	if _music != null:
		_music.start()
		_music_path = event_path


func stop_music() -> void:
	if _music != null and _music.is_valid():
		_music.stop(FmodServer.FMOD_STUDIO_STOP_ALLOWFADEOUT)
		_music.release()
	_music = null
	_music_path = ""
