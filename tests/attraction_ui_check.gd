extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const BranchScript = preload("res://scripts/ui/technology_branch.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")

var _failures: Array[String] = []
var _capture: bool = false


func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_run_checks.call_deferred()


func _run_checks() -> void:
	root.mode = Window.MODE_WINDOWED
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		var demo: DemoScript = DemoScene.instantiate() as DemoScript
		root.add_child(demo)
		current_scene = demo
		demo.set_process(false)
		demo._layout.set_process(false)
		demo._window_has_focus = true
		await _settle()
		await _check_tree(demo, resolution)
		for audio: AudioStreamPlayer in demo.get_node("Audio").get_children():
			audio.stop()
		current_scene = null
		demo.queue_free()
		await process_frame
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print(
			"PASS: five technology rows, compact pipe feedback, capture radius and quick-tool mapping"
		)
	quit(0 if _failures.is_empty() else 1)


func _check_tree(demo: DemoScript, resolution: Vector2i) -> void:
	demo.run.candy = 360
	demo._refresh_hud()
	demo._layout._show_technology()
	demo._drive_tool(0.0, Vector2.ZERO, false)
	await _settle()
	_check(
		demo._layout._branches.get_child_count() == 5,
		"the tree contains the five retained technologies"
	)
	_check(
		not demo._layout._branches.has_node("Attraction"), "the attraction technology row is absent"
	)
	_check(
		DiskDemoLayout.BRANCH_IDS[0] == "pipe" and DiskDemoLayout.BRANCH_IDS[1] == "net",
		"quick tool IDs preserve pipe and net ordering"
	)
	for index: int in range(DiskDemoLayout.BRANCH_IDS.size()):
		var branch: BranchScript = demo._layout._branches.get_child(index) as BranchScript
		_check(
			branch.technology_id == DiskDemoLayout.BRANCH_IDS[index],
			"retained branch rows match their purchase IDs"
		)
	var pipe_level: int = demo.run.pipe_level
	var capture_radius: float = demo.run.get_pipe_radius()
	var capture_seconds: float = demo.run.get_pipe_capture_seconds()
	_check_layout(demo)
	if _capture:
		await _save("five_technologies_%dx%d.png" % [resolution.x, resolution.y])
	var screen: Vector2 = root.get_visible_rect().size
	var pointer: Vector2 = (
		demo._world.get_global_transform_with_canvas().affine_inverse()
		* (screen * Vector2(0.5, 0.60))
	)
	demo._layout.close_panels()
	demo._drive_tool(0.0, pointer, false)
	_check(demo._pipe.visible and demo._pipe.active, "P1 retains active pipe feedback")
	_check(demo._pipe.radius == 24.0, "compact feedback preserves the actual capture radius")
	if _capture:
		await _save("pipe_compact_feedback_%dx%d.png" % [resolution.x, resolution.y])
	demo._layout._request_quick_upgrade(0)
	_check(
		demo.run.pipe_level == pipe_level + 1, "the first quick upgrade still improves pipe speed"
	)
	_check(
		demo.run.get_pipe_capture_seconds() < capture_seconds,
		"pipe speed upgrades still reduce processing time"
	)
	_check(
		demo.run.get_pipe_radius() == capture_radius,
		"speed upgrades preserve the actual capture radius"
	)
	demo._layout._request_quick_upgrade(1)
	_check(demo.run.net_unlocked, "the second quick upgrade still unlocks the net")
	demo._layout._hide_quick_upgrades()
	demo._view.zoom_steps(-1.0)
	demo._drive_tool(0.0, pointer, false)
	_check(
		not demo._pipe.visible and not demo._can_collect(pointer, 24.0),
		"P2 continues to disable manual collection"
	)
	demo._update_nest_hover(
		demo._world.get_global_transform_with_canvas() * demo.run.nests[0].position
	)
	_check(demo.selected_nest_id == -1, "P2 continues to disable governance")


func _check_layout(demo: DemoScript) -> void:
	var card: Rect2 = demo._layout._tool_card.get_global_rect()
	_check(
		Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(card),
		"the full technology card fits the viewport"
	)
	for row: BranchScript in demo._layout._branches.get_children():
		_check(card.encloses(row.get_global_rect()), "every technology row stays inside the card")
		var description: Rect2 = row.get_node("Content/Progress/Description").get_global_rect()
		var action: Rect2 = row.get_node("Content/Action").get_global_rect()
		_check(not description.intersects(action), "description and purchase button do not overlap")
		for stage: PanelContainer in row._stage_panels:
			_check(
				row.get_global_rect().encloses(stage.get_global_rect()),
				"all stage nodes fit their own row"
			)


func _settle() -> void:
	for _frame: int in range(4):
		await process_frame


func _save(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check(
		root.get_texture().get_image().save_png("res://artifacts/" + filename) == OK,
		"saved " + filename
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
