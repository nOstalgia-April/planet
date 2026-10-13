extends SceneTree

const AudioPlugin = preload("res://addons/planet_audio_mute/plugin.gd")
const RUNTIME: String = "res://tests/editor_audio_mute_runtime.tscn"


class Inspector:
	extends EditorDebuggerPlugin
	var state: Array = []

	func _has_capture(capture: String) -> bool:
		return capture == "audio_mute_test"

	func _capture(message: String, data: Array, _session_id: int) -> bool:
		if message != "audio_mute_test:state":
			return false
		state = data
		return true

	func set_game_enabled(enabled: bool) -> void:
		for session: EditorDebuggerSession in get_sessions():
			if session.is_active():
				session.send_message("audio_mute_test:set_game_enabled", [enabled])


var _elapsed: float = 0.0
var _started: bool = false
var _failures: int = 0
var _inspector: Inspector


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _started and _elapsed > 8.0:
		_started = true
		_run.call_deferred()
	return false


func _run() -> void:
	_inspector = Inspector.new()
	var plugin: AudioPlugin
	for node: Node in root.find_children("*", "EditorPlugin", true, false):
		if node.get_script() == AudioPlugin:
			plugin = node as AudioPlugin
	if plugin == null or plugin._mute_button == null:
		push_error("Audio plugin or native Game view mute button is missing.")
		quit(1)
		return
	plugin.add_debugger_plugin(_inspector)
	EditorInterface.play_custom_scene(RUNTIME)
	await _expect([false, false, false], "initial editor and FMOD are unmuted")
	plugin._mute_button.pressed.emit()
	await _expect([true, true, true], "native editor button mutes FMOD and Godot")
	plugin._mute_button.pressed.emit()
	await _expect([false, false, false], "native editor button restores output")
	_inspector.set_game_enabled(false)
	await _expect([false, true, true], "game's own mute closes both audio paths")
	plugin._mute_button.pressed.emit()
	await _expect([true, true, true], "editor can mute while game is muted")
	plugin._mute_button.pressed.emit()
	await _expect([false, true, true], "editor unmute preserves game mute")
	_inspector.set_game_enabled(true)
	await _expect([false, false, false], "game unmute restores both audio paths")
	plugin._mute_button.pressed.emit()
	await _expect([true, true, true], "editor mute before restarting game")
	EditorInterface.stop_playing_scene()
	await create_timer(1.0).timeout
	_inspector.state = []
	EditorInterface.play_custom_scene(RUNTIME)
	await _expect([true, true, true], "new run inherits native editor mute")
	plugin._mute_button.pressed.emit()
	await _expect([false, false, false], "new run receives live unmute")
	EditorInterface.stop_playing_scene()
	plugin.remove_debugger_plugin(_inspector)
	print(
		(
			"PASS: native editor mute button, debugger transport, FMOD/native master, game mute isolation and restart."
			if _failures == 0
			else "FAIL: editor audio bridge"
		)
	)
	quit(0 if _failures == 0 else 1)


func _expect(expected: Array, description: String) -> void:
	for attempt: int in range(150):
		await create_timer(0.1).timeout
		if _inspector.state == expected:
			print("CHECK: ", description)
			return
	_failures += 1
	push_error("%s: expected %s, received %s" % [description, expected, _inspector.state])
