extends Node

signal started
signal finished
signal overview_reached
signal playback_started

const PlanetView = preload("res://scripts/planet_view_controller.gd")
const FrameAnimation = preload("res://scripts/场景动画/帧动画.gd")

enum Phase { IDLE, CAMERA, PLAYING, COMPLETE, WAITING }

@export var view: PlanetView
@export var meteors: FrameAnimation
@export var wait_for_story: bool = false

var phase: Phase = Phase.IDLE


func _ready() -> void:
	assert(view != null and meteors != null)
	meteors.finished.connect(_on_meteors_finished)
	view.projection_changed.connect(_sync_opacity)
	reset()


func play() -> void:
	if phase != Phase.IDLE:
		return
	assert(not view.presentation_locked, "Finish the current presentation before victory.")
	phase = Phase.CAMERA
	view.presentation_locked = true
	view.end_drag()
	started.emit()
	view.show_restoration_overview()


func reset() -> void:
	if phase in [Phase.CAMERA, Phase.PLAYING, Phase.WAITING]:
		view.presentation_locked = false
	phase = Phase.IDLE
	meteors.animation_player.stop()
	meteors.hide()
	meteors.modulate.a = 1.0


func _process(_delta: float) -> void:
	if phase != Phase.CAMERA or view.is_transitioning():
		return
	phase = Phase.WAITING
	overview_reached.emit()
	if not wait_for_story:
		play_meteors()


func play_meteors() -> void:
	if phase not in [Phase.IDLE, Phase.WAITING]:
		return
	view.presentation_locked = true
	phase = Phase.PLAYING
	_sync_opacity()
	meteors.show()
	meteors.play()
	playback_started.emit()


func _on_meteors_finished() -> void:
	if phase != Phase.PLAYING:
		return
	phase = Phase.COMPLETE
	view.presentation_locked = false
	finished.emit()


func _sync_opacity() -> void:
	# Keep the supplied full-frame artwork in the distant background after victory.
	meteors.modulate.a = 1.0 - view.near_blend
