extends Control

const AnimationView = preload("res://scripts/物品动画/动画物件.gd")

@export var object_scenes: Array[PackedScene] = []
@export var initial_index: int = 0
@export_range(0.0, 3.0, 0.125) var replay_delay: float = 0.75

var current_view: AnimationView
var current_clip: StringName
var _paused: bool = false
var _finished: bool = false
var _replay_remaining: float = 0.0
var _looping_clips: Array[StringName] = []

@onready var _stage: Node2D = $画面
@onready var _object_picker: OptionButton = $工具栏/纵排/选择行/物件选择
@onready var _animation_picker: OptionButton = $工具栏/纵排/选择行/动作选择
@onready var _play_button: Button = $工具栏/纵排/选择行/播放按钮
@onready var _repeat_toggle: CheckButton = $工具栏/纵排/选择行/循环开关
@onready var _frame_slider: HSlider = $工具栏/纵排/进度行/帧进度
@onready var _frame_label: Label = $工具栏/纵排/进度行/帧数


func _ready() -> void:
	assert(not object_scenes.is_empty(), "预览场景没有配置物件。")
	for object_scene in object_scenes:
		_object_picker.add_item(object_scene.resource_path.get_file().get_basename())
	resized.connect(_update_layout)
	_repeat_toggle.toggled.connect(_on_repeat_toggled)
	_update_layout()
	_object_picker.select(initial_index)
	_on_object_selected(initial_index)


func _process(delta: float) -> void:
	if _finished and not _paused and _repeat_toggle.button_pressed:
		_replay_remaining -= delta
		if _replay_remaining <= 0.0:
			_on_replay()
	_update_frame_display()


func _update_layout() -> void:
	_stage.position = Vector2(size.x * 0.5, (size.y - 160.0) * 0.64)
	var magnification: float = clampf(minf(size.x / 650.0, (size.y - 160.0) / 235.0), 1.0, 4.0)
	_stage.scale = Vector2.ONE * magnification


func _on_object_selected(index: int) -> void:
	if current_view != null:
		_stage.remove_child(current_view)
		current_view.queue_free()
	current_view = object_scenes[index].instantiate() as AnimationView
	_stage.add_child(current_view)
	current_view.clip_finished.connect(_on_clip_finished)
	_make_preview_animations_local()
	_animation_picker.clear()
	for clip_name in current_view.animation_order:
		_animation_picker.add_item(String(clip_name))
	_animation_picker.select(0)
	_on_animation_selected(0)


func _on_animation_selected(index: int) -> void:
	current_clip = current_view.animation_order[index]
	_frame_slider.max_value = current_view.get_frame_count(current_clip) - 1
	_on_repeat_toggled(_repeat_toggle.button_pressed)
	_on_replay()


func _make_preview_animations_local() -> void:
	var original: AnimationLibrary = current_view.animation_player.get_animation_library(&"")
	var local_library: AnimationLibrary = AnimationLibrary.new()
	_looping_clips.clear()
	for clip_name in current_view.animation_order:
		var animation: Animation = original.get_animation(clip_name).duplicate() as Animation
		if animation.loop_mode == Animation.LOOP_LINEAR:
			_looping_clips.append(clip_name)
		local_library.add_animation(clip_name, animation)
	current_view.animation_player.remove_animation_library(&"")
	current_view.animation_player.add_animation_library(&"", local_library)


func _on_repeat_toggled(enabled: bool) -> void:
	var animation: Animation = current_view.animation_player.get_animation(current_clip)
	animation.loop_mode = (
		Animation.LOOP_LINEAR if enabled and current_clip in _looping_clips else Animation.LOOP_NONE
	)
	if _finished and not enabled:
		_paused = true
		_play_button.text = "播放"


func _on_replay() -> void:
	_paused = false
	_finished = false
	_play_button.text = "暂停"
	current_view.play_clip(current_clip)
	_update_frame_display()


func _on_toggle_play() -> void:
	if _finished:
		if _paused:
			_on_replay()
		else:
			_paused = true
			_play_button.text = "播放"
		return
	_paused = not _paused
	if _paused:
		current_view.animation_player.pause()
	else:
		current_view.animation_player.play()
	_play_button.text = "播放" if _paused else "暂停"


func _on_clip_finished(_clip_name: StringName) -> void:
	_finished = true
	_replay_remaining = replay_delay
	if not _repeat_toggle.button_pressed:
		_paused = true
		_play_button.text = "播放"


func _on_frame_selected(frame: float) -> void:
	_paused = true
	_finished = false
	_play_button.text = "播放"
	current_view.show_frame(current_clip, roundi(frame))
	_update_frame_display()


func _on_previous_frame() -> void:
	_on_frame_selected(maxf(0.0, _frame_slider.value - 1.0))


func _on_next_frame() -> void:
	_on_frame_selected(minf(_frame_slider.max_value, _frame_slider.value + 1.0))


func _update_frame_display() -> void:
	var count: int = current_view.get_frame_count(current_clip)
	var index: int = count - 1
	if not _finished:
		index = mini(
			count - 1, floori(current_view.animation_player.current_animation_position * 8.0)
		)
	_frame_slider.set_value_no_signal(index)
	_frame_label.text = "%02d / %02d · 8帧/秒" % [index + 1, count]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_on_toggle_play()
			KEY_R:
				_on_replay()
			KEY_LEFT:
				_on_previous_frame()
			KEY_RIGHT:
				_on_next_frame()
			_:
				return
		get_viewport().set_input_as_handled()
