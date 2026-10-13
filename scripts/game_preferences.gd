extends Node

signal changed

const SAVE_PATH: String = "user://preferences.cfg"

var music_volume: float = 0.8
var effects_volume: float = 0.8
var audio_enabled: bool = true
var fullscreen: bool = false


func _ready() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		music_volume = clampf(float(config.get_value("audio", "music", 0.8)), 0.0, 1.0)
		effects_volume = clampf(float(config.get_value("audio", "effects", 0.8)), 0.0, 1.0)
		audio_enabled = bool(
			config.get_value("audio", "enabled", config.get_value("audio", "music_enabled", true))
		)
		fullscreen = bool(config.get_value("display", "fullscreen", false))
	_apply_display()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	if music_volume > 0.0:
		audio_enabled = true
	_save()


func set_effects_volume(value: float) -> void:
	effects_volume = clampf(value, 0.0, 1.0)
	if effects_volume > 0.0:
		audio_enabled = true
	_save()


func toggle_audio() -> void:
	var volumes_zero: bool = is_zero_approx(music_volume) and is_zero_approx(effects_volume)
	audio_enabled = not audio_enabled or volumes_zero
	if audio_enabled and volumes_zero:
		music_volume = 0.8
		effects_volume = 0.8
	_save()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_display()
	_save()


func reset_defaults() -> void:
	music_volume = 0.8
	effects_volume = 0.8
	audio_enabled = true
	fullscreen = false
	_apply_display()
	_save()


func _apply_display() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("audio", "enabled", audio_enabled)
	config.set_value("display", "fullscreen", fullscreen)
	var error: Error = config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save preferences: %s" % error_string(error))
	changed.emit()
