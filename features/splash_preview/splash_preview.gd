extends Node2D

const SplashEffect = preload("res://features/splash_preview/effects/splash_effect_base.gd")

const TINTS: Array[Color] = [Color("ff0060"), Color("087aff"), Color("09c920")]

@export_range(0.0, 1.0, 0.05) var loop_gap: float = 0.35

var _effects: Array[SplashEffect] = []
var _cards: Array[Control] = []
var _elapsed: float = 0.0
var _playing: bool = true
var _solo_index: int = -1
var _updating_progress: bool = false

@onready var _replay: Button = %Replay
@onready var _pause: Button = %Pause
@onready var _loop: CheckButton = %Loop
@onready var _red: Button = %Red
@onready var _blue: Button = %Blue
@onready var _green: Button = %Green
@onready var _intensity: HSlider = %Intensity
@onready var _intensity_value: Label = %IntensityValue
@onready var _progress: HSlider = %Progress
@onready var _progress_value: Label = %ProgressValue


func _ready() -> void:
	get_window().title = "中央喷溅 · 四种效果"
	_effects = [
		$UI/Layout/Columns/Grid/Elastic/Effect,
		$UI/Layout/Columns/Grid/Lobe/Effect,
		$UI/Layout/Columns/Grid/Twist/Effect,
		$UI/Layout/Columns/Grid/Burst/Effect,
	]
	_cards = [
		$UI/Layout/Columns/Grid/Elastic,
		$UI/Layout/Columns/Grid/Lobe,
		$UI/Layout/Columns/Grid/Twist,
		$UI/Layout/Columns/Grid/Burst,
	]
	_replay.pressed.connect(play_all)
	_pause.toggled.connect(_on_pause_toggled)
	_red.pressed.connect(set_preview_tint.bind(TINTS[0]))
	_blue.pressed.connect(set_preview_tint.bind(TINTS[1]))
	_green.pressed.connect(set_preview_tint.bind(TINTS[2]))
	_intensity.value_changed.connect(set_preview_intensity)
	_progress.value_changed.connect(_on_progress_changed)
	_progress.drag_started.connect(_pause_for_scrub)
	for index: int in range(_cards.size()):
		_cards[index].resized.connect(_update_effect_layout)
		_cards[index].gui_input.connect(_on_card_input.bind(index))
	set_preview_tint(TINTS[0])
	set_preview_intensity(_intensity.value)
	_update_effect_layout()
	play_all()


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	var duration: float = _effects[0].duration
	if _elapsed >= duration + loop_gap and _loop.button_pressed:
		_elapsed = fmod(_elapsed, duration + loop_gap)
	elif _elapsed >= duration and not _loop.button_pressed:
		_elapsed = duration
		_playing = false
		_pause.set_pressed_no_signal(true)
		_pause.text = "继续"
	_apply_time(minf(_elapsed, duration))
	_update_progress()


func play_all() -> void:
	_solo_index = -1
	_elapsed = 0.0
	_playing = true
	_pause.set_pressed_no_signal(false)
	_pause.text = "暂停"
	_apply_time(0.0)
	_update_progress()


func play_effect(index: int) -> void:
	_solo_index = index
	_elapsed = 0.0
	_playing = true
	_pause.set_pressed_no_signal(false)
	_pause.text = "暂停"
	_apply_time(0.0)
	_update_progress()


func set_preview_tint(tint: Color) -> void:
	for effect: SplashEffect in _effects:
		effect.set_tint(tint)
	_red.set_pressed_no_signal(tint.is_equal_approx(TINTS[0]))
	_blue.set_pressed_no_signal(tint.is_equal_approx(TINTS[1]))
	_green.set_pressed_no_signal(tint.is_equal_approx(TINTS[2]))


func set_preview_intensity(intensity: float) -> void:
	for effect: SplashEffect in _effects:
		effect.set_intensity(intensity)
	_intensity.set_value_no_signal(intensity)
	_intensity_value.text = "%.2f" % intensity
	_update_effect_layout()
	_apply_time(minf(_elapsed, _effects[0].duration))


func set_preview_time(seconds: float) -> void:
	_solo_index = -1
	_elapsed = clampf(seconds, 0.0, _effects[0].duration)
	_pause_for_scrub()
	_apply_time(_elapsed)
	_update_progress()


func _apply_time(seconds: float) -> void:
	if _solo_index >= 0:
		_effects[_solo_index].seek(seconds)
		return
	for effect: SplashEffect in _effects:
		effect.seek(seconds)


func _update_effect_layout() -> void:
	for index: int in range(_cards.size()):
		var card_size: Vector2 = _cards[index].size
		_effects[index].position = Vector2(card_size.x * 0.5, card_size.y * 0.53)
		var fit: float = minf(card_size.x / 580.0, card_size.y / 300.0)
		var fit_scale: float = clampf(fit, 0.7, 1.5) / maxf(1.0, _intensity.value)
		_effects[index].scale = Vector2.ONE * clampf(fit_scale, 0.35, 1.5)


func _update_progress() -> void:
	_updating_progress = true
	_progress.value = minf(_elapsed / _effects[0].duration, 1.0)
	_progress_value.text = "%.2f s" % minf(_elapsed, _effects[0].duration)
	_updating_progress = false


func _on_pause_toggled(paused: bool) -> void:
	_playing = not paused
	_pause.text = "继续" if paused else "暂停"
	if _playing and _elapsed >= _effects[0].duration:
		_elapsed = 0.0


func _pause_for_scrub() -> void:
	_playing = false
	_pause.set_pressed_no_signal(true)
	_pause.text = "继续"


func _on_progress_changed(progress: float) -> void:
	if _updating_progress:
		return
	_pause_for_scrub()
	_elapsed = progress * _effects[0].duration
	_apply_time(_elapsed)
	_update_progress()


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			play_effect(index)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_R:
				play_all()
			elif key.keycode == KEY_SPACE:
				_pause.button_pressed = not _pause.button_pressed
