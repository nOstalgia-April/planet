extends Node

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")
const PlayScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const PlayScript = preload("res://features/场景预览/游玩预览.gd")

var _failures: Array[String] = []
var _goals: int = 0


func _ready() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	_check_color_last()
	_check_automation_last()
	_check_monster_last()
	await _check_real_flowers()
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print(
			"PASS: three colors AND full automation AND zero monsters; each final condition, actual flowers, duplicate colors and restart."
		)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _create_run() -> PrototypeRun:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS.duplicate() as PrototypeSettings
	add_child(run)
	run.start_run([Vector2(-80, -200), Vector2(80, -200)])
	run._add_nest(NestState.Species.MUCUS, Vector2(240, 0))
	run._add_nest(NestState.Species.DRILL, Vector2(-240, 0))
	run.candy = 100000
	run.purchase_technology("cultivation")
	run.purchase_technology("automation")
	_goals = 0
	run.goal_completed.connect(func() -> void: _goals += 1)
	return run


func _automate(run: PrototypeRun, nest_id: int) -> void:
	for _stage: int in range(3):
		_check(run.upgrade_nest(nest_id), "Fixture construction succeeds.")


func _check_color_last() -> void:
	var run: PrototypeRun = _create_run()
	for nest: NestState in run.nests:
		_automate(run, nest.nest_id)
	_check(not run.is_complete, "An empty automated planet without colors does not win.")
	run.record_flower(1)
	run.record_flower(2)
	_check(run.unlocked_colors == [0], "Two pink flowers unlock only one color.")
	run.record_flower(3)
	_check(not run.is_complete and _goals == 0, "Two colors cannot win an empty automated planet.")
	run.record_flower(4)
	_check(
		run.is_complete and _goals == 1,
		"The third actual flower can be the final victory condition."
	)
	run.record_flower(4)
	run.advance(200.0)
	_check(_goals == 1, "Repeated flowers and updates never repeat victory.")
	for nest: NestState in run.nests:
		_check(nest.alive_slimes == 0, "Victory does not restart monster production.")
	run.start_run([Vector2(-80, -200), Vector2(80, -200)])
	_check(
		not run.is_complete and run.unlocked_colors.is_empty(),
		"Restart clears victory and every color."
	)
	run.free()


func _check_automation_last() -> void:
	var run: PrototypeRun = _create_run()
	for nest_id: int in [1, 3, 4]:
		_automate(run, nest_id)
		run.record_flower(nest_id)
	_check(
		not run.is_complete, "Three colors and an empty planet still require every nest automated."
	)
	_automate(run, 2)
	_check(
		run.is_complete and _goals == 1, "The final empty nest's automation can complete victory."
	)
	run.free()


func _check_monster_last() -> void:
	var run: PrototypeRun = _create_run()
	run.get_nest(3).alive_slimes = 3
	run.get_nest(4).alive_slimes = 1
	for nest: NestState in run.nests:
		_automate(run, nest.nest_id)
		run.record_flower(nest.nest_id)
	_check(not run.is_complete, "Three colors and automation cannot ignore remaining monsters.")
	run.net_unlocked = true
	_check(
		run.collect_net_batch([3], [], [3]) == 0 and run.get_nest(3).alive_slimes == 3,
		"An immune fused body prevents net cleanup from completing victory."
	)
	_check(run.collect_slime(3, -1, 3), "Suction releases a fused body's complete population.")
	_check(
		not run.is_complete,
		"A remaining drill monster prevents victory after the fused body is caught."
	)
	_check(run.collect_slime(4), "The last drill monster can be captured.")
	_check(
		run.is_complete and _goals == 1, "The last drill capture completes all three conditions."
	)
	run.free()


func _check_real_flowers() -> void:
	var game: PlayScript = PlayScene.instantiate() as PlayScript
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.set_process(false)
	game.run._add_nest(NestState.Species.MUCUS, Vector2(240, 0))
	game.run._add_nest(NestState.Species.DRILL, Vector2(-240, 0))
	game.run.candy = 100000
	game.run.purchase_technology("cultivation")
	game.run.purchase_technology("automation")
	for nest: NestState in game.run.nests:
		_automate(game.run, nest.nest_id)
	_check(
		game.run.unlocked_colors.is_empty(),
		"Purchases do not unlock colors before the real flowers appear."
	)
	var deadline: int = Time.get_ticks_msec() + 12000
	while game.run.unlocked_colors.size() < 3 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(
		game.run.unlocked_colors.size() == 3,
		"All three real flower animations report color unlocks to the rules."
	)
	_check(
		game._restoration.unlocked_species.size() == 3,
		"Rules and restoration receive the same three flower events."
	)
	_check(
		game.run.is_complete,
		"The real scene wins after its final color when all nests are automated and empty."
	)
	game.restart_run()
	_check(
		game.run.unlocked_colors.is_empty() and game._restoration.unlocked_species.is_empty(),
		"The real scene resets both color states."
	)
	game.queue_free()
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
