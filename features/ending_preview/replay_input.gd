extends Node

signal replay_requested


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_R:
			get_viewport().set_input_as_handled()
			get_tree().paused = false
			replay_requested.emit()
