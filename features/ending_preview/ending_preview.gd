extends "res://features/tutorial_intro/story_game.gd"


func _ready() -> void:
	super._ready()
	_replay_ending.call_deferred()


func _replay_ending() -> void:
	restart_run()
	story.cancel()
	story.seen.assign(range(StoryFlow.Kind.OPENING, StoryFlow.Kind.RESCUE))
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
	# F6 starts with the earned colors already restored, then uses the formal ending.
	_restoration.restore_save({"completed": [0, 1, 2], "background": true})
	story.cancel()
	_view.zoom_steps(1.0, false)
	_show_completion()
