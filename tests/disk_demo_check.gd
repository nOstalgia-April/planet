extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")

var _failures: int = 0


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1920, 1080)
		await process_frame
		await process_frame
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	await process_frame
	demo.set_process(false)
	demo.run.advance(2.0)
	_check(demo.get_node("World/Nests").get_child_count() == 3, "initial nests connected")
	var initial_slimes: int = demo.get_node("World/Slimes").get_child_count()
	_check(
		initial_slimes == 3 * int(2.0 / demo.run.settings.spawn_intervals[0]),
		"spawn signals create actors"
	)
	var views: Node2D = demo.get_node("World/Nests") as Node2D
	var nest_view: NestView = views.get_child(1) as NestView
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = nest_view.get_global_transform_with_canvas() * Vector2(0.0, -45.0)
	if DisplayServer.get_name() == "headless":
		nest_view.get_node("SelectionArea").input_event.emit(root, click, 0)
	else:
		await physics_frame
		root.push_input(click, true)
		await physics_frame
		await process_frame
		click = click.duplicate() as InputEventMouseButton
		click.pressed = false
		root.push_input(click, true)
	_check(demo.selected_nest_id == nest_view.nest_id, "raised nest mouse event selects detail")
	var slime_root: Node2D = demo.get_node("World/Slimes") as Node2D
	var slime: PrototypeSlime = slime_root.get_child(0) as PrototypeSlime
	for actor: PrototypeSlime in demo._slimes:
		actor.set_process(false)
	var capture_point: Vector2 = slime.get_capture_point()
	var expected_count: int = 1
	if "--capture" in OS.get_cmdline_user_args():
		demo._drive_tool(0.12, capture_point, true)
		await RenderingServer.frame_post_draw
		_save_frame("disk_demo_pipe_attraction.png")
	demo._capture_at(demo.run.get_pipe_capture_seconds(), capture_point, true)
	await process_frame
	_check(
		demo.run.candy == 0 and demo.run.pending_slime_count == expected_count,
		"holding accumulates nearby monsters without paying"
	)
	_check(
		slime_root.get_child_count() == initial_slimes - expected_count,
		"collected actors disappear and free their population slots immediately"
	)
	_check(demo.get_node("World/Effects").get_child_count() == 0, "pickup has no candy effect")
	if "--capture" in OS.get_cmdline_user_args():
		demo._drive_tool(0.0, capture_point, true)
		await RenderingServer.frame_post_draw
		_save_frame("disk_demo_collection_hold.png")
	demo._drive_tool(0.0, capture_point, false)
	_check(
		demo.run.candy == expected_count * demo.run.settings.slime_reward,
		"release beside the planet pays the whole collection immediately"
	)
	_check(
		demo.run.pending_candy == 0 and demo.run.pending_slime_count == 0,
		"release clears the batch"
	)
	_check(
		demo.get_node("World/Effects").get_child_count() == 1,
		"release plays one total reward effect"
	)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		_save_frame("disk_demo_collection_settled.png")
	demo._drive_tool(0.0, capture_point, false)
	_check(
		demo.run.candy == expected_count * demo.run.settings.slime_reward,
		"repeated release cannot pay twice"
	)
	_check(not demo.has_node("Flight"), "screen-exit transport removed from the active scene")
	var nest_budget_cost: int = 0
	for cost: int in demo.run.settings.nest_upgrade_costs:
		nest_budget_cost += cost
	demo.run.candy = (
		nest_budget_cost * demo.run.settings.nest_budget
		+ demo.run.settings.pipe_upgrade_costs[0]
		+ 100
	)
	demo.run.economy_changed.emit()
	demo.get_node("%ToolButton").pressed.emit()
	_check(
		demo.run.pipe_level == 1 and demo.run.net_level == 0,
		"pipe button upgrades only processing speed"
	)
	demo._drive_tool(0.0, Vector2.LEFT * 240.0, false)
	if "--capture" in OS.get_cmdline_user_args():
		demo.run.advance(20.0)
		for nest: NestState in demo.run.nests:
			_check(nest.alive_slimes == 10, "initial nests stop at ten surface monsters")
		await create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		_save_frame("disk_demo_play.png")
		demo.get_node("%NetToolButton").pressed.emit()
		_check(demo._active_tool == DemoScript.ToolMode.NET, "net selector switches tool")
		for actor: PrototypeSlime in demo._slimes:
			actor.set_process(false)
		var net_pointer: Vector2 = demo._slimes[0].get_capture_point()
		var before_net: int = demo.run.candy
		demo._drive_tool(demo._net.cast_seconds, net_pointer, true)
		demo._drive_tool(demo._net.close_seconds * 0.5, net_pointer, false)
		await RenderingServer.frame_post_draw
		_save_frame("disk_demo_net_open.png")
		demo._drive_tool(demo._net.close_seconds * 0.51, net_pointer, false)
		await RenderingServer.frame_post_draw
		_save_frame("disk_demo_net_burst.png")
		var net_reward: int = demo._net_caught_count * demo.run.settings.slime_reward
		_check(
			net_reward > 0 and demo._net_caught_count <= demo.run.get_net_capacity(),
			"net finishes automatically within its capacity"
		)
		_check(
			demo.run.candy == before_net + net_reward and demo.run.pending_candy == 0,
			"net pays directly without mouse hold or pipe processing"
		)
		demo._drive_tool(demo.net_result_seconds + 0.01, net_pointer, false)
		demo._drive_tool(0.0, net_pointer, false)
		demo.get_node("%ToolButton").pressed.emit()
		_check(
			demo.run.net_level == 1 and demo.run.pipe_level == 1,
			"net button upgrades only capacity"
		)
		_check(not demo.run.can_cast_net(), "net upgrade preserves the active cooldown")
		await RenderingServer.frame_post_draw
		_save_frame("disk_demo_net_cooldown.png")
	for nest_id: int in range(1, demo.run.settings.nest_budget + 1):
		demo._select_nest(nest_id)
		for _level: int in range(demo.run.settings.nest_upgrade_costs.size()):
			demo.get_node("%NestButton").pressed.emit()
	_check(demo.run.generated_nests == 5, "finite refill creates all five views")
	_check(demo.run.is_complete, "goal completion connected")
	await create_timer(1.7).timeout
	var completion: Control = demo.get_node("%Completion") as Control
	_check(completion.visible, "completion appears after color restoration")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		_save_frame("disk_demo_complete.png")
		demo._close_victory()
		await process_frame
		await RenderingServer.frame_post_draw
		_save_frame("disk_demo_restored.png")
	demo.get_node("%ReplayButton").pressed.emit()
	_check(not demo.run.is_complete and demo.run.candy == 0, "replay resets rules")
	_check(not completion.visible and views.get_child_count() == 3, "replay resets visuals")
	await process_frame
	_check(slime_root.get_child_count() == 0, "old slime actors cleared on replay")
	if _failures == 0:
		print(
			"PASS: responsive disk demo, single pipe processing, net burst, independent upgrades, nest caps and replay"
		)
	quit(0 if _failures == 0 else 1)


func _save_frame(filename: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var frame: Image = root.get_texture().get_image()
	var result: Error = frame.save_png("res://artifacts/" + filename)
	_check(result == OK, "screenshot saved: " + filename)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
