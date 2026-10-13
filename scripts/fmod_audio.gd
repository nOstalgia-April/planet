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
var _effects_elapsed: float = 0.0
var _effect_descriptions: Array[FmodEventDescription] = []
var _master_bus: FmodBus
var _editor_muted: bool = false

# Holding the references keeps the banks loaded; dropping them unloads.
var _banks: Array[FmodBank] = []
var _music: FmodEvent
var _music_path: String = ""
var _music_volume: float = 0.0
# Previous tracks still fading out: FmodEvent -> current volume.
var _fading_out: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_editor_muted = "--debug-mute-audio" in OS.get_cmdline_args()
	if EngineDebugger.is_active():
		EngineDebugger.register_message_capture(&"planet_audio", _capture_editor_message)
		EngineDebugger.send_message("planet_audio:ready", [])
	GamePreferences.changed.connect(_apply_preferences)
	_apply_preferences()
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
	_master_bus = FmodServer.get_bus("bus:/")
	for bank: FmodBank in _banks:
		for description: FmodEventDescription in bank.get_description_list():
			if not description.get_path().begins_with("event:/Mx_"):
				_effect_descriptions.append(description)
	_apply_preferences()


# Stop the music before dropping the banks at quit; dropping them unloads every event.
func _exit_tree() -> void:
	if EngineDebugger.is_active():
		EngineDebugger.unregister_message_capture(&"planet_audio")
	stop_music()
	for instance: FmodEvent in _fading_out:
		if instance.is_valid():
			instance.stop(FmodServer.FMOD_STUDIO_STOP_IMMEDIATE)
			instance.release()
	_fading_out.clear()
	_effect_descriptions.clear()
	_master_bus = null
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
	instance.set_volume(_effects_gain())
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
		instance.set_volume(_effects_gain())
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
	return GamePreferences.music_volume if GamePreferences.audio_enabled else 0.0


func _effects_gain() -> float:
	return GamePreferences.effects_volume if GamePreferences.audio_enabled else 0.0


# Editor mute is temporary and independent of the player's saved audio switch.
func set_editor_muted(muted: bool) -> void:
	_editor_muted = muted
	_apply_master_mute()


func _capture_editor_message(message: String, data: Array) -> bool:
	if message != "set_editor_muted":
		return false
	if data.size() != 1 or not data[0] is bool:
		return false
	set_editor_muted(data[0])
	return true


func _apply_master_mute() -> void:
	var muted: bool = _editor_muted or not GamePreferences.audio_enabled
	if _master_bus != null:
		_master_bus.set_mute(muted)
	AudioServer.set_bus_mute(0, muted or is_zero_approx(GamePreferences.effects_volume))


func _apply_preferences() -> void:
	if _music != null and _music.is_valid():
		_music.set_volume(_music_volume * _music_gain())
	for instance: FmodEvent in _fading_out:
		if instance.is_valid():
			instance.set_volume(float(_fading_out[instance]) * _music_gain())
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(GamePreferences.effects_volume, 0.0001)))
	_apply_master_mute()
	_apply_effects_volume()


func _apply_effects_volume() -> void:
	# FMOD can spawn nested events (Vacuum_Loop) without a game-side play call.
	for description: FmodEventDescription in _effect_descriptions:
		if description.get_instance_count() == 0:
			continue
		for instance: FmodEvent in description.get_instance_list():
			instance.set_volume(_effects_gain())
