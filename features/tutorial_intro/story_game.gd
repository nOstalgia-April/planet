extends "res://features/场景预览/游玩预览.gd"

const StoryFlow = preload("res://features/tutorial_intro/story_flow.gd")

var _story_ready: bool = false

@onready var story: StoryFlow = $StoryFlow


func _ready() -> void:
	super._ready()
	_story_ready = true
	story.rescue_finished.connect(_finish_rescue)
	story.begin()


func restart_run() -> void:
	if _story_ready:
		story.cancel()
	super.restart_run()
	if _story_ready:
		story.begin()


func _on_victory_finished() -> void:
	story.play_rescue()


func _finish_rescue() -> void:
	super._on_victory_finished()
