extends "res://scripts/planet_restoration.gd"

signal story_started(stage: int)

@export_range(0.1, 2.0, 0.05) var return_seconds: float = 0.65

var dialogue_pending: bool = false
var returning_to_near: bool = false
var _passive_restoration: bool = false


func reset() -> void:
	dialogue_pending = false
	returning_to_near = false
	_passive_restoration = false
	super.reset()


func confirm_dialogue() -> void:
	dialogue_pending = false


func _try_start() -> void:
	if (
		phase == Phase.IDLE
		and (
			(completed_species.size() == 2 and not _queue.is_empty())
			or (completed_species.size() == 3 and _can_restore_background())
		)
	):
		if view.presentation_locked:
			return
		_passive_restoration = true
		if not _queue.is_empty():
			_start_next()
		else:
			_species = -1
			_set_phase(Phase.CONFIRM)
		return
	super._try_start()


func _start_overview() -> void:
	if _passive_restoration:
		_set_phase(Phase.FILL if _species >= 0 else Phase.BACKGROUND)
		if _species >= 0:
			story_started.emit(3)
		return
	super._start_overview()
	if _species >= 0:
		dialogue_pending = true
		story_started.emit(completed_species.size() + 1)


func _process(delta: float) -> void:
	if _passive_restoration and phase == Phase.HOLD:
		# This restoration never acquired the camera or gameplay controls.
		_passive_restoration = false
		_set_phase(Phase.IDLE)
		return
	if phase == Phase.HOLD and _species >= 0:
		_elapsed += delta
		if _elapsed < hold_seconds:
			return
		if dialogue_pending:
			return
		if not returning_to_near:
			returning_to_near = true
			view.zoom_discovery(1.0, return_seconds)
			return
		if view.is_transitioning():
			return
		returning_to_near = false
		if completed_species.size() == 2 and not _queue.is_empty():
			# Finish the second dialogue before a queued third color starts in free play.
			_set_phase(Phase.IDLE)
			view.presentation_locked = false
			presentation_finished.emit()
			return
		delta = 0.0
	super._process(delta)
