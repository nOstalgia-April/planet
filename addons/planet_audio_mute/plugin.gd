@tool
extends EditorPlugin

const AudioDebugger = preload("res://addons/planet_audio_mute/debugger.gd")

var _debugger: AudioDebugger = AudioDebugger.new()
var _mute_button: Button
var _muted_icon: Texture2D
var _lookup_elapsed: float = 0.0
var _warned: bool = false


func _enter_tree() -> void:
	add_debugger_plugin(_debugger)
	_bind_mute_button.call_deferred()


func _exit_tree() -> void:
	remove_debugger_plugin(_debugger)


func _process(delta: float) -> void:
	if is_instance_valid(_mute_button):
		var muted: bool = _mute_button.icon == _muted_icon
		if muted != _debugger.muted:
			_debugger.set_muted(muted)
		return
	_lookup_elapsed += delta
	if _lookup_elapsed >= 1.0:
		_lookup_elapsed = 0.0
		_bind_mute_button()


func _bind_mute_button() -> void:
	var base: Control = EditorInterface.get_base_control()
	_muted_icon = base.get_theme_icon(&"AudioMute", &"EditorIcons")
	var audible_icon: Texture2D = base.get_theme_icon(&"AudioStreamPlayer", &"EditorIcons")
	# Godot 4.7 has no public Game view mute signal or runtime debug-mute getter.
	# Match the native button by its actual editor icons, scoped to GameView,
	# so this works with translated tooltips and detached Game view windows.
	for view: Node in base.get_tree().root.find_children("*", "GameView", true, false):
		for node: Node in view.find_children("*", "Button", true, false):
			var button: Button = node as Button
			if button.icon == _muted_icon or button.icon == audible_icon:
				_mute_button = button
				_debugger.set_muted(button.icon == _muted_icon)
				return
	if not _warned:
		_warned = true
		push_warning("Planet Audio Mute: Godot Game view mute button was not found.")
