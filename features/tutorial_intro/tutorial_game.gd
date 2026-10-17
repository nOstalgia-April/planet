extends "res://features/场景预览/游玩预览.gd"

const Tutorial = preload("res://features/tutorial_intro/tutorial_intro.gd")
const Core = preload("res://scripts/planet_core_animation.gd")

var _tutorial_ready: bool = false

@onready var tutorial: Tutorial = $TutorialIntro
@onready var _core: Core = $World/PlanetSurface/星球画面/星球核心


func _ready() -> void:
	super._ready()
	_tutorial_ready = true
	tutorial.phase_changed.connect(_on_tutorial_phase_changed)
	tutorial.begin()


func _on_tutorial_phase_changed(phase: Tutorial.Phase) -> void:
	_core.set_static(phase in [Tutorial.Phase.OVERVIEW, Tutorial.Phase.ZOOMING])


func restart_run() -> void:
	if _tutorial_ready:
		tutorial.cancel()
	super.restart_run()
	if _tutorial_ready:
		tutorial.begin()
