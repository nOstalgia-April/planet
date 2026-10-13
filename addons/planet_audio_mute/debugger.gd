@tool
extends EditorDebuggerPlugin

var muted: bool = false


func _has_capture(capture: String) -> bool:
	return capture == "planet_audio"


func _capture(message: String, _data: Array, session_id: int) -> bool:
	if message != "planet_audio:ready":
		return false
	_send_state(get_session(session_id))
	return true


func _setup_session(session_id: int) -> void:
	var session: EditorDebuggerSession = get_session(session_id)
	session.started.connect(_send_state.bind(session))


func set_muted(value: bool) -> void:
	muted = value
	for session: EditorDebuggerSession in get_sessions():
		_send_state(session)


func _send_state(session: EditorDebuggerSession) -> void:
	if session.is_active():
		session.send_message("planet_audio:set_editor_muted", [muted])
