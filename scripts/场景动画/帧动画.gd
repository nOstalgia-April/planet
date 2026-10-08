extends Node2D

signal finished

@export var animation_player: AnimationPlayer
@export var clip: StringName = &"待机"
@export_range(1.0, 30.0) var frames_per_second: float = 5.0
@export var frame_count: int = 1


func _ready() -> void:
	assert(animation_player != null)
	animation_player.animation_finished.connect(_on_finished)


func play() -> void:
	animation_player.stop()
	animation_player.play(clip)
	animation_player.advance(0.0)


func seek_frame(index: int) -> void:
	animation_player.assigned_animation = clip
	animation_player.seek(float(clampi(index, 0, frame_count - 1)) / frames_per_second, true)
	animation_player.pause()


func _on_finished(_name: StringName) -> void:
	finished.emit()
