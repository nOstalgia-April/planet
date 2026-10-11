extends Control

signal pause_toggled
signal settings_changed
signal restart_requested
signal menu_requested

const IconButton = preload("res://scripts/ui/menu_icon_button.gd")
const PAUSE: Texture2D = preload("res://assets/ui/game_menu/pause.tres")
const RESUME: Texture2D = preload("res://assets/ui/game_menu/resume.tres")
const MUSIC_ON: Texture2D = preload("res://assets/ui/game_menu/music_on.tres")
const MUSIC_OFF: Texture2D = preload("res://assets/ui/game_menu/music_off.tres")

var _pending_action: StringName = &""

@onready var toolbar: HBoxContainer = $Toolbar
@onready var _pause: IconButton = $Toolbar/Pause
@onready var _music: IconButton = $Toolbar/Music
@onready var _settings: IconButton = $Toolbar/Settings
@onready var _modal: Control = $Modal
@onready var _music_slider: HSlider = %MusicVolume
@onready var _effects_slider: HSlider = %EffectsVolume


func _ready() -> void:
	_pause.pressed.connect(pause_toggled.emit)
	_music.pressed.connect(GamePreferences.toggle_music)
	_settings.pressed.connect(set_open.bind(true))
	%CloseSettings.pressed.connect(set_open.bind(false))
	%ResumeGame.pressed.connect(set_open.bind(false))
	_music_slider.value_changed.connect(_set_music)
	_effects_slider.value_changed.connect(_set_effects)
	%Fullscreen.toggled.connect(GamePreferences.set_fullscreen)
	%Defaults.pressed.connect(GamePreferences.reset_defaults)
	%Controls.pressed.connect(_toggle_controls)
	%Restart.pressed.connect(_confirm.bind(&"restart"))
	%MainMenu.pressed.connect(_confirm.bind(&"menu"))
	%CancelAction.pressed.connect(cancel_confirmation)
	%ConfirmAction.pressed.connect(_accept_action)
	GamePreferences.changed.connect(_refresh_preferences)
	_refresh_preferences()


func is_open() -> bool:
	return _modal.visible


func set_open(open: bool) -> void:
	_modal.visible = open
	_settings.highlighted = open
	_settings.queue_redraw()
	cancel_confirmation()
	%ControlsText.hide()
	settings_changed.emit()
	if open:
		%CloseSettings.grab_focus()
	else:
		_settings.release_focus()


func set_paused(paused: bool) -> void:
	_pause.glyph = RESUME if paused else PAUSE
	_pause.highlighted = paused
	_pause.queue_redraw()
	$Toolbar/Pause/PausedLabel.visible = paused and not is_open()


func contains_pointer(pointer: Vector2) -> bool:
	return is_open() or toolbar.get_global_rect().has_point(pointer)


func handle_escape() -> void:
	if not _pending_action.is_empty():
		cancel_confirmation()
	elif %ControlsText.visible:
		%ControlsText.hide()
	else:
		set_open(false)


func _set_music(value: float) -> void:
	GamePreferences.set_music_volume(value / 100.0)


func _set_effects(value: float) -> void:
	GamePreferences.set_effects_volume(value / 100.0)


func _refresh_preferences() -> void:
	var music_audible: bool = GamePreferences.music_enabled and GamePreferences.music_volume > 0.0
	_music.glyph = MUSIC_ON if music_audible else MUSIC_OFF
	_music.highlighted = not music_audible
	_music.queue_redraw()
	_music_slider.set_value_no_signal(GamePreferences.music_volume * 100.0)
	_effects_slider.set_value_no_signal(GamePreferences.effects_volume * 100.0)
	%MusicValue.text = "%d%%" % roundi(_music_slider.value) if music_audible else "已关闭"
	%EffectsValue.text = "%d%%" % roundi(_effects_slider.value)
	%Fullscreen.set_pressed_no_signal(GamePreferences.fullscreen)


func _toggle_controls() -> void:
	%ControlsText.visible = not %ControlsText.visible


func _confirm(action: StringName) -> void:
	_pending_action = action
	%SettingsBody.hide()
	%Confirmation.show()
	%ConfirmText.text = ("重新开始？\n本局进度将被清空。" if action == &"restart" else "返回主菜单？\n本局进度不会保留。")
	%CancelAction.grab_focus()


func cancel_confirmation() -> void:
	_pending_action = &""
	%Confirmation.hide()
	%SettingsBody.show()


func _accept_action() -> void:
	var action: StringName = _pending_action
	set_open(false)
	if action == &"restart":
		restart_requested.emit()
	elif action == &"menu":
		menu_requested.emit()
