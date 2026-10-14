extends Node

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")
const DemoScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")
const PageScript = preload("res://scripts/ui/technology_page.gd")
const VacuumSkin = preload("res://scripts/vacuum_skin.gd")
const OUTPUT: String = "res://artifacts/combo_ladder_20261014"

var _failures: int = 0
var _completions: Array[Vector2i] = []


func _ready() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	_check_rules()
	await _check_scene()
	print("Combo ladder check: %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_rules() -> void:
	var run: PrototypeRun = PrototypeRun.new()
	run.settings = SETTINGS.duplicate() as PrototypeSettings
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	run.combo_stage_completed.connect(func(stage: int, bonus: int) -> void:
		_completions.append(Vector2i(stage, bonus))
	)
	run.candy = 100000
	_check(not run.purchase_technology("combo_unlock"), "first tier requires efficiency two")
	_check(not run.purchase_technology("combo_4"), "separate stage buttons removed")
	_check(not run.purchase_technology("combo_interval"), "interval branch removed")
	_check(not run.purchase_technology("combo_reward"), "reward branch removed")
	_check(run.purchase_technology("pipe"), "efficiency prerequisite purchased")
	for tier: int in range(4):
		var before: int = run.candy
		_check(run.purchase_technology("combo"), "sequential shortcut purchases tier")
		_check(run.combo_level == tier + 1, "one permanent tier per purchase")
		_check(run.candy == before - SETTINGS.combo_upgrade_costs[tier], "tier cost paid once")
	_check(not run.purchase_technology("combo"), "maximum tier cannot be bought twice")
	run.candy = 0
	run.get_nest(1).alive_slimes = 200
	var expected: int = 0
	for stage: int in range(4):
		for capture: int in range(SETTINGS.combo_stage_targets[stage]):
			_check(run.collect_slime(1, 4), "capture accepted")
			expected += 4
			if capture + 1 < SETTINGS.combo_stage_targets[stage]:
				_check(run.candy == expected, "ordinary income paid before completion")
				run.advance(0.1)
		@warning_ignore("integer_division")
		var bonus: int = SETTINGS.combo_stage_targets[stage] * 4 * SETTINGS.combo_reward_percentages[stage] / 100
		expected += bonus
		_check(run.candy == expected, "whole stage value pays the exact bonus")
		_check(_completions[-1] == Vector2i(stage + 1, bonus), "one completion fact per stage")
		_check(run.combo_count == 0 and run.combo_stage_candy == 0, "stage accumulation clears")
		if stage < 3:
			_check(run.combo_remaining == 5.0 and run.combo_stage == stage + 1, "next stage timer starts immediately")
	_check(run.combo_remaining == 0.0 and run.combo_stage == 0, "highest stage waits for next capture")
	_check(_completions.size() == 4, "four awards per full cycle")
	run.collect_slime(1, 4)
	run.advance(4.9)
	run.collect_slime(1, 4)
	_check(is_equal_approx(run.combo_remaining, 0.1), "second capture never renews deadline")
	var balance: int = run.candy
	run.advance(0.11)
	_check(run.combo_count == 0 and run.combo_stage == 0 and run.candy == balance, "timeout preserves normal and completed rewards")
	_check(run.combo_level == 4, "timeout preserves research")
	for capture: int in range(3):
		run.collect_slime(1, 4)
	_check(run.combo_stage == 1 and run.combo_count == 0, "empty second stage is timed")
	run.advance(5.0)
	_check(run.combo_stage == 0 and run.combo_remaining == 0.0, "empty advanced stage also expires")
	run.combo_level = 1
	balance = run.candy
	run.collect_slime(1, 100, 36)
	_check(run.combo_count == 1 and run.combo_stage_candy == 100, "giant counts once and retains full value")
	run.collect_slime(1, 4)
	run.collect_slime(1, 4)
	_check(run.candy == balance + 108 + 27, "giant value participates in the stage bonus")
	_check(run.combo_stage == 0 and run.combo_remaining == 0.0, "tier one loops immediately")
	run.collect_slime(1, 4)
	run.net_unlocked = true
	balance = run.candy
	run.collect_net_batch([1, 1], [4, 4])
	_check(run.candy == balance + 8 and run.combo_count == 1 and run.combo_stage_candy == 4, "net pays normally without entering the ladder")
	_check(not run.collect_slime(999), "invalid capture rejected")
	_check(run.combo_count == 1, "invalid capture cannot advance progress")
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	run.combo_level = 1
	run.get_nest(1).alive_slimes = 10
	for capture: int in range(3):
		run.collect_slime(1)
	_check(run.candy == 3 and run._combo_reward_remainder == 75, "earned fractional bonus retained")
	run.collect_slime(1)
	run.advance(5.0)
	for capture: int in range(3):
		run.collect_slime(1)
	_check(run.candy == 8 and run._combo_reward_remainder == 50, "fractions survive timeout without paying incomplete stage")
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	_check(run.combo_level == 0 and run._combo_reward_remainder == 0, "restart clears run and research")
	run.free()


func _check_scene() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	get_tree().root.add_child(demo)
	demo.set_process(false)
	demo._view.set_process(false)
	demo._window_has_focus = true
	demo.run.candy = 100000
	demo.run.purchase_technology("pipe")
	var page: PageScript = demo._layout._technology
	await _settle()
	for tier: int in range(4):
		page._nodes["combo_unlock"].pressed.emit()
		await _settle()
		_check(demo.run.combo_level == tier + 1, "same technology button upgrades each tier")
	demo._pipe.set_process(false)
	demo._pipe._art.set_process(false)
	_check(not page._nodes.has("combo_reward") and not page._nodes.has("combo_interval"), "old tree nodes removed")
	_check(page.TECHNOLOGIES.count("combo_unlock") == 1 and page._max_level("combo_unlock") == 4, "one upgradable four-level technology node")
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_window().size = resolution
		demo._layout._show_technology()
		await _settle()
		page._show_details("combo_unlock")
		await _settle()
		for node: Control in page._nodes.values():
			_check(page._canvas.get_global_rect().encloses(node.get_global_rect()), "technology fits canvas")
			for other: Control in page._nodes.values():
				if node != other:
					_check(not node.get_global_rect().intersects(other.get_global_rect()), "technology hit regions do not overlap")
		await _save("tree_%dx%d" % [resolution.x, resolution.y])
		demo._layout.close_panels()
		demo.run._reset_combo()
		demo.run.get_nest(1).alive_slimes = 100
		demo._pipe.show()
		demo._pipe.set_tool_state(Vector2(0, -235), Vector2(0, -235), true)
		demo._pipe.show_capture_skin(PrototypeSlime.Species.SLIME)
		demo._pipe._art._process(1.0)
		demo.run.collect_slime(1, 4)
		demo.run.advance(1.0)
		demo._layout.refresh_timers(demo.run)
		await _save("progress_%dx%d" % [resolution.x, resolution.y])
		var remaining: float = demo.run.combo_remaining
		demo.set_process(true)
		get_tree().paused = true
		await _settle()
		_check(demo.run.combo_remaining == remaining, "pause freezes progress")
		get_tree().paused = false
		await _settle()
		demo.set_process(false)
		_check(demo.run.combo_remaining < remaining, "resume continues the real gameplay clock")
		demo._pipe.show()
		demo._pipe.set_tool_state(Vector2(0, -235), Vector2(0, -235), true)
		demo.run.collect_slime(1, 4)
		demo.run.collect_slime(1, 4)
		_check(demo._pipe._art.requested_skin == VacuumSkin.SkinKind.RAINBOW, "completion requests rainbow")
		demo._pipe._art._process(1.0)
		demo._pipe._advance_combo_burst(0.01)
		_check(demo._pipe.get_node("Bursts").get_child_count() > 0, "completion bursts from vacuum")
		await get_tree().create_timer(0.15).timeout
		await _save("rainbow_%dx%d" % [resolution.x, resolution.y])
		for stage: int in range(1, 4):
			for capture: int in range(SETTINGS.combo_stage_targets[stage]):
				demo.run.collect_slime(1, 4)
			demo._pipe._advance_combo_burst(3.0)
			demo._pipe._art._process(1.0)
			demo._pipe._advance_combo_burst(0.0)
			demo._pipe._art._process(1.0)
			demo._pipe._advance_combo_burst(0.01)
			await get_tree().create_timer(1.2 if stage < 3 else 0.15).timeout
		await _save("final_burst_%dx%d" % [resolution.x, resolution.y])
		demo._pipe._advance_combo_burst(3.0)
		demo._pipe._art._process(1.0)
		demo._pipe._advance_combo_burst(0.0)
		_check(demo._pipe._art.current_skin == VacuumSkin.SkinKind.PINK, "burst fades to species color")
		await get_tree().create_timer(1.3).timeout
		_check(demo._pipe.get_node("Bursts").get_child_count() == 0, "effects clean themselves up")
		await _save("restored_%dx%d" % [resolution.x, resolution.y])
	demo._pipe.play_combo_burst(4, 100)
	demo.restart_run()
	_check(demo._pipe._combo_bursts.is_empty() and not demo._pipe._combo_active, "restart cancels pending feedback")
	demo.queue_free()
	await _settle()


func _settle() -> void:
	for frame: int in range(6):
		await get_tree().process_frame


func _save(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK, "screenshot saved")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
