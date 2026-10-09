extends SceneTree

const PreviewScene: PackedScene = preload(
	"res://features/technology_tree_preview/technology_tree_preview.tscn"
)
const PreviewScript = preload("res://features/technology_tree_preview/technology_tree_preview.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const DemoScript = preload("res://scripts/disk_demo.gd")
const NodeScript = preload("res://scripts/ui/technology_node.gd")
const PageScript = preload("res://scripts/ui/technology_page.gd")

var _failures: int = 0
var _capture: bool = false


func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_check_page.call_deferred()


func _check_page() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var preview: PreviewScript = PreviewScene.instantiate() as PreviewScript
	root.add_child(preview)
	current_scene = preview
	await _settle()
	preview.set_preview(0)
	var page: PageScript = preview.page
	_check(page._nodes.size() == 9, "each upgrade item has exactly one icon")
	_check(page._nodes["pipe"].level_label.text == "1", "base speed is displayed as level one")
	_check(
		page._nodes["net_unlock"].state == NodeScript.State.LOCKED, "net requires speed level two"
	)
	_check(
		page._nodes["combo_unlock"].state == NodeScript.State.LOCKED,
		"combo requires speed level two"
	)
	_check(
		page._nodes["cultivation"].state == NodeScript.State.UNAFFORDABLE,
		"cultivation is available from the opening"
	)
	page.select_node("combo_interval")
	page.purchase.pressed.emit()
	_check(preview.run.combo_interval_level == 0, "locked interval cannot be purchased")
	preview.set_preview(1)
	await _settle()
	await _click(page._nodes["net_capacity"])
	_check(page.selected_key == "net_capacity", "mouse input can inspect a locked node")
	page.purchase.pressed.emit()
	_check(
		preview.run.net_level == 0 and preview.run.candy == 80,
		"rich wallets cannot bypass net unlock"
	)
	await _click(page._nodes["pipe"])
	await _click(page.purchase)
	_check(
		preview.run.pipe_level == 1 and preview.run.candy == 70,
		"first speed purchase charges its configured cost"
	)
	_check(page._nodes["pipe"].level_label.text == "2", "the same icon updates its current level")
	_check(
		(
			page._nodes["net_unlock"].state == NodeScript.State.AVAILABLE
			and page._nodes["combo_unlock"].state == NodeScript.State.AVAILABLE
		),
		"speed two opens both branches"
	)
	await _click(page.purchase)
	_check(
		preview.run.pipe_level == 2 and preview.run.candy == 40,
		"the same icon buys the next speed level"
	)
	page.select_node("net_unlock")
	page.purchase.pressed.emit()
	_check(
		preview.run.net_unlocked and preview.run.nests.size() == 2,
		"net unlock opens the tool without introducing a nest"
	)
	_check(page._note("net_unlock").is_empty(), "net details contain no nest-discovery promise")
	page.purchase.pressed.emit()
	_check(
		preview.run.nests.size() == 2 and preview.run.candy == 30,
		"unlock cannot charge twice or create nests"
	)
	page.select_node("net_capacity")
	page.purchase.pressed.emit()
	_check(
		preview.run.get_net_capacity() == 10 and preview.run.candy == 20,
		"capacity purchases work after unlock"
	)
	_check_model_branches(preview)
	preview.set_preview(3)
	page.select_node("valuable")
	_check(page.purchase.disabled, "regional research shows the selected nest's owned state")
	page._select_scope(1)
	page.purchase.pressed.emit()
	_check(
		preview.run.get_nest(2).valuable_level == 1 and preview.run.get_nest(1).valuable_level == 1,
		"regional purchase only affects the selected nest"
	)
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle()
		for state: int in range(4):
			preview.set_preview(state)
			await _settle()
			_check_layout(preview)
			if _capture:
				await _save("technology_page_%d_%dx%d.png" % [state, resolution.x, resolution.y])
		preview.set_preview(0)
		page.select_node("valuable")
		await _settle()
		if _capture:
			await _save("technology_page_locked_%dx%d.png" % [resolution.x, resolution.y])
	preview.queue_free()
	await process_frame
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	await _settle()
	demo.run.candy = 50
	demo.run.economy_changed.emit()
	demo._layout._show_technology()
	demo._layout._technology.select_node("pipe")
	demo._layout._technology.purchase.pressed.emit()
	_check(
		demo.run.pipe_level == 1 and demo.run.candy == 40,
		"the main demo uses the same page and real purchase handler"
	)
	_check(demo._layout.is_over_ui(Vector2(500, 400)), "the page blocks background input")
	demo._layout._technology.select_node("net_unlock")
	demo._layout._technology.purchase.pressed.emit()
	_check(
		demo.run.net_unlocked and demo._status_label.text.contains("捕网已解锁"),
		"the separate unlock item retains the main-game discovery feedback"
	)
	demo._layout._technology.select_node("combo_unlock")
	demo._layout._technology.purchase.pressed.emit()
	demo._layout._technology.select_node("combo_interval")
	demo._layout._technology.purchase.pressed.emit()
	_check(
		demo.run.combo_interval_level == 1 and demo._layout._combo_timer.max_value == 4.0,
		"interval purchases update the main HUD timer scale"
	)
	if _capture:
		await _settle()
		await _save("technology_page_demo_1920x1080.png")
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await process_frame
	_check(not demo._layout.is_technology_open(), "Escape returns to gameplay")
	demo._layout._show_technology()
	await _settle()
	await _click(demo._layout._technology.get_node("%Close") as Button)
	_check(not demo._layout.is_technology_open(), "the return button closes the page")
	demo.restart_run()
	_check(
		demo._layout._technology._nodes["pipe"].state == NodeScript.State.UNAFFORDABLE,
		"restart refreshes node ownership and wallet"
	)
	for child: Node in demo.get_node("Audio").get_children():
		if child is AudioStreamPlayer:
			child.stop()
	demo.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: technology states, real purchases, prerequisites, regional scope, reset and both resolutions"
		)
	quit(0 if _failures == 0 else 1)


func _check_model_branches(preview: PreviewScript) -> void:
	preview.set_preview(1)
	var run: PrototypeRun = preview.run
	run.candy = 10000
	var before: int = run.candy
	_check(
		not run.purchase_technology("combo_unlock") and not run.purchase_technology("net_unlock"),
		"both unlocks enforce speed two in the model"
	)
	_check(
		(
			not run.purchase_technology("combo_reward")
			and not run.purchase_technology("combo_interval")
		),
		"both combo upgrades require its unlock"
	)
	_check(
		run.get_technology_cost("combo_reward") == run.settings.combo_upgrade_costs[1],
		"locked reward advertises its own upgrade cost"
	)
	_check(
		(
			not run.purchase_technology("automation")
			and not run.purchase_nest_technology(1, "valuable")
		),
		"both governance branches require cultivation"
	)
	_check(run.candy == before, "failed prerequisites preserve candy")
	_check(
		run.purchase_technology("cultivation") and run.purchase_nest_technology(1, "valuable"),
		"valuable research follows cultivation directly"
	)
	_check(
		run.upgrade_nest(1) and not run.upgrade_nest(1),
		"cultivation only permits the first construction stage"
	)
	_check(
		run.purchase_technology("automation") and run.governance_level == 3,
		"automation research skips a separate half-governance technology"
	)
	_check(
		run.upgrade_nest(1) and run.upgrade_nest(1) and run.get_nest(1).is_tamed,
		"automation research permits the remaining local construction"
	)
	_check(
		run.purchase_technology("pipe") and run.purchase_technology("combo_unlock"),
		"speed two permits combo unlock"
	)
	_check(
		run.purchase_technology("combo_interval") and run.combo_level == 1,
		"interval upgrades do not increase rewards"
	)
	_check(
		run.purchase_technology("combo_reward") and run.combo_interval_level == 1,
		"reward upgrades do not increase interval level"
	)
	run.get_nest(2).alive_slimes = 20
	before = run.candy
	for _index: int in range(6):
		run.collect_slime(2)
	_check(
		run.candy == before + 6 * run.settings.slime_reward + 2,
		"reward upgrade affects real captures"
	)
	_check(
		is_equal_approx(run.combo_remaining, 4.0),
		"interval upgrade renews real captures to four seconds"
	)
	run.advance(3.5)
	_check(run.combo_count == 6, "upgraded combo survives past the old three-second deadline")
	run.advance(0.6)
	_check(run.combo_count == 0, "upgraded combo expires at its new deadline")
	run.candy = 10000
	for id: String in ["pipe", "net_unlock", "net_capacity", "combo_reward", "combo_interval"]:
		while run.purchase_technology(id):
			pass
		before = run.candy
		_check(
			not run.purchase_technology(id) and run.candy == before,
			"maxed technology cannot charge: " + id
		)
	preview.page.refresh(run)
	_check(preview.page._nodes["pipe"].level_label.text == "7", "max speed stays on the same icon")
	preview.set_preview(0)
	_check(
		run.combo_interval_level == 0 and is_equal_approx(run.get_combo_window_seconds(), 3.0),
		"restart resets interval research"
	)


func _check_layout(preview: PreviewScript) -> void:
	var canvas_rect: Rect2 = preview.page._canvas.get_global_rect()
	var detail: Control = preview.page.get_node("Margin/Content/Body/Detail") as Control
	for id: String in ["pipe", "cultivation", "automation"]:
		var center: Vector2 = (
			preview.page._nodes[id].get_global_transform() * NodeScript.ICON_CENTER
		)
		_check(
			absf(center.x - root.get_visible_rect().size.x * 0.5) < 1.0,
			"governance path is centered on screen"
		)
	for node: NodeScript in preview.page._nodes.values():
		_check(
			not node.get_global_rect().intersects(detail.get_global_rect()),
			"detail panel does not cover an upgrade"
		)
	for node: NodeScript in preview.page._nodes.values():
		_check(canvas_rect.encloses(node.get_global_rect()), "node fits the graph: " + node.name)
	var screen: Rect2 = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	_check(
		screen.encloses(preview.page.purchase.get_global_rect()), "purchase button stays on screen"
	)
	for node: NodeScript in preview.page._nodes.values():
		for other: NodeScript in preview.page._nodes.values():
			if node != other:
				_check(
					not node.get_global_rect().intersects(other.get_global_rect()),
					"technology hit areas do not overlap"
				)


func _settle() -> void:
	for _frame: int in range(5):
		await process_frame


func _click(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = down
		root.push_input(click, true)
		await process_frame


func _save(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check(
		root.get_texture().get_image().save_png("res://artifacts/" + filename) == OK,
		"screenshot saved"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
