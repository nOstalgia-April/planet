extends Node

# Autoload "GameAudio": keeps the FMOD banks loaded for the whole session, so
# sounds survive scene changes, plays fire-and-forget events and one looping
# music track with crossfades. Every caller degrades to silence when banks or
# events are missing.

const BANK_ROOT: String = "res://bank/Desktop"
const BANK_NAMES: PackedStringArray = ["Master.strings.bank", "Master.bank", "ProjectVacuum.bank"]

const MAX_FADE_STEP: float = 1.0 / 30.0
const MUSIC_DUCK_PARAMETER: String = "Music_Duck"
# Global 0-1, held at 1 while a menu pauses the game (settings, technology
# page); FMOD maps it to a low-pass on the music.
const MUSIC_MENU_PARAMETER: String = "Music_Menu"
# Safety net: music held back by a transition starts anyway after this long.
const TRANSITION_TIMEOUT_SECONDS: float = 15.0
# Near-view gameplay sounds. They keep running in the planet overview but are
# silenced there; music, UI and Earth_Rotate stay audible in both views.
# Vacuum_Loop is started inside FMOD by Vacuum_On's command instrument, so it
# is not listed among its event's instances and cannot be paused one by one.
# A pause mutes this bus instead, silencing it with the other gameplay sounds.
const GAMEPLAY_BUS: String = "bus:/SFX/Gameplay"
# Command-only events that keep running through a pause: Vacuum_Off, played as
# the pause turns the vacuum off, stops Vacuum_Loop under the muted bus.
const PAUSE_EXEMPT_EVENTS: PackedStringArray = ["Vacuum_Off"]
const NEAR_VIEW_PREFIXES: PackedStringArray = [
	"event:/Monsters/",
	"event:/Vacuum/",
	"event:/Candy/",
	"event:/Nest/Slime_NestAppear",
	"event:/Nest/Mucus_NestAppear",
	"event:/Nest/Drill_NestAppear",
	"event:/Net/",
	"event:/Drill_Crawl",
	"event:/Drill_OutofDirt",
]

@export_range(0.0, 10.0, 0.05) var music_fade_in_seconds: float = 0.3
@export_range(0.0, 10.0, 0.05) var music_fade_out_seconds: float = 0.3
# Music after a transition is started this long before the transition's file
# ends. GameStart_Transition fades below -40 dB from about 2.4 s of its 3.43 s,
# so the music enters there (overlapping only that near-silent tail); the value
# also absorbs FMOD's start-up delay (~0.21 s measured).
@export_range(0.0, 3.0, 0.01) var transition_music_lead_seconds: float = 1.2
# Music_Duck (global, 0-1) dips the music during presentations; FMOD maps it to
# volume and a low-pass. The game eases it over this many seconds each way.
@export_range(0.0, 3.0, 0.05) var music_duck_fade_seconds: float = 0.4
@export_range(0.0, 3.0, 0.05) var music_menu_fade_seconds: float = 0.3

var banks_loaded: bool = false
# Names of the global parameters defined by the loaded banks.
var _global_parameters: Dictionary = {}
# Event name -> every loaded path with that name, so a path whose folder moved
# in FMOD still finds its event (see resolve_event_path).
var _paths_by_name: Dictionary = {}
# Requested path -> path actually used, so each lookup and warning runs once.
var _resolved_paths: Dictionary = {}
var _effects_elapsed: float = 0.0
var _music_ducked: bool = false
var _music_duck: float = 0.0
var _music_menu: float = 0.0
var _effect_descriptions: Array[FmodEventDescription] = []
# Parallel to _effect_descriptions: whether each one is a near-view sound.
var _effect_is_near_view: Array[bool] = []
# 1 in the near view, 0 in the overview; follows the camera transition.
var _near_view_gain: float = 1.0
var _master_bus: FmodBus
var _editor_muted: bool = false
# A paused game (settings, technology page, pause button) freezes gameplay
# sounds in place; music keeps playing under Music_Menu, and UI sounds too.
var _game_paused: bool = false
# Parallel to _effect_descriptions: UI sounds (and PAUSE_EXEMPT_EVENTS) keep
# playing while gameplay freezes.
var _effect_is_ui: Array[bool] = []
var _gameplay_bus: FmodBus

# Holding the references keeps the banks loaded; dropping them unloads.
var _banks: Array[FmodBank] = []
var _music: FmodEvent
var _music_path: String = ""
var _music_volume: float = 0.0
# A transition sound between two music tracks. Music requested while it plays
# starts paused in _pending_music, so its streams are already open, and is
# unpaused at full volume as the transition ends.
var _transition: FmodEvent
var _transition_elapsed: float = 0.0
var _transition_length: float = 0.0
# Seconds before the transition's end at which held music starts.
var _transition_lead: float = 0.0
# False for a sound adopted with hold_music_for, which its caller already released.
var _transition_owned: bool = false
var _pending_music: FmodEvent
var _pending_music_path: String = ""
# Previous tracks still fading out: FmodEvent -> current volume.
var _fading_out: Dictionary = {}
# One-shots played below the effects volume, as [FmodEvent, scale, near view]
# entries, so the periodic volume refresh keeps their scale.
var _scaled_effects: Array[Array] = []


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
	if FmodServer.check_bus_path(GAMEPLAY_BUS):
		_gameplay_bus = FmodServer.get_bus(GAMEPLAY_BUS)
	else:
		push_warning("FMOD bus missing, pauses cannot silence Vacuum_Loop: " + GAMEPLAY_BUS)
	for description: Dictionary in FmodServer.get_global_parameter_desc_list():
		_global_parameters[description["name"]] = true
	for bank: FmodBank in _banks:
		for description: FmodEventDescription in bank.get_description_list():
			var path: String = description.get_path()
			if not _paths_by_name.has(path.get_file()):
				_paths_by_name[path.get_file()] = PackedStringArray()
			_paths_by_name[path.get_file()].append(path)
			if not path.get_file().begins_with("Mx_"):
				_effect_descriptions.append(description)
				_effect_is_near_view.append(_is_near_view(path))
				_effect_is_ui.append(
					path.begins_with("event:/UI/") or path.get_file() in PAUSE_EXEMPT_EVENTS
				)
	_apply_preferences()


# Stop the music before dropping the banks at quit; dropping them unloads every event.
func _exit_tree() -> void:
	if EngineDebugger.is_active():
		EngineDebugger.unregister_message_capture(&"planet_audio")
	stop_music()
	_end_transition()
	_discard_pending_music()
	for instance: FmodEvent in _fading_out:
		if instance.is_valid():
			instance.stop(FmodServer.FMOD_STUDIO_STOP_IMMEDIATE)
			instance.release()
	_fading_out.clear()
	_scaled_effects.clear()
	_effect_descriptions.clear()
	_effect_is_near_view.clear()
	_effect_is_ui.clear()
	_master_bus = null
	_gameplay_bus = null
	_banks.clear()
	banks_loaded = false


# The path to use for event_path: itself when it exists, otherwise the one
# loaded event with the same name, wherever FMOD's folders moved it. A name
# found in several folders is ambiguous and left unresolved.
func resolve_event_path(event_path: String) -> String:
	if not banks_loaded:
		return event_path
	if _resolved_paths.has(event_path):
		return _resolved_paths[event_path]
	var resolved: String = event_path
	if not FmodServer.check_event_path(event_path):
		var matches: PackedStringArray = _paths_by_name.get(
			event_path.get_file(), PackedStringArray()
		)
		if matches.size() == 1:
			resolved = matches[0]
			push_warning("FMOD event %s moved; using %s" % [event_path, resolved])
		elif matches.size() > 1:
			push_warning("FMOD event name is ambiguous: %s in %s" % [event_path, matches])
	_resolved_paths[event_path] = resolved
	return resolved


# Returns true only when every listed event exists in the loaded banks.
func has_events(event_paths: PackedStringArray) -> bool:
	if not banks_loaded:
		return false
	for event_path: String in event_paths:
		if not FmodServer.check_event_path(resolve_event_path(event_path)):
			push_warning("FMOD event missing: %s" % event_path)
			return false
	return true


# Plays a one-shot event and pushes it to FMOD right away, so it sounds even if
# the main thread is about to block (for example on a scene change).
func play_now(event_path: String) -> void:
	play(event_path)
	if banks_loaded:
		FmodServer.update()


# Plays a one-shot event and returns its instance so the caller can watch its
# timeline (for example to sync visuals). The instance is already released: it
# finishes on its own, including its tail, even across scene changes.
func start_event(event_path: String) -> FmodEvent:
	event_path = resolve_event_path(event_path)
	if not banks_loaded or not FmodServer.check_event_path(event_path):
		return null
	var instance: FmodEvent = FmodServer.create_event_instance(event_path)
	if instance == null:
		return null
	instance.set_volume(_effects_gain(_is_near_view(event_path)))
	instance.start()
	instance.release()
	FmodServer.update()
	return instance


# Plays a one-shot event, optionally setting its global or local parameters first.
# volume_scale lowers this one instance below the effects volume.
func play(event_path: String, parameters: Dictionary = {}, volume_scale: float = 1.0) -> void:
	if not banks_loaded:
		return
	event_path = resolve_event_path(event_path)
	var instance: FmodEvent = FmodServer.create_event_instance(event_path)
	if instance == null:
		return
	for parameter_name: String in parameters:
		if _global_parameters.has(parameter_name):
			set_global(parameter_name, float(parameters[parameter_name]))
		else:
			instance.set_parameter_by_name(parameter_name, float(parameters[parameter_name]))
	instance.set_volume(_effects_gain(_is_near_view(event_path)) * volume_scale)
	instance.start()
	instance.release()
	if volume_scale < 1.0:
		_scaled_effects.append([instance, volume_scale, _is_near_view(event_path)])


# Called every frame by the game scene with the camera's near/overview blend
# (1 = near view, 0 = overview) to fade near-view sound effects. Silent
# near-view events still play, so their FMOD logic (commands, parameters) runs.
func set_near_view_gain(gain: float) -> void:
	gain = clampf(gain, 0.0, 1.0)
	if is_equal_approx(gain, _near_view_gain):
		return
	_near_view_gain = gain
	_apply_effects_volume()


# Sets a music parameter whether FMOD defines it as global or as local to the
# event. A local one is only set while event_path is the track playing, since
# other music events may not define it.
func set_music_parameter(event_path: String, parameter_name: String, value: float) -> void:
	event_path = resolve_event_path(event_path)
	if _global_parameters.has(parameter_name):
		set_global(parameter_name, value)
	elif event_path == _music_path and _music != null and _music.is_valid():
		_music.set_parameter_by_name(parameter_name, value)


func set_global(parameter_name: String, value: float) -> void:
	if banks_loaded:
		FmodServer.set_global_parameter_by_name(parameter_name, value)


# Starts a looping sound effect; the caller keeps the instance and stops it
# with stop_loop. Returns null when FMOD audio is unavailable.
func start_loop(event_path: String) -> FmodEvent:
	if not banks_loaded:
		return null
	event_path = resolve_event_path(event_path)
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
	event_path = resolve_event_path(event_path)
	if event_path == _music_path and _music != null and _music.is_valid():
		return
	if _transition != null:
		_prepare_pending_music(event_path)
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
	_discard_pending_music()


# Stops the current music and plays a one-shot transition sound right away.
# Music requested while it plays (next_music_path now, or a later play_music
# call) starts as the transition ends. The current music is stopped through
# FMOD (its own fade-out, if any) because a scene load may follow immediately.
func play_transition(event_path: String, next_music_path: String = "") -> void:
	event_path = resolve_event_path(event_path)
	if not has_events([event_path]):
		return
	if _music != null and _music.is_valid():
		_music.stop(FmodServer.FMOD_STUDIO_STOP_ALLOWFADEOUT)
		_music.release()
	_music = null
	_music_path = ""
	_discard_pending_music()
	_end_transition()
	_transition = FmodServer.create_event_instance(event_path)
	if _transition == null:
		return
	_transition.set_volume(_effects_gain(false))
	_transition.start()
	_transition_owned = true
	_transition_elapsed = 0.0
	_transition_length = FmodServer.get_event(event_path).get_length() / 1000.0
	_transition_lead = transition_music_lead_seconds
	if not next_music_path.is_empty():
		_prepare_pending_music(next_music_path)
	FmodServer.update()


# Treats a sound already playing (an instance of event_path) as a transition:
# music requested from now on waits until it is lead_seconds from its end.
func hold_music_for(instance: FmodEvent, event_path: String, lead_seconds: float) -> void:
	event_path = resolve_event_path(event_path)
	if instance == null or not instance.is_valid() or not has_events([event_path]):
		return
	_discard_pending_music()
	_end_transition()
	_transition = instance
	_transition_owned = false
	_transition_elapsed = 0.0
	_transition_length = FmodServer.get_event(event_path).get_length() / 1000.0
	_transition_lead = lead_seconds


# True until the current transition sound reaches the point where the next
# music would start (see transition_music_lead_seconds).
func is_transition_playing() -> bool:
	return _transition != null


## Returns -1 when this track is unavailable. FMOD owns looping, pausing and seeking.
func get_music_position_seconds(event_path: String) -> float:
	event_path = resolve_event_path(event_path)
	if _music_path != event_path or _music == null or not _music.is_valid():
		return -1.0
	return float(_music.get_timeline_position()) / 1000.0


func _process(delta: float) -> void:
	var paused: bool = get_tree().paused
	if paused != _game_paused:
		_game_paused = paused
		_set_gameplay_frozen(paused)
	_advance_music_menu(delta)
	# Music keeps playing through a pause, so its fades do too.
	_advance_music_fades(delta)
	# Transitions are gameplay sounds: they hold with the pause.
	if paused:
		return
	_advance_music_duck(delta)
	if _transition != null:
		_transition_elapsed += delta
		if _is_transition_ending():
			_end_transition()
			_start_pending_music()
	_effects_elapsed += delta
	if _effects_elapsed >= 0.1:
		_effects_elapsed = 0.0
		_apply_effects_volume()


func _advance_music_fades(delta: float) -> void:
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


func _is_transition_ending() -> bool:
	if not _transition.is_valid() or _transition_elapsed >= TRANSITION_TIMEOUT_SECONDS:
		return true
	if _transition.get_playback_state() == FmodServer.FMOD_STUDIO_PLAYBACK_STOPPED:
		return true
	return (
		_transition_length > 0.0
		and (_transition.get_timeline_position() / 1000.0 >= _transition_length - _transition_lead)
	)


func _prepare_pending_music(event_path: String) -> void:
	event_path = resolve_event_path(event_path)
	if event_path == _pending_music_path:
		return
	_discard_pending_music()
	if not has_events([event_path]):
		return
	_pending_music = FmodServer.create_event_instance(event_path)
	if _pending_music == null:
		return
	_pending_music.set_volume(_music_gain())
	_pending_music.set_paused(true)
	_pending_music.start()
	_pending_music_path = event_path


# Picks up right where the transition ends, so it starts at full volume.
func _start_pending_music() -> void:
	if _pending_music == null or not _pending_music.is_valid():
		_discard_pending_music()
		return
	_music = _pending_music
	_music_path = _pending_music_path
	_pending_music = null
	_pending_music_path = ""
	_music_volume = 1.0
	_music.set_volume(_music_gain())
	_music.set_paused(false)


func _discard_pending_music() -> void:
	if _pending_music != null and _pending_music.is_valid():
		_pending_music.stop(FmodServer.FMOD_STUDIO_STOP_IMMEDIATE)
		_pending_music.release()
	_pending_music = null
	_pending_music_path = ""


func _end_transition() -> void:
	if _transition_owned and _transition != null and _transition.is_valid():
		_transition.release()
	_transition = null


# While true, Music_Duck eases to 1; set it back to false to release the dip.
func set_music_ducked(ducked: bool) -> void:
	_music_ducked = ducked


func _advance_music_menu(delta: float) -> void:
	var target: float = 1.0 if _game_paused else 0.0
	if is_equal_approx(_music_menu, target):
		return
	var step: float = 1.0 if music_menu_fade_seconds <= 0.0 else delta / music_menu_fade_seconds
	_music_menu = move_toward(_music_menu, target, step)
	if _global_parameters.has(MUSIC_MENU_PARAMETER):
		set_global(MUSIC_MENU_PARAMETER, _music_menu)


func _advance_music_duck(delta: float) -> void:
	var target: float = 1.0 if _music_ducked else 0.0
	if is_equal_approx(_music_duck, target):
		return
	var step: float = 1.0 if music_duck_fade_seconds <= 0.0 else delta / music_duck_fade_seconds
	_music_duck = move_toward(_music_duck, target, step)
	if _global_parameters.has(MUSIC_DUCK_PARAMETER):
		set_global(MUSIC_DUCK_PARAMETER, _music_duck)


func _music_gain() -> float:
	return GamePreferences.music_volume if GamePreferences.audio_enabled else 0.0


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


# Holds gameplay sounds in place and mutes the gameplay bus; music (low-passed
# through Music_Menu) and UI sounds keep playing. Pending music stays paused
# until its transition ends.
func _set_gameplay_frozen(frozen: bool) -> void:
	if _gameplay_bus != null:
		_gameplay_bus.set_mute(frozen)
	for index: int in range(_effect_descriptions.size()):
		var description: FmodEventDescription = _effect_descriptions[index]
		if _effect_is_ui[index] or description.get_instance_count() == 0:
			continue
		for instance: FmodEvent in description.get_instance_list():
			if instance != null and instance.is_valid():
				instance.set_paused(frozen)


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
	for index: int in range(_effect_descriptions.size()):
		var description: FmodEventDescription = _effect_descriptions[index]
		if description.get_instance_count() == 0:
			continue
		var gain: float = _effects_gain(_effect_is_near_view[index])
		for instance: FmodEvent in description.get_instance_list():
			# Native playback may outlive its Godot wrapper or end during enumeration.
			if instance != null and instance.is_valid():
				instance.set_volume(gain)
	# Volume changes apply together at the next FMOD update, so the scaled
	# value below wins without an audible jump.
	for index: int in range(_scaled_effects.size() - 1, -1, -1):
		var entry: Array = _scaled_effects[index]
		var instance: FmodEvent = entry[0]
		if (
			instance == null
			or not instance.is_valid()
			or instance.get_playback_state() == FmodServer.FMOD_STUDIO_PLAYBACK_STOPPED
		):
			_scaled_effects.remove_at(index)
		else:
			instance.set_volume(_effects_gain(entry[2]) * float(entry[1]))


func _effects_gain(near_view: bool) -> float:
	if not GamePreferences.audio_enabled:
		return 0.0
	return GamePreferences.effects_volume * (_near_view_gain if near_view else 1.0)


func _is_near_view(event_path: String) -> bool:
	for prefix: String in NEAR_VIEW_PREFIXES:
		if event_path.begins_with(prefix):
			return true
	return false
