extends "res://features/场景预览/游玩预览.gd"

const Tutorial = preload("res://features/tutorial_intro/tutorial_intro.gd")

var _tutorial_ready: bool = false

@onready var tutorial: Tutorial = $TutorialIntro


func _ready() -> void:
	super._ready()
	_tutorial_ready = true
	tutorial.begin()


func restart_run() -> void:
	if _tutorial_ready:
		tutorial.cancel()
	super.restart_run()
	if _tutorial_ready:
		tutorial.begin()
