extends SceneTree

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")

var _failures: int = 0


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	_check_value_purchases()
	_check_fractional_combo()
	await _check_live_rewards()
	if _failures == 0:
		print(
			"PASS: value purchases, live species and gold rewards, in-flight net, percentage carry, automation and reset"
		)
	quit(0 if _failures == 0 else 1)


func _check_value_purchases() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	var fixed_pipe_cost: int = run.get_pipe_upgrade_cost()
	for expected: int in [4, 10, 20, 50]:
		var cost: int = run.get_technology_cost("base_value")
		run.candy = cost - 1
		var level: int = run.base_value_level
		_check(
			not run.purchase_technology("base_value"), "An underfunded breakthrough is rejected."
		)
		_check(
			run.candy == cost - 1 and run.base_value_level == level,
			"Failure preserves money and level."
		)
		run.candy += 1
		_check(
			run.purchase_technology("base_value") and run.candy == 0, "A breakthrough charges once."
		)
		_check(run.get_base_value() == expected, "Breakthroughs follow the configured value curve.")
		_check(
			run.get_capture_reward(NestState.Species.MUCUS, true) == expected * 6,
			"Gold and species multipliers compose."
		)
		_check(
			run.get_pipe_upgrade_cost() == fixed_pipe_cost,
			"Existing upgrade prices do not inflate with income."
		)
	run.candy = 100000
	_check(
		not run.purchase_technology("base_value") and run.candy == 100000,
		"Maximum value refuses further charges."
	)
	run._add_nest(NestState.Species.MUCUS, Vector2(300, -200))
	run.get_nest(3).alive_slimes = 2
	run.net_unlocked = true
	_check(
		run.collect_net_batch([3]) == 100,
		"Default model net rewards include species and global value."
	)
	run.candy = 0
	_check(
		run.collect_slime(3) and run.candy == 100, "Default model pipe rewards use the same value."
	)
	_check(SETTINGS.slime_reward == 2, "Research never mutates shared settings.")
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	_check(
		run.base_value_level == 0 and run.get_base_value() == 2, "Restart restores initial value."
	)
	run.free()


func _check_fractional_combo() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	run.combo_level = 1
	run.get_nest(1).alive_slimes = 20
	for _index: int in range(6):
		run.collect_slime(1)
	_check(
		run.candy == 12 and run._combo_reward_remainder == 50,
		"Half a candy is retained, never rounded up per capture."
	)
	run.advance(3.1)
	run.get_nest(1).alive_slimes = 20
	for _index: int in range(6):
		run.collect_slime(1)
	_check(
		run.candy == 25 and run._combo_reward_remainder == 0,
		"Earned fractions survive a broken streak."
	)
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	_check(
		run.combo_level == 0 and run._combo_reward_remainder == 0,
		"Restart clears combo research and fractions."
	)
	run.free()


func _check_live_rewards() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	demo.run.candy = 100000
	demo.run.purchase_technology("pipe")
	demo.run.purchase_technology("net_unlock")
	demo.run.purchase_technology("combo_unlock")
	demo.run.purchase_technology("cultivation")
	demo.run.purchase_technology("automation")
	for _stage: int in range(3):
		demo.run.upgrade_nest(2)
	demo.run._add_nest(NestState.Species.MUCUS, demo._planet.get_nest_position(-0.8))
	var basic: PrototypeSlime = _spawn(demo, 1)
	demo.run.valuable_level = 1
	demo._spawn_directions[1] = 8
	var golden: PrototypeSlime = _spawn(demo, 1)
	demo._spawn_directions[3] = 1
	var mucus: PrototypeSlime = _spawn(demo, 3)
	_check(
		basic.reward == 2 and golden.reward == 6 and mucus.reward == 4,
		"Fixture has existing basic, gold and mucus actors."
	)
	demo.run.purchase_technology("base_value")
	_check(
		basic.reward == 4 and golden.reward == 12 and mucus.reward == 8,
		"Existing actors immediately receive the breakthrough."
	)
	var automated: NestState = demo.run.get_nest(2)
	automated.income_remainder = 0.75
	var before: int = demo.run.candy
	demo.run._advance_automatic_income(automated, 0.125)
	_check(
		demo.run.candy == before + 1 and is_equal_approx(automated.income_remainder, 0.5),
		"Scaled automatic income preserves its earned fraction."
	)
	_check(
		is_equal_approx(demo.run.get_passive_income(), 6.0),
		"Income display reports the upgraded rate."
	)
	for actor: PrototypeSlime in [basic, golden, mucus]:
		actor.position = Vector2(0, -190)
	demo.run.combo_count = 5
	demo.run.combo_remaining = 3.0
	demo._select_tool(DemoScript.ToolMode.NET)
	demo._start_net(Vector2(0, -190))
	demo.run.purchase_technology("base_value")
	before = demo.run.candy
	demo._advance_net(demo._net.cast_seconds)
	demo._advance_net(demo._net.close_seconds)
	_check(
		demo._net_caught_count == 3 and demo.run.candy == before + 60,
		"A net already in flight settles all species at the new value."
	)
	_check(
		demo.run.combo_count == 5 and demo.run.combo_remaining == 3.0,
		"The net neither rewards nor renews combo."
	)
	var fresh: PrototypeSlime = _spawn(demo, 1)
	_check(fresh.reward == 10, "Future actors receive the same current value.")
	fresh.position = Vector2(0, -190)
	before = demo.run.candy
	demo._capture_at(2.0, fresh.get_capture_point(), true)
	_check(
		demo.run.candy == before + 12 and demo.run._combo_reward_remainder == 50,
		"Real suction pays current value plus its fractional percentage bonus."
	)
	demo.restart_run()
	_check(
		demo.run.get_base_value() == 2 and demo._slimes.is_empty(),
		"Live restart clears research and the old actors."
	)
	current_scene = null
	demo.queue_free()
	await process_frame


func _spawn(demo: DemoScript, nest_id: int) -> PrototypeSlime:
	demo.run.get_nest(nest_id).alive_slimes += 1
	demo._on_slime_requested(nest_id)
	var actor: PrototypeSlime = demo._slimes.back()
	actor._process(actor.launch_seconds)
	actor.set_process(false)
	return actor


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
