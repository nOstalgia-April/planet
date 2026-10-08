extends Control

const FrameArt = preload("res://scripts/场景动画/帧动画.gd")

@export var view: FrameArt
@export var replay_delay: float = 0.8

var _paused: bool = false
var _finished: bool = false
var _remaining: float = 0.0

@onready var _play_button: Button = $工具栏/按钮/播放
@onready var _frame_slider: HSlider = $工具栏/进度/滑条
@onready var _frame_label: Label = $工具栏/进度/帧数


func _ready() -> void:
	view.finished.connect(_on_finished)
	_frame_slider.max_value = view.frame_count - 1
	get_viewport().size_changed.connect(_fit_view)
	_fit_view()
	_replay()


func _process(delta: float) -> void:
	if _finished and not _paused:
		_remaining -= delta
		if _remaining <= 0.0:
			_replay()
	_update_frame_display()


func _update_frame_display() -> void:
	var frame: int = (
		view.frame_count - 1
		if _finished
		else mini(
			view.frame_count - 1,
			floori(
				(
					(view.animation_player.current_animation_position + 0.00001)
					* view.frames_per_second
				)
			)
		)
	)
	_frame_slider.set_value_no_signal(frame)
	_frame_label.text = (
		"%02d / %02d · %d 帧/秒" % [frame + 1, view.frame_count, view.frames_per_second]
	)


func _fit_view() -> void:
	view.position = Vector2(size.x * 0.5, (size.y - 180.0) * 0.5)


func _replay() -> void:
	_paused = false
	_finished = false
	_play_button.text = "暂停"
	view.play()
	_update_frame_display()


func _toggle_play() -> void:
	_paused = not _paused
	if _paused:
		view.animation_player.pause()
	elif _finished:
		_replay()
	else:
		view.animation_player.play()
	_play_button.text = "播放" if _paused else "暂停"


func _seek(value: float) -> void:
	_paused = true
	_finished = false
	_play_button.text = "播放"
	_frame_slider.set_value_no_signal(value)
	view.seek_frame(roundi(value))
	_update_frame_display()


func _previous() -> void:
	_seek(maxf(0.0, _frame_slider.value - 1.0))


func _next() -> void:
	_seek(minf(_frame_slider.max_value, _frame_slider.value + 1.0))


func _on_finished() -> void:
	_finished = true
	_remaining = replay_delay


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/主菜单/主菜单.tscn")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_toggle_play()
			KEY_R:
				_replay()
			KEY_LEFT:
				_previous()
			KEY_RIGHT:
				_next()
			_:
				return
		get_viewport().set_input_as_handled()
