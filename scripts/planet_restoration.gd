extends Node

signal presentation_started
signal presentation_finished
signal palette_changed(progress: float)

const PlanetView = preload("res://scripts/planet_view_controller.gd")
const PlanetArt = preload("res://scripts/场景动画/双视角星球.gd")

enum Phase { IDLE, CONFIRM, CAMERA, FILL, FINISH, HOLD }

@export var view: PlanetView
@export var art: PlanetArt
@export var bright_background: Node2D
@export var core: Node2D
@export_range(0.0, 3.0, 0.05) var confirmation_seconds: float = 0.8
@export_range(0.0, 6.0, 0.1) var fill_seconds: float = 2.4
@export_range(0.0, 3.0, 0.1) var background_seconds: float = 1.0
@export_range(0.0, 3.0, 0.1) var hold_seconds: float = 1.2

var unlocked_species: Array[int] = []
var completed_species: Array[int] = []
var phase: Phase = Phase.IDLE
var _queue: Array[int] = []
var _species: int = -1
var _elapsed: float = 0.0


func _ready() -> void:
	assert(view != null and art != null and bright_background != null and core != null)
	reset()


func reveal_flower(_nest_id: int, species: int) -> void:
	assert(species >= 0 and species < 3)
	if species in unlocked_species:
		return
	unlocked_species.append(species)
	_queue.append(species)
	if phase == Phase.IDLE:
		view.end_drag()
		view.presentation_locked = true
		presentation_started.emit()
		_start_next()


func reset() -> void:
	_queue.clear()
	unlocked_species.clear()
	completed_species.clear()
	_species = -1
	phase = Phase.IDLE
	_elapsed = 0.0
	view.presentation_locked = false
	art.reset_colors()
	bright_background.modulate.a = 0.0
	core.modulate.a = 1.0
	palette_changed.emit(0.0)


func _start_next() -> void:
	_species = _queue.pop_front()
	_set_phase(Phase.CONFIRM)


func _set_phase(value: Phase) -> void:
	phase = value
	_elapsed = 0.0


func _progress(duration: float) -> float:
	return 1.0 if duration <= 0.0 else clampf(_elapsed / duration, 0.0, 1.0)


func _process(delta: float) -> void:
	_elapsed += delta
	match phase:
		Phase.CONFIRM:
			if _elapsed >= confirmation_seconds:
				view.show_restoration_overview()
				_set_phase(Phase.CAMERA)
		Phase.CAMERA:
			if not view.is_transitioning():
				_set_phase(Phase.FILL)
		Phase.FILL:
			var progress: float = _progress(fill_seconds)
			art.set_color_progress(_species, progress)
			if progress >= 1.0:
				completed_species.append(_species)
				_set_phase(Phase.FINISH if completed_species.size() == 3 else Phase.HOLD)
		Phase.FINISH:
			var progress: float = smoothstep(0.0, 1.0, _progress(background_seconds))
			art.set_restored_mix(progress)
			bright_background.modulate.a = progress
			core.modulate.a = 1.0 - progress
			palette_changed.emit(progress)
			if progress >= 1.0:
				_set_phase(Phase.HOLD)
		Phase.HOLD:
			if _elapsed < hold_seconds:
				return
			if not _queue.is_empty():
				_start_next()
			else:
				_set_phase(Phase.IDLE)
				view.presentation_locked = false
				presentation_finished.emit()
