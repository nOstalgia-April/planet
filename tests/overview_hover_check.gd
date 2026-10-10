extends SceneTree

const PlayScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const Bubble = preload("res://scripts/overview_monster_bubble.gd")

var _failures: Array[String] = []
var _capture_frame: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		var game: Play = PlayScene.instantiate() as Play
		root.add_child(game)
		current_scene = game
		game.set_process(false)
		game._layout.set_process(false)
		game._view.set_process(false)
		game._window_has_focus = true
		await process_frame
		await process_frame
		game._apply_layout()
		game._view.zoom_steps(-1.0, false)
		game._world.rotation = -0.4
		game._apply_layout()
		var overview: OverviewEcology = game._overview
		_present(overview)
		for frame: int in range(180):
			overview._process(1.0 / 120.0)
		_check(overview.bubbles.size() == 3, "fixture has three distinct neighboring groups")
		var selected: Bubble = overview.bubbles[0]
		var neighbor: Bubble = overview.bubbles[1]
		for candidate: Bubble in overview.bubbles:
			if (
				candidate != selected
				and (
					candidate.position.distance_to(selected.position)
					< neighbor.position.distance_to(selected.position)
				)
			):
				neighbor = candidate
		var population: Vector2i = overview.population_counts
		var direction: float = selected.cluster.angle
		var pointer: Vector2 = selected.position
		var idle_position: Vector2 = neighbor.position
		var idle_radius: float = selected.radius
		await _capture(resolution, "idle")
		_move_pointer(pointer)
		game._update_overview_hover(pointer)
		_check(
			overview._hovered_bubble == selected, "game input enables hover on the visible bubble"
		)
		overview._process(0.0)
		_check(
			selected.hover_scale == 1.0 and neighbor.position == idle_position,
			"hover changes targets without snapping geometry"
		)
		for frame: int in range(12):
			overview.update_hover(pointer, true)
			overview._process(1.0 / 60.0)
			if frame % 6 == 5:
				await _capture(resolution, "enter")
		_check(
			selected.hover_scale > 1.08 and selected.hover_scale < 1.3,
			"hover visibly grows over time"
		)
		_check(neighbor.motion_velocity.length() > 0.02, "neighbor displacement carries velocity")
		var release_position: Vector2 = neighbor.position
		var release_velocity: Vector2 = neighbor.motion_velocity
		overview.update_hover(Vector2.ZERO, false)
		_check(
			neighbor.motion_velocity == release_velocity and neighbor.position == release_position,
			"leaving preserves displacement and inertia"
		)
		overview._process(1.0 / 60.0)
		_check(
			neighbor.position.distance_to(release_position) > 0.01,
			"neighbor keeps moving after release"
		)
		for frame: int in range(60):
			overview.update_hover(pointer, true)
			overview._process(1.0 / 60.0)
			_check(
				overview._hovered_bubble == selected,
				"a stationary pointer does not flicker between neighbors"
			)
			if frame % 6 == 0:
				await _capture(resolution, "hold")
		_check(
			absf(selected.hover_scale - selected.hover_magnification) < 0.01,
			"hover settles at the configured magnification"
		)
		_check(
			neighbor.position.distance_to(idle_position) > idle_radius * 0.04,
			"enlargement pushes a nearby bubble away"
		)
		_check(
			(
				selected.radius == idle_radius
				and selected.cluster.angle == direction
				and overview.population_counts == population
			),
			"presentation never changes density or geographical identity"
		)
		var enlarged_edge: Vector2 = selected.position + Vector2.UP * selected.radius * 1.15
		_check(
			overview.get_bubble_at(enlarged_edge) == selected,
			"expanded edge participates in click hit testing"
		)
		_check(selected.z_index > neighbor.z_index, "hovered artwork draws above its neighbors")
		await _capture(resolution, "hover_final")
		print(
			"HOVER ",
			resolution,
			" scale=",
			selected.hover_scale,
			" neighbor_shift=",
			neighbor.position.distance_to(idle_position)
		)
		overview.update_hover(Vector2.ZERO, false)
		for frame: int in range(120):
			overview._process(1.0 / 60.0)
			if frame % 6 == 0:
				await _capture(resolution, "release")
		_check(
			absf(selected.hover_scale - 1.0) < 0.005,
			"leaving returns the bubble to its density size"
		)
		_check(
			neighbor.position.distance_to(idle_position) < idle_radius * 0.2,
			"neighbors settle back near their original arrangement"
		)
		for frame: int in range(180):
			overview._process(1.0 / 60.0)
		var settled: Vector2 = selected.position
		for frame: int in range(120):
			overview._process(1.0 / 60.0)
		_check(
			selected.position == settled and selected.motion_velocity == Vector2.ZERO,
			"idle bubbles stop moving completely after release"
		)
		_check(
			selected.motion_offset == selected.offset and selected.hover_scale == 1.0,
			"resting presentation matches the original density layout exactly"
		)
		_check_gates(game, selected.position)
		# Repeated pointer sweeps and a delayed frame must not destabilize the springs.
		for frame: int in range(90):
			var target: Bubble = overview.bubbles[(frame / 6) % 3]
			overview.update_hover(target.position, true)
			overview._process(1.0 / 30.0)
		overview._process(3.0)
		for bubble: Bubble in overview.bubbles:
			_check(
				bubble.position.is_finite() and bubble.motion_velocity.is_finite(),
				"rapid sweeps and a long frame remain finite"
			)
			_check(
				bubble.motion_offset.length() < 2.0,
				"motion stays local to the original surface anchor"
			)
			_check(
				bubble.hover_scale > 0.94 and bubble.hover_scale < 1.35,
				"spring overshoot stays restrained"
			)
		# The top edge is a real layout boundary, including during growth.
		game._world.rotation = -PI * 0.5
		overview.update_hover(selected.position, true)
		for frame: int in range(90):
			overview._process(1.0 / 60.0)
		for bubble: Bubble in overview.bubbles:
			_check(
				root.get_visible_rect().encloses(
					overview._bubble_rect(bubble.position, bubble.display_radius)
				),
				"enlarged bubbles remain within the viewport"
			)
		# Click a moving enlarged bubble through the game's actual input route.
		overview.update_hover(neighbor.position, true)
		for frame: int in range(45):
			overview._process(1.0 / 60.0)
		var focus_angle: float = neighbor.cluster.angle
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = neighbor.position
		click.global_position = click.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		root.push_input(click, true)
		_check(
			game._view.is_transitioning() and not game._view.is_overview(),
			"hovered bubble still opens near gameplay"
		)
		game._view._process(game._view.transition_seconds)
		_check(
			absf(angle_difference(game._world.rotation + focus_angle, -PI * 0.5)) < 0.001,
			"navigation targets the group instead of its displaced artwork"
		)
		_check(
			overview._hovered_bubble == null and overview.bubbles.is_empty(),
			"near view clears hover state and cursor ownership"
		)
		current_scene = null
		game.queue_free()
		await process_frame
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print(
			"PASS: spring hover, neighbor inertia, static idle layout, release, UI gates, boundaries and displaced-bubble navigation at both resolutions"
		)
	quit(0 if _failures.is_empty() else 1)


func _present(overview: OverviewEcology) -> void:
	var positions: PackedVector2Array = PackedVector2Array()
	var kinds: PackedInt32Array = PackedInt32Array()
	for group: int in range(3):
		var angle: float = [0.0, 0.24, 0.58][group]
		for index: int in range(48 if group != 1 else 28):
			positions.append(Vector2.from_angle(angle) * 250.0)
			kinds.append(group % 2)
	overview.update_ecology(positions, kinds, true, root.get_visible_rect().size)
	overview.set_process(false)


func _check_gates(game: Play, pointer: Vector2) -> void:
	game._layout._show_technology()
	game._update_overview_hover(pointer)
	_check(game._overview._hovered_bubble == null, "technology modal blocks hover")
	game._layout.close_panels()
	game._on_window_focus_exited()
	game._update_overview_hover(pointer)
	_check(game._overview._hovered_bubble == null, "unfocused window blocks hover")
	game._on_window_focus_entered()
	game._view.begin_drag(Vector2.ZERO)
	game._update_overview_hover(pointer)
	_check(game._overview._hovered_bubble == null, "camera drag blocks hover")
	game._view.end_drag()
	var menu: Button = game.get_node("预览导航/返回主菜单") as Button
	_move_pointer(menu.get_global_rect().get_center())
	game._update_overview_hover(menu.get_global_rect().get_center())
	_check(game._overview._hovered_bubble == null, "preview buttons block hover")
	_move_pointer(Vector2.ZERO)


func _move_pointer(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)


func _capture(resolution: Vector2i, phase: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	if resolution.x == 1920 and not phase in ["idle", "hover_final"]:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = (
		"res://artifacts/hover_%dx%d_%03d_%s.png"
		% [resolution.x, resolution.y, _capture_frame, phase]
	)
	_check(root.get_texture().get_image().save_png(path) == OK, "hover frame saved")
	_capture_frame += 1


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
