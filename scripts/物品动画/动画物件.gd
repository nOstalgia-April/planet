extends Node2D

signal clip_finished(clip_name: StringName)

@export var default_animation: StringName = &"待机"
@export var animation_order: Array[StringName] = []
@export var animation_player: AnimationPlayer
@export_range(1.0, 30.0, 1.0) var frames_per_second: float = 8.0


func _ready() -> void:
	assert(animation_player != null, "动画物件缺少动画播放器。")
	animation_player.animation_finished.connect(_on_animation_finished)


func play_clip(clip_name: StringName) -> void:
	assert(animation_player.has_animation(clip_name), "不存在动画：%s" % clip_name)
	animation_player.stop()
	animation_player.play(clip_name)
	animation_player.advance(0.0)


func show_frame(clip_name: StringName, frame_index: int) -> void:
	assert(animation_player.has_animation(clip_name), "不存在动画：%s" % clip_name)
	animation_player.assigned_animation = clip_name
	var last_frame: int = get_frame_count(clip_name) - 1
	var animation: Animation = animation_player.get_animation(clip_name)
	animation_player.seek(animation.track_get_key_time(0, clampi(frame_index, 0, last_frame)), true)
	animation_player.pause()


func get_frame_count(clip_name: StringName) -> int:
	return animation_player.get_animation(clip_name).track_get_key_count(0)


func _on_animation_finished(clip_name: StringName) -> void:
	clip_finished.emit(clip_name)
