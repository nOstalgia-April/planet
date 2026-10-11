extends "res://features/场景预览/游玩预览.gd"


func _ready() -> void:
	super._ready()
	run._pending_nest_species = NestState.Species.DRILL
	_on_nest_spawn_requested(NestState.Species.DRILL)
	var nest: NestState = run.get_nest(3)
	_view.zoom_steps(-1.0, false)
	_view.focus_surface(nest.position.angle(), false)
	run._advance_nest_population(nest, run.get_nest_spawn_interval(nest.nest_id))
