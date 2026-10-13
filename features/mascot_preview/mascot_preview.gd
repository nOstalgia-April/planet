extends Control

const Presenter = preload("res://scripts/ui/mascot_presenter.gd")

@onready var presenter: Presenter = $MascotPresenter
@onready var pause_button: Button = $Controls/Pause


func _select_form(index: int) -> void:
	presenter.select_form(index)
	pause_button.text = "暂停"
	var buttons: Array[Button] = [$Controls/Cloak, $Controls/Muscle, $Controls/Small]
	for button_index: int in range(buttons.size()):
		buttons[button_index].set_pressed_no_signal(button_index == index)


func _replay() -> void:
	_select_form(presenter.selected_form)


func _toggle_pause() -> void:
	presenter.paused = not presenter.paused
	pause_button.text = "继续" if presenter.paused else "暂停"


func _slow_motion(enabled: bool) -> void:
	presenter.playback_speed = 0.5 if enabled else 1.0


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3:
				_select_form(event.keycode - KEY_1)
			KEY_R:
				_replay()
			KEY_SPACE:
				_toggle_pause()
