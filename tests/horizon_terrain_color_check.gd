extends Node

const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const Restoration = preload("res://scripts/planet_restoration.gd")
const OUTPUT: String = "res://artifacts/terrain_color_20261014"

var _game: Play
var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_tree().root.size = resolution
		_game = PLAY.instantiate() as Play
		add_child(_game)
		_game.set_process(false)
		_game._view.set_process(false)
		_game._view.overview_rotation_speed = 0.0
		_game._restoration.set_process(false)
		await get_tree().process_frame
		_game._apply_layout()
		await get_tree().create_timer(1.2).timeout
		_check(_game._horizon_terrain.has_visible_color(0), "opening shows pink terrain")
		_check(_game._horizon_terrain.has_visible_color(1), "opening shows blue terrain")
		_check(not _game._horizon_terrain.has_visible_color(2), "opposite peak is off screen")
		await _capture("gray", resolution)
		for species: int in [0, 1]:
			await _check_reveal(species, resolution)
			_game._view.zoom_steps(1.0, false)
			await get_tree().create_timer(1.2).timeout
		_check(_game._horizon_terrain.color_progress == Vector3(1, 1, 0), "colors survive reentry")
		await _capture("pink_blue_return", resolution)
		_game._view.zoom_steps(-1.0, false)
		_game._view.focus_surface(PI / 2.0, false)
		await get_tree().create_timer(1.2).timeout
		_check(_game._horizon_terrain.has_visible_color(2), "opposite peak can reveal green")
		await _capture("purple_foot_gray_peak", resolution)
		await _check_reveal(2, resolution)
		_game._view.focus_surface(PI / 2.0, false)
		await get_tree().create_timer(1.2).timeout
		await _capture("restored_peak", resolution)
		_game.restart_run()
		_check(_game._horizon_terrain.color_progress == Vector3.ZERO, "restart clears terrain colors")
		await get_tree().create_timer(1.2).timeout
		# Green is unlocked on the other hemisphere: no extra near-view delay.
		_game._restoration.reveal_flower(1, 2)
		_game._restoration._process(0.8)
		_check(_game._restoration.phase == Restoration.Phase.CAMERA, "offscreen reveal skips terrain phase")
		_check(_game._horizon_terrain.color_progress.z == 1.0, "offscreen color remains unlocked")
		_game.restart_run()
		await get_tree().create_timer(1.2).timeout
		_game._restoration.reveal_flower(1, 0)
		_game._restoration._process(0.8)
		_game._restoration._process(0.45)
		_game.restart_run()
		_game._restoration._process(10.0)
		_check(_game._horizon_terrain.color_progress == Vector3.ZERO, "restart cancels partial terrain reveal")
		_check(not _game._view.presentation_locked, "restart releases camera lock")
		_game._view.zoom_steps(-1.0, false)
		_game._restoration.reveal_flower(1, 1)
		_game._restoration._process(0.8)
		_check(_game._restoration.phase == Restoration.Phase.CAMERA, "overview reveal skips terrain phase")
		_check(_game._horizon_terrain.color_progress.y == 1.0, "overview unlock colors terrain")
		_game.queue_free()
		await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	print("TERRAIN COLOR: ", _failures.size(), " failures")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_reveal(species: int, resolution: Vector2i) -> void:
	var restore: Restoration = _game._restoration
	restore.reveal_flower(1, species)
	_check(restore.phase == Restoration.Phase.CONFIRM, "flower precedes terrain reveal")
	_check(_game._horizon_terrain.color_progress[species] == 0.0, "confirmation holds gray terrain")
	restore._process(restore.confirmation_seconds)
	_check(restore.phase == Restoration.Phase.TERRAIN, "visible terrain inserts near reveal")
	_check(not _game._view.is_overview(), "terrain reveal holds near camera")
	restore._process(restore.terrain_seconds * 0.5)
	_check(is_equal_approx(_game._horizon_terrain.color_progress[species], 0.5), "terrain fades halfway")
	_check(_game._planet_art.color_progress[species] == 0.0, "globe fill waits for terrain")
	_game._view.zoom_steps(-1.0)
	_check(not _game._view.is_overview(), "player cannot skip terrain reveal")
	restore.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.05, true).timeout
	_check(is_equal_approx(_game._horizon_terrain.color_progress[species], 0.5), "pause freezes terrain reveal")
	get_tree().paused = false
	restore.set_process(false)
	await _capture("color_%d_half" % species, resolution)
	restore._process(restore.terrain_seconds * 0.5)
	_check(_game._horizon_terrain.color_progress[species] == 1.0, "terrain completes before camera moves")
	_check(restore.phase == Restoration.Phase.CAMERA and _game._view.is_overview(), "terrain joins existing overview transition")
	await _capture("color_%d_full" % species, resolution)
	restore.reveal_flower(2, species)
	for step: int in range(20):
		_game._view._process(1.0)
		restore._process(1.0)
		if restore.phase == Restoration.Phase.IDLE:
			break
	_check(restore.phase == Restoration.Phase.IDLE, "queued presentation finishes")
	_check(restore.completed_species.count(species) == 1, "same species never replays")
	_check(_game._planet_art.color_progress[species] == 1.0, "existing globe fill completes")


func _capture(label: String, resolution: Vector2i) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var path: String = OUTPUT + "/%s_%dx%d.png" % [label, resolution.x, resolution.y]
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture saved")
	print("CAPTURE ", path, " ", Time.get_datetime_string_from_system())


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)
