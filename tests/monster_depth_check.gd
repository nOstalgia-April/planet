extends Node

const PlayScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const Drill = preload("res://scripts/drill_monster.gd")

var _failures: Array[String] = []
var _game: Play


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_tree().root.size = resolution
		_game = PlayScene.instantiate() as Play
		add_child(_game)
		_game.set_process(false)
		_game._view.set_process(false)
		_game._layout.close_panels()
		_game._slime_root.set_process(false)
		await get_tree().process_frame
		_game._apply_layout()
		_game.run.advance(20.0)
		for actor: PrototypeSlime in _game._slimes:
			actor.hide()
			actor.set_process(false)
		var back: PrototypeSlime = _spawn(Vector2(940, 815), 0)
		var front: PrototypeSlime = _spawn(Vector2(958, 848), 1)
		var isolated: PrototypeSlime = _spawn(Vector2(1370, 835), 0)
		var mole: Drill = _game.DRILL_SCENE.instantiate() as Drill
		_game._slime_root.add_child(mole)
		mole.setup(1, Vector2.UP * 220.0, _game._planet)
		mole.presentation_scale = _game._view.near_slime_scale
		_place(mole, Vector2(930, 825))
		_game._slimes.append(mole)
		var stages: Array[StringName] = [&"跳出", &"钻地", &"鼓包", &"鼓包", &"跳出", &"夹夹"]
		for phase: int in range(stages.size()):
			mole._enter_phase(phase as Drill.Phase, 5.0, stages[phase])
			mole.art.animation_player.pause()
			mole.art.animation_player.seek(0.5, true)
			mole.refresh_presentation()
			_game._slime_root._process(1.0)
			_check(back.get_index() < mole.get_index(), "mole stays ahead of rear ground contact")
			_check(
				mole.get_index() < front.get_index(),
				"mole animation never jumps above front contact"
			)
			await _capture("mole_%d" % phase, resolution)
		_check(back.modulate.r < front.modulate.r, "overlapped rear body is subdued")
		_check(is_equal_approx(isolated.modulate.r, 1.0), "isolated body retains source color")
		var original: Vector2 = mole.position
		_game._capture_at(0.03, mole.get_capture_point(), true)
		_game._slime_root._process(1.0)
		_check(_game._capture_targets == [mole], "real pipe selects the exposed mole")
		_check(mole.get_index() > front.get_index(), "active mole renders above crowd")
		_check(is_equal_approx(mole.modulate.r, 1.0), "active mole retains full color")
		await _capture("mole_capture", resolution)
		_game._capture_at(0.0, mole.get_capture_point(), false)
		mole.position = original
		mole.refresh_presentation()
		_game._slime_root._process(1.0)
		_check(mole.get_index() < front.get_index(), "release restores ground order")
		_game._world.rotation += 0.35
		for actor: PrototypeSlime in [back, front, mole, isolated]:
			actor._update_surface_rotation()
			actor.refresh_presentation()
		_game._slime_root._process(1.0)
		var first: float = back.get_global_transform_with_canvas().origin.y
		var second: float = front.get_global_transform_with_canvas().origin.y
		_check(
			(back.get_index() < front.get_index()) == (first < second), "rotation uses screen depth"
		)
		_game._world.rotation -= 0.35
		for actor: PrototypeSlime in [back, front, mole, isolated]:
			actor._update_surface_rotation()
			actor.refresh_presentation()
		mole._enter_phase(Drill.Phase.TRAVEL, 5.0, &"鼓包")
		mole.art.animation_player.pause()
		var offsets: Array[Vector2] = [
			Vector2(-12, -33),
			Vector2(25, -17),
			Vector2(-30, 4),
			Vector2(6, 14),
			Vector2(39, 29),
			Vector2(-10, 47),
			Vector2(-67, 69)
		]
		for cluster: int in range(7):
			var center: Vector2 = Vector2(
				240.0 + cluster * 220.0, 915.0 - sin(cluster * 0.55) * 200.0
			)
			for index: int in range(4 + cluster % 4):
				_spawn(center + offsets[index], cluster % 2)
		_game._advance_ground_mucus(0.0)
		_game._slime_root._process(1.0)
		await _capture("crowd", resolution)
		_game.restart_run()
		_game._slime_root._process(1.0)
		_check(_game._slime_root.get_child_count() == 0, "restart clears ordering and focus")
		_game.queue_free()
		await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	print(
		(
			"PASS: crowd depth, all six mole phases, suction/release, rotation and restart at two sizes."
			if _failures.is_empty()
			else "FAIL: monster depth"
		)
	)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _spawn(point: Vector2, species: int) -> PrototypeSlime:
	var actor: PrototypeSlime = _game.slime_scene.instantiate() as PrototypeSlime
	_game._slime_root.add_child(actor)
	actor.setup(1, Vector2.UP * 220.0, _game._planet)
	actor.configure_species(species as PrototypeSlime.Species, false, 1)
	actor.presentation_scale = _game._view.near_slime_scale
	_place(actor, point)
	actor.slime_art._active.animation_player.pause()
	_game._slimes.append(actor)
	return actor


func _place(actor: PrototypeSlime, point: Vector2) -> void:
	var size: Vector2 = _game.get_viewport_rect().size
	var screen: Vector2 = point * size / Vector2(1920, 1080)
	actor.position = _game._world.get_global_transform_with_canvas().affine_inverse() * screen
	actor.set_process(false)
	actor._update_surface_rotation()
	actor.refresh_presentation()


func _capture(label: String, resolution: Vector2i) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/monster_depth")
	var path: String = (
		"res://artifacts/monster_depth/%s_%dx%d.png" % [label, resolution.x, resolution.y]
	)
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture saved")


func _check(condition: bool, description: String) -> void:
	if not condition and not _failures.has(description):
		_failures.append(description)
