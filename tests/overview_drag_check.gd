extends Node

const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const OUTPUT: String = "res://artifacts/overview_drag_20261013"

var _game: Play
var _failures: int = 0


func _ready() -> void:
	get_tree().root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		_game = PLAY.instantiate() as Play
		add_child(_game)
		await _settle()
		_game.set_process(false)
		_game._view.set_process(false)
		_game._window_has_focus = true
		_game._view.zoom_steps(-1.0, false)
		await _settle()
		var center: Vector2 = _game._world.get_global_transform_with_canvas().origin
		var radius: float = get_viewport().get_visible_rect().size.y * 0.54
		var step: float = 0.18
		for angle: float in [-PI * 0.75, -PI * 0.25, PI * 0.25, PI * 0.75]:
			var start: Vector2 = center + Vector2.from_angle(angle) * radius
			var before: float = _game._world.rotation
			_check(not _game._view.contains_planet_body(start), "drag starts in blank space")
			_button(start, true)
			_check(_game._view.is_dragging(), "each quadrant accepts a background drag")
			for frame: int in range(1, 13):
				_motion(center + Vector2.from_angle(angle + step * frame / 12.0) * radius)
			_check_turn(before, step, "clockwise arc follows the pointer in each quadrant")
			_motion(start)
			_check_turn(before, 0.0, "reversing the path returns to the same heading")
			_button(start, false)
			_check(not _game._view.is_dragging(), "release ends the drag")
		for side: float in [-1.0, 1.0]:
			var start: Vector2 = center + Vector2(side * radius, 0.0)
			var before: float = _game._world.rotation
			_button(start, true)
			_motion(start + Vector2(0.0, 60.0))
			_check_turn(
				before, atan2(60.0, radius) * side, "vertical side drag rotates with the pointer"
			)
			_button(start, false)
		var start: Vector2 = center + Vector2(-radius, 0.0)
		var before: float = _game._world.rotation
		_button(start, true)
		_motion(center + Vector2(-radius * 0.8, 0.0))
		_check_turn(before, 0.0, "radial movement does not rotate")
		_motion(center)
		_motion(center + Vector2(radius, 0.0))
		_check_turn(before, 0.0, "crossing the center does not flip the planet")
		_motion(center + Vector2(radius, 60.0))
		_check_turn(before, atan2(60.0, radius), "drag resumes smoothly beyond the center")
		_button(start, false)
		before = _game._world.rotation
		_button(start, true)
		_motion(center + Vector2(radius, 0.0))
		_check_turn(before, 0.0, "a single event across the center cannot flip the planet")
		_button(start, false)
		# Crossing the angle wrap must remain a small continuous turn.
		start = center + Vector2.from_angle(PI - 0.04) * radius
		before = _game._world.rotation
		_button(start, true)
		_motion(center + Vector2.from_angle(-PI + 0.04) * radius)
		_check_turn(before, 0.08, "angle wrap stays continuous")
		_button(start, false)
		await _capture("overview", resolution)
		_game._view.zoom_steps(1.0, false)
		before = _game._world.rotation
		_game._view.begin_drag(Vector2(600.0, 600.0))
		_game._view.drag_to(Vector2(600.0, 700.0))
		_check_turn(before, 0.0, "near view still ignores vertical motion")
		_game._view.drag_to(Vector2(680.0, 700.0))
		var near_radius: float = _game._planet.radius * _game._world.scale.x
		_check_turn(before, 80.0 / near_radius, "near view keeps its horizontal sensitivity")
		_game._view.end_drag()
		await _capture("near", resolution)
		_game.queue_free()
		await get_tree().process_frame
	print("Overview drag: %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_turn(before: float, expected: float, description: String) -> void:
	_check(absf(angle_difference(before, _game._world.rotation) - expected) < 0.0001, description)


func _button(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	get_tree().root.push_input(event, true)


func _motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT
	get_tree().root.push_input(event, true)


func _settle() -> void:
	for frame: int in range(6):
		await get_tree().process_frame


func _capture(label: String, resolution: Vector2i) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	await _settle()
	await RenderingServer.frame_post_draw
	var path: String = "%s/%s_%dx%d.png" % [OUTPUT, label, resolution.x, resolution.y]
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "current scene capture")


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)
