extends Node

signal presentation_started
signal presentation_finished
signal progress_committed
signal palette_changed(progress: float)
# The planet starts filling with a species' color: stage 1 for the first species
# restored this run, 2 and 3 for the next ones, whatever the species order.
signal color_fill_started(stage: int)
# The whole scene brightens to white once every nest is automated.
signal background_restore_started

const PlanetView = preload("res://scripts/planet_view_controller.gd")
const PlanetArt = preload("res://scripts/场景动画/双视角星球.gd")
const HorizonTerrain = preload("res://scripts/horizon_terrain.gd")
const PlanetCore = preload("res://scripts/planet_core_animation.gd")

enum Phase { IDLE, CONFIRM, CAMERA, FILL, FINISH, BACKGROUND, HOLD, TERRAIN }

@export var run: PrototypeRun
@export var view: PlanetView
@export var art: PlanetArt
@export var bright_background: Node2D
@export var core: PlanetCore
@export var terrain: HorizonTerrain
@export_range(0.0, 3.0, 0.05) var confirmation_seconds: float = 0.8
@export_range(0.0, 3.0, 0.05) var terrain_seconds: float = 0.9
@export_range(0.0, 6.0, 0.1) var fill_seconds: float = 2.4
@export_range(0.0, 3.0, 0.1) var background_seconds: float = 1.0
@export_range(0.0, 3.0, 0.1) var hold_seconds: float = 1.2

var unlocked_species: Array[int] = []
var completed_species: Array[int] = []
var phase: Phase = Phase.IDLE
var _queue: Array[int] = []
var _species: int = -1
var _elapsed: float = 0.0
var _background_complete: bool = false


func _ready() -> void:
	assert(
		run != null and view != null and art != null and bright_background != null and core != null
	)
	assert(terrain != null)
	reset()


func reveal_flower(_nest_id: int, species: int) -> void:
	assert(species >= 0 and species < 3)
	if species in unlocked_species:
		return
	unlocked_species.append(species)
	_queue.append(species)
	_try_start()


func _try_start() -> void:
	if (
		phase == Phase.IDLE
		and (not _queue.is_empty() or _can_restore_background())
		and not view.presentation_locked
	):
		view.end_drag()
		view.presentation_locked = true
		presentation_started.emit()
		if not _queue.is_empty():
			_start_next()
		else:
			_species = -1
			_set_phase(Phase.CONFIRM)


func _can_restore_background() -> bool:
	if _background_complete or run.nests.is_empty():
		return false
	for nest: NestState in run.nests:
		if not nest.is_tamed:
			return false
	return true


func reset() -> void:
	_queue.clear()
	unlocked_species.clear()
	completed_species.clear()
	_species = -1
	phase = Phase.IDLE
	_elapsed = 0.0
	_background_complete = false
	view.presentation_locked = false
	art.reset_colors()
	terrain.reset_colors()
	bright_background.modulate.a = 0.0
	core.modulate.a = 1.0
	core.set_static(false)
	core.set_white_mix(0.0)
	palette_changed.emit(0.0)


func _start_next() -> void:
	_species = _queue.pop_front()
	_set_phase(Phase.CONFIRM)


func _set_phase(value: Phase) -> void:
	phase = value
	_elapsed = 0.0
	if value == Phase.FILL:
		color_fill_started.emit(completed_species.size() + 1)
	elif value == Phase.BACKGROUND:
		background_restore_started.emit()


func _progress(duration: float) -> float:
	return 1.0 if duration <= 0.0 else clampf(_elapsed / duration, 0.0, 1.0)


func _process(delta: float) -> void:
	_try_start()
	_elapsed += delta
	match phase:
		Phase.CONFIRM:
			if _elapsed >= confirmation_seconds:
				if _species >= 0 and view.near_blend > 0.0 and terrain.has_visible_color(_species):
					_set_phase(Phase.TERRAIN)
				else:
					if _species >= 0:
						terrain.set_color_progress(_species, 1.0)
					_start_overview()
		Phase.TERRAIN:
			var progress: float = smoothstep(0.0, 1.0, _progress(terrain_seconds))
			terrain.set_color_progress(_species, progress)
			if progress >= 1.0:
				_start_overview()
		Phase.CAMERA:
			if not view.is_transitioning():
				_set_phase(Phase.FILL if _species >= 0 else Phase.BACKGROUND)
		Phase.FILL:
			var progress: float = _progress(fill_seconds)
			art.set_color_progress(_species, progress)
			if progress >= 1.0:
				completed_species.append(_species)
				progress_committed.emit()
				_set_phase(Phase.FINISH if completed_species.size() == 3 else Phase.HOLD)
		Phase.FINISH:
			var progress: float = smoothstep(0.0, 1.0, _progress(background_seconds))
			art.set_restored_mix(progress)
			if progress >= 1.0:
				_set_phase(Phase.HOLD)
		Phase.BACKGROUND:
			var progress: float = smoothstep(0.0, 1.0, _progress(background_seconds))
			bright_background.modulate.a = progress
			art.set_white_mix(progress)
			core.set_white_mix(progress)
			palette_changed.emit(progress)
			if progress >= 1.0:
				_background_complete = true
				progress_committed.emit()
				_set_phase(Phase.HOLD)
		Phase.HOLD:
			if _elapsed < hold_seconds:
				return
			if not _queue.is_empty():
				_start_next()
			elif _can_restore_background():
				_set_phase(Phase.BACKGROUND)
			else:
				_set_phase(Phase.IDLE)
				view.presentation_locked = false
				presentation_finished.emit()


func _start_overview() -> void:
	view.show_restoration_overview()
	_set_phase(Phase.CAMERA)


func capture_save() -> Dictionary:
	return {"completed": completed_species.duplicate(), "background": _background_complete}


func restore_save(data: Dictionary) -> void:
	reset()
	completed_species.assign(data.completed)
	# Paid automation can precede its flower animation. Restore the earned result.
	unlocked_species.assign(run.unlocked_colors)
	for nest: NestState in run.nests:
		if nest.is_tamed and nest.species not in unlocked_species:
			unlocked_species.append(nest.species)
	run.unlocked_colors.assign(unlocked_species)
	for species: int in completed_species:
		art.set_color_progress(species, 1.0)
		terrain.set_color_progress(species, 1.0)
	for species: int in unlocked_species:
		if species not in completed_species:
			_queue.append(species)
	if completed_species.size() == 3:
		art.set_restored_mix(1.0)
	_background_complete = data.background
	var white: float = 1.0 if _background_complete else 0.0
	bright_background.modulate.a = white
	art.set_white_mix(white)
	core.set_white_mix(white)
	palette_changed.emit(white)
