extends "res://features/场景预览/游玩预览.gd"

@export var preview_species: NestState.Species = NestState.Species.MUCUS
@export var preview_from_overview: bool = false


func _ready() -> void:
	super._ready()
	_preview.call_deferred(preview_species)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_2, KEY_3]:
			_preview((event.keycode - KEY_1) as NestState.Species)
			get_viewport().set_input_as_handled()


func _preview(species: NestState.Species) -> void:
	restart_run()
	# Existing inhabitants make the anticipation's slow motion visible in F6.
	for nest: NestState in run.nests:
		run._advance_nest_population(nest, run.get_nest_spawn_interval(nest.nest_id))
	if preview_from_overview:
		_view.zoom_steps(-1.0, false)
	run._pending_nest_species = species
	_on_nest_spawn_requested(species)
