extends Node

const StoryGame = preload("res://features/tutorial_intro/story_game.gd")
const Flow = preload("res://features/tutorial_intro/story_flow.gd")

@export var game: StoryGame


func _ready() -> void:
	GameAudio.play_music("event:/Mx/Mx_GamePlay")


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			game.story.cancel()
			get_tree().paused = false
			get_tree().change_scene_to_file.call_deferred("res://scenes/主菜单/主菜单.tscn")
		elif key.pressed and not key.echo and key.keycode == KEY_R:
			get_viewport().set_input_as_handled()
			get_tree().paused = false
			game.restart_run()
		elif key.pressed and not key.echo and key.keycode == KEY_N:
			get_viewport().set_input_as_handled()
			advance_preview()


func advance_preview() -> void:
	if get_tree().paused or game.story.phase != Flow.Phase.IDLE:
		return
	if game._view.presentation_locked or game.run.is_complete:
		return
	game._layout.close_panels()
	game.run.candy = maxi(game.run.candy, 100000)
	if Flow.Kind.CULTIVATION not in game.story.seen:
		game.run.purchase_technology("cultivation")
		return
	if Flow.Kind.AUTOMATION not in game.story.seen:
		game.run.purchase_technology("automation")
		return
	for species: int in range(3):
		if species in game._restoration.unlocked_species:
			continue
		var target: NestState
		for nest: NestState in game.run.nests:
			if nest.species == species:
				target = nest
				break
		if target == null:
			game.run._add_nest(
				species as NestState.Species,
				game._planet.get_nest_position(2.0 if species == 1 else -2.0)
			)
			target = game.run.nests.back()
		while not target.is_tamed:
			if not game.run.upgrade_nest(target.nest_id):
				return
		return
	for nest: NestState in game.run.nests:
		while not nest.is_tamed:
			if not game.run.upgrade_nest(nest.nest_id):
				return
	var slimes: Array[PrototypeSlime] = game._slimes.duplicate()
	for slime: PrototypeSlime in slimes:
		game._finish_capture(slime)
