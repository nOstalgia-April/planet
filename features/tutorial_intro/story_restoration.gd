extends "res://scripts/planet_restoration.gd"

signal story_started(stage: int)

@export_range(0.1, 2.0, 0.05) var return_seconds: float = 0.65

var dialogue_pending: bool = false
var returning_to_near: bool = false


func reset() -> void:
	dialogue_pending = false
	returning_to_near = false
	super.reset()


func confirm_dialogue() -> void:
	dialogue_pending = false


func _start_overview() -> void:
	super._start_overview()
	if _species >= 0:
		dialogue_pending = true
		story_started.emit(completed_species.size() + 1)


func _process(delta: float) -> void:
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
		delta = 0.0
	super._process(delta)
