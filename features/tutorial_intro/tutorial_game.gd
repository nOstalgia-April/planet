extends "res://features/场景预览/游玩预览.gd"

const Tutorial = preload("res://features/tutorial_intro/tutorial_intro.gd")
const Core = preload("res://scripts/planet_core_animation.gd")

var _tutorial_ready: bool = false
var _core_waiting_for_overview: bool = false
var _core_reached_near: bool = false

@onready var tutorial: Tutorial = $TutorialIntro
@onready var _core: Core = $World/PlanetSurface/星球画面/星球核心


func _ready() -> void:
	super._ready()
	_tutorial_ready = true
	tutorial.phase_changed.connect(_on_tutorial_phase_changed)
	_view.view_changed.connect(_on_core_view_changed)
	tutorial.begin()


func _on_tutorial_phase_changed(phase: Tutorial.Phase) -> void:
	if phase == Tutorial.Phase.OVERVIEW:
		_core_waiting_for_overview = true
		_core_reached_near = false
		_core.set_static(true)


func _on_core_view_changed() -> void:
	if not _core_waiting_for_overview or _view.is_transitioning():
		return
	if is_equal_approx(_view.zoom_amount, 1.0):
		_core_reached_near = true
	elif _view.is_overview() and _core_reached_near:
		_core_waiting_for_overview = false
		_core.set_static(false)


func restart_run() -> void:
	if _tutorial_ready:
		tutorial.cancel()
	super.restart_run()
	if _tutorial_ready:
		tutorial.begin()
