extends Node

const SETTINGS: PrototypeSettings = preload("res://resources/prototype_settings.tres")
const DemoScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")
const PageScript = preload("res://scripts/ui/technology_page.gd")
const InteractivePageScript = preload("res://scripts/ui/interactive_technology_page.gd")
const VacuumSkin = preload("res://scripts/vacuum_skin.gd")
const ComboMeter = preload("res://scripts/ui/combo_meter.gd")
const OUTPUT: String = "res://artifacts/combo_meter_gradient_20261015"

var _failures: int = 0
var _completions: Array[Vector2i] = []


func _ready() -> void:
	# Isolate scripted pointer events from desktop mouse motion during rendered checks.
	get_tree().root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
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
	run.combo_stage_completed.connect(
		func(stage: int, bonus: int) -> void: _completions.append(Vector2i(stage, bonus))
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
		var bonus: int = (
			SETTINGS.combo_stage_targets[stage] * 4 * SETTINGS.combo_reward_percentages[stage] / 100
		)
		expected += bonus
		_check(run.candy == expected, "whole stage value pays the exact bonus")
		_check(_completions[-1] == Vector2i(stage + 1, bonus), "one completion fact per stage")
		_check(run.combo_count == 0 and run.combo_stage_candy == 0, "stage accumulation clears")
		if stage < 3:
			_check(
				run.combo_remaining == 5.0 and run.combo_stage == stage + 1,
				"next stage timer starts immediately"
			)
	_check(
		run.combo_remaining == 0.0 and run.combo_stage == 0, "highest stage waits for next capture"
	)
	_check(_completions.size() == 4, "four awards per full cycle")
	run.collect_slime(1, 4)
	run.advance(4.9)
	run.collect_slime(1, 4)
	_check(is_equal_approx(run.combo_remaining, 0.1), "second capture never renews deadline")
	var balance: int = run.candy
	run.advance(0.11)
	_check(
		run.combo_count == 0 and run.combo_stage == 0 and run.candy == balance,
		"timeout preserves normal and completed rewards"
	)
	_check(run.combo_level == 4, "timeout preserves research")
	for capture: int in range(3):
		run.collect_slime(1, 4)
	_check(run.combo_stage == 1 and run.combo_count == 0, "empty second stage is timed")
	run.advance(5.0)
	_check(run.combo_stage == 0 and run.combo_remaining == 0.0, "empty advanced stage also expires")
	run.combo_level = 1
	balance = run.candy
	run.collect_slime(1, 100, 36)
	_check(
		run.combo_count == 1 and run.combo_stage_candy == 100,
		"giant counts once and retains full value"
	)
	run.collect_slime(1, 4)
	run.collect_slime(1, 4)
	_check(run.candy == balance + 108 + 27, "giant value participates in the stage bonus")
	_check(run.combo_stage == 0 and run.combo_remaining == 0.0, "tier one loops immediately")
	run.collect_slime(1, 4)
	run.net_unlocked = true
	balance = run.candy
	run.collect_net_batch([1, 1], [4, 4])
	_check(
		run.candy == balance + 8 and run.combo_count == 1 and run.combo_stage_candy == 4,
		"net pays normally without entering the ladder"
	)
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
	_check(
		run.candy == 8 and run._combo_reward_remainder == 50,
		"fractions survive timeout without paying incomplete stage"
	)
	run.start_run([Vector2(-100, -200), Vector2(100, -200)])
	_check(
		run.combo_level == 0 and run._combo_reward_remainder == 0, "restart clears run and research"
	)
	run.free()


func _check_scene() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	get_tree().root.add_child(demo)
	# Desktop focus changes must not hide the vacuum during scripted screenshots.
	get_window().focus_exited.disconnect(demo._on_window_focus_exited)
	get_window().focus_entered.disconnect(demo._on_window_focus_entered)
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
	demo._pipe.combo_meter.set_process(false)
	_check(
		not page._nodes.has("combo_reward") and not page._nodes.has("combo_interval"),
		"old tree nodes removed"
	)
	_check(
		page.TECHNOLOGIES.count("combo_unlock") == 1 and page._max_level("combo_unlock") == 4,
		"one upgradable four-level technology node"
	)
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_window().size = resolution
		demo._layout._show_technology()
		await _settle()
		page._show_details("combo_unlock")
		await _settle()
		# The opening view intentionally shows the starting rows; later research is reached by panning.
		for node: Control in page._nodes.values():
			_check(
				Rect2(Vector2.ZERO, page.graph.size).encloses(node.get_rect()),
				(
					"technology fits graph: %s at %dx%d, node=%s, graph=%s"
					% [node.name, resolution.x, resolution.y, node.get_rect(), page.graph.size]
				)
			)
			for other: Control in page._nodes.values():
				if node != other:
					_check(
						not node.get_global_rect().intersects(other.get_global_rect()),
						"technology hit regions do not overlap"
					)
		var interactive: InteractivePageScript = page as InteractivePageScript
		var original_center: Vector2 = interactive.view_center
		for node: Control in page._nodes.values():
			interactive.set_view_center(node.get_rect().get_center())
			await _settle()
			_check(
				page._canvas.get_global_rect().encloses(node.get_global_rect()),
				"panning fully reveals technology: " + node.name
			)
			var motion: InputEventMouseMotion = InputEventMouseMotion.new()
			motion.position = node.get_global_rect().get_center()
			motion.global_position = motion.position
			get_viewport().push_input(motion, true)
			await _settle()
			_check(
				get_viewport().gui_get_hovered_control() == node,
				"revealed technology receives pointer input: " + node.name
			)
		interactive.set_view_center(original_center)
		page._show_details("combo_unlock")
		await _settle()
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
		_check(
			demo._pipe._art.requested_skin == VacuumSkin.SkinKind.RAINBOW,
			"completion requests rainbow"
		)
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
		_check(
			demo._pipe._art.current_skin == VacuumSkin.SkinKind.PINK, "burst fades to species color"
		)
		await get_tree().create_timer(1.3).timeout
		_check(demo._pipe.get_node("Bursts").get_child_count() == 0, "effects clean themselves up")
		await _save("restored_%dx%d" % [resolution.x, resolution.y])
		await _check_meter(demo, resolution)
	demo._pipe.play_combo_burst(4, 100)
	demo.restart_run()
	_check(
		demo._pipe._combo_bursts.is_empty() and not demo._pipe._combo_active,
		"restart cancels pending feedback"
	)
	demo._pipe.combo_meter.refresh()
	_check(
		not demo._pipe.combo_meter.visible and demo._pipe.combo_meter.displayed_count == 0,
		"restart hides the locked meter and clears its displayed progress"
	)
	demo.queue_free()
	await _settle()


func _check_meter(demo: DemoScript, resolution: Vector2i) -> void:
	var meter: ComboMeter = demo._pipe.combo_meter
	demo.run._reset_combo()
	demo.run.get_nest(1).alive_slimes = 200
	demo._pipe.reset_skin()
	meter.reset_feedback()
	meter.refresh()
	demo._pipe.show()
	demo._pipe.set_tool_state(Vector2(0, -235), Vector2(0, -235), true)
	meter.refresh()
	var tool_image: Image = demo._pipe._art.default_frames[0].get_image()
	if tool_image.is_compressed():
		tool_image.decompress()
	var tool_width: float = (
		tool_image.get_used_rect().size.x
		* demo._pipe._art.get_global_transform_with_canvas().x.length()
	)
	var meter_width: float = (
		(meter.get_global_transform_with_canvas() * meter.get_meter_rect()).size.x
	)
	_check(
		absf(meter_width / tool_width - 0.8 / 3.0) < 0.01,
		"meter width is one third of the previous eighty-percent vacuum width"
	)
	_check(
		(
			meter.visible
			and meter.displayed_stage == 0
			and meter.displayed_count == 0
			and meter.segment_count == SETTINGS.combo_stage_targets[0]
			and is_zero_approx(meter.time_ratio)
		),
		"an unlocked idle meter shows three empty segments without a deadline"
	)
	_check(
		demo._layout.get_node_or_null("ComboChip") == null, "the old numeric combo panel is absent"
	)
	_check(
		meter.find_children("*", "Label", true, false).is_empty(),
		"the meter displays no numeric requirement labels"
	)
	await _save("meter_idle_%dx%d" % [resolution.x, resolution.y])
	for stage: int in range(4):
		var target: int = SETTINGS.combo_stage_targets[stage]
		for index: int in range(target):
			var cell: Rect2 = meter.get_cell_rect(index)
			_check(
				cell.has_area() and meter.get_fill_rect().grow(0.0001).encloses(cell),
				"each capture has a positive interval inside the gradient strip"
			)
			if index > 0:
				_check(
					is_equal_approx(meter.get_cell_rect(index - 1).end.x, cell.position.x),
					"capture steps share a continuous strip without block gaps"
				)
		_check(
			(
				meter.displayed_stage == stage
				and meter.displayed_count == 0
				and meter.segment_count == target
			),
			"each stage opens with its configured number of empty segments"
		)
		for capture: int in range(target - 1):
			_check(demo.run.collect_slime(1, 4), "meter fixture capture is accepted")
			meter.refresh()
			_check(
				meter.displayed_stage == stage and meter.displayed_count == capture + 1,
				"one confirmed capture lights exactly one segment"
			)
		demo.run.advance(1.0)
		meter.refresh()
		_check(
			is_equal_approx(meter.time_ratio, 0.8),
			"the small timer reflects the real fixed stage deadline"
		)
		await _save("meter_stage_%d_partial_%dx%d" % [stage + 1, resolution.x, resolution.y])
		_check(demo.run.collect_slime(1, 4), "final stage capture is accepted")
		meter.refresh()
		_check(
			(
				meter.displayed_stage == stage
				and meter.displayed_count == target
				and meter.segment_count == target
			),
			"the completed outgoing stage remains fully lit after the model advances"
		)
		await _save("meter_stage_%d_full_%dx%d" % [stage + 1, resolution.x, resolution.y])
		meter._process(1.0)
		meter.refresh()
		_check(
			meter.displayed_stage == demo.run.combo_stage and meter.displayed_count == 0,
			"completion feedback releases to the current empty stage"
		)
	_check(
		meter.displayed_stage == 0 and is_zero_approx(meter.time_ratio),
		"the final rainbow stage returns to an idle first stage"
	)
	for capture: int in range(SETTINGS.combo_stage_targets[0]):
		demo.run.collect_slime(1, 4)
	_check(meter.displayed_count == 3, "first stage completion begins its full-bar hold")
	demo.run.collect_slime(1, 4)
	meter.refresh()
	_check(
		meter.displayed_stage == 1 and meter.displayed_count == 1 and meter.segment_count == 5,
		"a fast next capture interrupts the hold and immediately lights its new segment"
	)
	demo._pipe.hide()
	_check(not meter.is_visible_in_tree(), "the meter hides together with the vacuum")
	demo._pipe.show()
	_check(meter.is_visible_in_tree(), "the meter returns with the vacuum")
	demo.run.advance(SETTINGS.combo_window_seconds)
	meter.refresh()
	_check(
		(
			meter.displayed_stage == 0
			and meter.displayed_count == 0
			and meter.segment_count == 3
			and is_zero_approx(meter.time_ratio)
		),
		"a timeout immediately clears progress and returns to the first stage"
	)
	_check_meter_capture(demo)
	await _check_meter_edges(demo, resolution)
	demo._pipe.reset_skin()
	demo.run._reset_combo()
	meter.reset_feedback()
	meter.refresh()
	demo._pipe.set_tool_state(Vector2(0, -235), Vector2(0, -235), true)


func _check_meter_capture(demo: DemoScript) -> void:
	var target: Vector2 = Vector2(0, -235)
	demo._on_slime_requested(1)
	var actor: PrototypeSlime = demo._slimes[-1]
	actor._process(actor.launch_seconds)
	actor.set_process(false)
	actor.position = target
	actor._update_surface_rotation()
	actor.position += target - actor.get_capture_point()
	demo._capture_at(demo.run.get_pipe_capture_seconds(), target, true)
	demo._pipe.combo_meter.refresh()
	_check(
		(
			not demo._slimes.has(actor)
			and demo.run.combo_count == 1
			and demo._pipe.combo_meter.displayed_count == 1
		),
		"a real vacuum capture removes one actor and lights exactly one segment"
	)


func _check_meter_edges(demo: DemoScript, resolution: Vector2i) -> void:
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var anchors: Array[Vector2] = [
		Vector2(32.0, screen_size.y * 0.60),
		Vector2(screen_size.x - 32.0, screen_size.y * 0.60),
		Vector2(screen_size.x * 0.5, 48.0)
	]
	for index: int in range(anchors.size()):
		var world_point: Vector2 = (
			demo._world.get_global_transform_with_canvas().affine_inverse() * anchors[index]
		)
		demo._pipe.set_tool_state(world_point, world_point, true)
		demo._pipe.combo_meter._process(0.0)
		var transform: Transform2D = demo._pipe.combo_meter.get_global_transform_with_canvas()
		_check(
			is_zero_approx(transform.get_rotation()),
			"the segmented meter stays upright across vacuum positions"
		)
		var screen_bounds: Rect2 = transform * demo._pipe.combo_meter.get_meter_rect().grow(1.5)
		_check(
			Rect2(Vector2.ZERO, screen_size).encloses(screen_bounds),
			"the meter and shadow remain fully visible at the viewport edges"
		)
		if index < 2:
			_check(
				transform.origin.y < demo._pipe._art.get_global_transform_with_canvas().origin.y,
				"the meter remains above the vacuum artwork at either side edge"
			)
		await _save("meter_edge_%d_%dx%d" % [index, resolution.x, resolution.y])


func _settle() -> void:
	for frame: int in range(6):
		await get_tree().process_frame


func _save(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await RenderingServer.frame_post_draw
	_check(
		get_viewport().get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK,
		"screenshot saved"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
