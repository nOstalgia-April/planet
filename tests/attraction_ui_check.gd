extends SceneTree

const PageScript = preload("res://scripts/ui/technology_page.gd")
const DemoScript = preload("res://scripts/disk_demo.gd")
const NodeScript = preload("res://scripts/ui/technology_node.gd")
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
			"PASS: nine technology items, compact pipe feedback, capture radius and quick-tool mapping"
		)
	quit(0 if _failures.is_empty() else 1)


func _check_tree(demo: DemoScript, resolution: Vector2i) -> void:
	demo.run.candy = 360
	demo._refresh_hud()
	demo._layout._show_technology()
	demo._drive_tool(0.0, Vector2.ZERO, false)
	await _settle()
	_check(
		demo._layout._technology.TECHNOLOGIES.size() == 9,
		"the tree contains nine distinct technology items"
	)
	_check(
		not demo._layout._technology._nodes.has("attraction"),
		"the attraction technology row is absent"
	)
	_check(
		DiskDemoLayout.BRANCH_IDS[0] == "pipe" and DiskDemoLayout.BRANCH_IDS[1] == "net",
		"quick tool IDs preserve pipe and net ordering"
	)
	for id: String in DiskDemoLayout.BRANCH_IDS:
		var action: String = demo.run._resolve_technology_action(id)
		_check(
			demo._layout._technology._nodes[action].technology_id == action,
			"graph nodes match their purchase IDs"
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
	var page: PageScript = demo._layout._technology
	var card: Rect2 = page.get_global_rect()
	_check(
		Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(card),
		"technology page fits the viewport"
	)
	for node: NodeScript in page._nodes.values():
		_check(
			page._canvas.get_global_rect().encloses(node.get_global_rect()),
			"all nodes fit the canvas"
		)
	for node: NodeScript in page._nodes.values():
		_check(
			not node.get_global_rect().intersects(page.purchase.get_global_rect()),
			"graph nodes and purchase action do not overlap"
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
