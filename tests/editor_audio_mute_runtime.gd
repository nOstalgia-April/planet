extends Node

var _elapsed: float = 0.0


func _ready() -> void:
	GamePreferences.audio_enabled = true
	GamePreferences.effects_volume = 0.24
	GamePreferences.changed.emit()
	EngineDebugger.register_message_capture(&"audio_mute_test", _capture)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.1:
		return
	_elapsed = 0.0
	EngineDebugger.send_message(
		"audio_mute_test:state",
		[GameAudio._editor_muted, GameAudio._master_bus.get_mute(), AudioServer.is_bus_mute(0)]
	)


func _capture(message: String, data: Array) -> bool:
	if message != "set_game_enabled":
		return false
	GamePreferences.audio_enabled = data[0]
	GamePreferences.changed.emit()
	return true
