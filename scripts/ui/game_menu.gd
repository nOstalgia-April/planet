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

var progress_is_saved: bool = false

var _pending_action: StringName = &""

@onready var toolbar: HBoxContainer = $Toolbar
@onready var _pause: IconButton = $Toolbar/Pause
@onready var _music: IconButton = $Toolbar/Music
@onready var _settings: IconButton = $Toolbar/Settings
@onready var _modal: Control = $Modal
@onready var _panel: PanelContainer = $Modal/Center/Panel
@onready var _panel_material: ShaderMaterial = _panel.material as ShaderMaterial
@onready var _music_slider: HSlider = %MusicVolume
@onready var _effects_slider: HSlider = %EffectsVolume


func _ready() -> void:
	_panel.resized.connect(_sync_panel_height)
	_sync_panel_height()
	_pause.pressed.connect(pause_toggled.emit)
	_music.pressed.connect(GamePreferences.toggle_audio)
	_settings.pressed.connect(set_open.bind(true))
	%CloseSettings.pressed.connect(set_open.bind(false))
	%ResumeGame.pressed.connect(set_open.bind(false))
	_music_slider.value_changed.connect(_set_music)
	_effects_slider.value_changed.connect(_set_effects)
	%DisplayPrevious.pressed.connect(_cycle_display)
	%DisplayNext.pressed.connect(_cycle_display)
	%Controls.mouse_entered.connect(_show_controls.bind(true))
	%Controls.mouse_exited.connect(_leave_controls)
	%Controls.focus_entered.connect(_show_controls.bind(true))
	%Controls.focus_exited.connect(_show_controls.bind(false))
	%Controls.pressed.connect(_show_controls.bind(true))
	%Restart.pressed.connect(_confirm.bind(&"restart"))
	%MainMenu.pressed.connect(_confirm.bind(&"menu"))
	%CancelAction.pressed.connect(cancel_confirmation)
	%ConfirmAction.pressed.connect(_accept_action)
	GamePreferences.changed.connect(_refresh_preferences)
	_refresh_preferences()


func set_accent(color: Color) -> void:
	_panel_material.set_shader_parameter("accent", color)


func _sync_panel_height() -> void:
	_panel_material.set_shader_parameter("panel_height", _panel.size.y)


func is_open() -> bool:
	return _modal.visible


func set_open(open: bool) -> void:
	_modal.visible = open
	_settings.highlighted = open
	_settings.queue_redraw()
	cancel_confirmation()
	settings_changed.emit()
	if open:
		%CloseSettings.grab_focus()
	else:
		_settings.release_focus()


func set_paused(paused: bool) -> void:
	_pause.tooltip_text = "继续 · 空格" if paused else "暂停 · 空格"
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
		%Controls.release_focus()
		_show_controls(false)
	else:
		set_open(false)


func _set_music(value: float) -> void:
	GamePreferences.set_music_volume(value / 100.0)


func _set_effects(value: float) -> void:
	GamePreferences.set_effects_volume(value / 100.0)


func _refresh_preferences() -> void:
	var audio_audible: bool = (
		GamePreferences.audio_enabled
		and (GamePreferences.music_volume > 0.0 or GamePreferences.effects_volume > 0.0)
	)
	_music.glyph = MUSIC_ON if audio_audible else MUSIC_OFF
	_music.highlighted = not audio_audible
	_music.tooltip_text = "关闭声音" if audio_audible else "开启声音"
	_music.queue_redraw()
	_music_slider.set_value_no_signal(GamePreferences.music_volume * 100.0)
	_effects_slider.set_value_no_signal(GamePreferences.effects_volume * 100.0)
	%MusicValue.text = (
		"%d%%" % roundi(_music_slider.value) if GamePreferences.audio_enabled else "已关闭"
	)
	%EffectsValue.text = (
		"%d%%" % roundi(_effects_slider.value) if GamePreferences.audio_enabled else "已关闭"
	)
	%DisplayMode.text = "全屏" if GamePreferences.fullscreen else "窗口"


func _cycle_display() -> void:
	GamePreferences.set_fullscreen(not GamePreferences.fullscreen)


func _show_controls(show_controls: bool) -> void:
	if not _pending_action.is_empty():
		return
	%ControlsText.visible = show_controls
	%SettingsBody.visible = not show_controls


func _leave_controls() -> void:
	%Controls.release_focus()
	_show_controls(false)


func _confirm(action: StringName) -> void:
	_pending_action = action
	%SettingsBody.hide()
	%ControlsText.hide()
	%Controls.disabled = true
	%Confirmation.show()
	%ConfirmText.text = "重新开始？\n本局进度将被清空。"
	if action != &"restart":
		%ConfirmText.text = "返回主菜单？\n进度将自动保存。" if progress_is_saved else "返回主菜单？\n本局进度不会保留。"
	%CancelAction.grab_focus()


func cancel_confirmation() -> void:
	_pending_action = &""
	%Controls.disabled = false
	%Confirmation.hide()
	%ControlsText.hide()
	%SettingsBody.show()


func _accept_action() -> void:
	var action: StringName = _pending_action
	set_open(false)
	if action == &"restart":
		restart_requested.emit()
	elif action == &"menu":
		menu_requested.emit()
