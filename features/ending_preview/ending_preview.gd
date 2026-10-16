extends "res://features/场景预览/游玩预览.gd"


func _ready() -> void:
	super._ready()
	_replay_ending.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_replay_ending()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_key_input(event)


func _replay_ending() -> void:
	restart_run()
	run._add_nest(NestState.Species.MUCUS, _planet.get_nest_position(0.0))
	run._add_nest(NestState.Species.DRILL, _planet.get_nest_position(PI))
	run.candy = 100000
	run.purchase_technology("cultivation")
	run.purchase_technology("automation")
	for nest: NestState in run.nests:
		for _stage: int in range(run.settings.nest_upgrade_costs.size()):
			run.upgrade_nest(nest.nest_id)
		# Settle the existing flower artwork immediately for this F6 entry point.
		_nest_views[nest.nest_id - 1]._art.set_stage(nest.level, false)
	if _completion_tween != null:
		_completion_tween.kill()
	# Apply the actual restoration presentation before its normal victory sequence.
	for _step: int in range(80):
		_view._process(1.0)
		_restoration._process(1.0)
		if _restoration.phase == PlanetRestoration.Phase.IDLE:
			break
	_show_completion()
