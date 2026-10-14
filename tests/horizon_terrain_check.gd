extends Node

const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const OUTPUT: String = "res://artifacts/horizon_terrain_20261014"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_tree().root.size = resolution
		var game: Play = PLAY.instantiate() as Play
		game.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(game)
		game.set_process(false)
		game._view.set_process(false)
		game._view.overview_rotation_speed = 0.0
		await get_tree().process_frame
		game._apply_layout()
		var terrain: Node2D = game._horizon_terrain
		_check(terrain.visible, "direct near entry shows terrain")
		_check(terrain.z_index < game._planet.z_index, "terrain is behind the crust")
		_check(terrain.z_index < game._nests.z_index, "terrain is behind all actors")
		await get_tree().create_timer(1.1).timeout
		for piece: AnimatedSprite2D in game._horizon_terrain.pieces:
			_check(not piece.is_playing(), "appearance stops after one pass")
			_check(
				piece.frame == piece.sprite_frames.get_frame_count(&"appear") - 1,
				"appearance holds its last supplied frame"
			)
		await _capture("near", resolution)
		game._view.zoom_steps(-1.0)
		game._view._process(0.5)
		_check(terrain.visible and terrain.modulate.a < 1.0, "exit fades terrain")
		game._view._process(0.3)
		_check(not terrain.visible, "overview hides terrain")
		await _capture("overview", resolution)
		game._view.zoom_steps(1.0)
		game._view._process(0.4)
		_check(terrain.visible, "terrain enters during the near transition")
		_check(game._horizon_terrain.pieces[0].is_playing(), "entry replays appearance")
		await _capture("enter", resolution)
		await get_tree().create_timer(0.16).timeout
		var tree: AnimatedSprite2D = game._horizon_terrain.pieces[3]
		get_tree().paused = true
		var paused_frame: int = tree.frame
		var paused_progress: float = tree.frame_progress
		await get_tree().create_timer(0.2, true).timeout
		_check(
			tree.frame == paused_frame and is_equal_approx(tree.frame_progress, paused_progress),
			"pause freezes the appearance animation"
		)
		get_tree().paused = false
		game._view.zoom_steps(-1.0)
		game._view._process(0.05)
		var reversal_frame: int = tree.frame
		game._view.zoom_steps(1.0)
		_check(tree.frame == reversal_frame, "visible reversal does not restart terrain")
		game._view._process(1.0)
		await get_tree().create_timer(1.1).timeout
		await _capture("arrived", resolution)
		var local_transform: Transform2D = terrain.transform
		game._view.zoom_steps(-1.0, false)
		game._view.focus_surface(PI / 2.0, false)
		await get_tree().create_timer(1.1).timeout
		_check(terrain.transform == local_transform, "terrain remains attached when rotating")
		var peak: AnimatedSprite2D = game._horizon_terrain.pieces[2]
		var peak_top: Vector2 = peak.get_global_transform_with_canvas() * Vector2(210, 114)
		_check(
			peak_top.y < get_viewport().get_visible_rect().size.y * game._view.near_horizon_ratio,
			"opposite mountain reaches the horizon when its region is selected"
		)
		await _capture("opposite_peak", resolution)
		game.restart_run()
		_check(terrain.visible and tree.frame == 0, "restart resets near terrain animation")
		game.queue_free()
		await get_tree().process_frame
	var overview: Play = PLAY.instantiate() as Play
	overview.start_in_overview = true
	add_child(overview)
	_check(not overview._horizon_terrain.visible, "direct overview entry has no terrain")
	overview.queue_free()
	await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	print("HORIZON TERRAIN: ", _failures.size(), " failures")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _capture(label: String, resolution: Vector2i) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var path: String = OUTPUT + "/%s_%dx%d.png" % [label, resolution.x, resolution.y]
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture saved")


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
