extends Node

const SLIME_SCENE: PackedScene = preload("res://scenes/world/slime.tscn")
const PLAY_SCENE: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const OUTPUT: String = "res://artifacts/mucus_ground_shadow_20261016"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var actor: PrototypeSlime = SLIME_SCENE.instantiate() as PrototypeSlime
	add_child(actor)
	actor.configure_species(PrototypeSlime.Species.MUCUS, false, 2)
	var shadow: Node2D = actor.mucus_ground_shadow
	var sprite: Sprite2D = shadow.get_node("Ink") as Sprite2D
	var animation: AnimationPlayer = shadow.get_node("AnimationPlayer") as AnimationPlayer
	_check(shadow.visible and not actor.ground_shadow.visible, "mucus selects only blue ground art")
	_check(shadow.get_index() < actor.slime_art.get_index(), "ground art stays below the body")
	_check(
		animation.get_animation(&"流动").track_get_key_count(0) == 3, "all supplied frames are bound"
	)
	for frame: int in range(3):
		animation.seek(frame * 0.2, true)
		actor.slime_art._active.show_frame(&"待机", frame)
		var body: Rect2 = actor.slime_art.get_art_bounds()
		var ink: Rect2 = sprite.transform * Rect2(sprite.texture.get_image().get_used_rect())
		_check(
			absf(ink.get_center().x - body.get_center().x) < 1.0,
			"blue pool stays centered under every body frame"
		)
		_check(
			ink.size.x / body.size.x > 0.95 and ink.size.x / body.size.x < 1.02,
			"blue pool follows body width"
		)
		_check(
			(
				ink.position.y < body.end.y
				and ink.end.y - body.end.y > 4.5
				and ink.end.y - body.end.y < 7.5
			),
			"blue edge sits beneath the foot as supplied"
		)
	actor._launch_elapsed = actor.launch_seconds * 0.5
	actor.refresh_presentation()
	_check(shadow.position.y > actor.slime_art.position.y, "launch keeps the pool on the ground")
	actor._launch_elapsed = actor.launch_seconds
	actor.apply_capture(0.1, 1.0, actor.get_capture_point())
	actor.refresh_presentation()
	_check(not shadow.visible, "actual suction hides the ground pool")
	actor.release_capture(1.0)
	actor.refresh_presentation()
	_check(shadow.visible, "release restores the ground pool")
	actor._flying = true
	actor.refresh_presentation()
	_check(not shadow.visible, "falling bodies do not carry ground art")
	actor._flying = false
	actor.configure_species(PrototypeSlime.Species.SLIME, false, 1)
	_check(
		actor.ground_shadow.visible and not shadow.visible, "pink shadows remain species specific"
	)
	actor.queue_free()
	await get_tree().process_frame
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _capture_current_scene()
	for failure: String in _failures:
		push_error(failure)
	print(
		(
			"PASS: supplied mucus shadow alignment, three frames, launch, suction, release and fall"
			if _failures.is_empty()
			else "FAIL: mucus shadow"
		)
	)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _capture_current_scene() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	get_window().size = Vector2i(1920, 1080)
	var game: Play = PLAY_SCENE.instantiate() as Play
	add_child(game)
	game.set_process(false)
	game._view.set_process(false)
	game._layout.close_panels()
	await get_tree().process_frame
	game._apply_layout()
	game.run.advance(20.0)
	for existing: PrototypeSlime in game._slimes:
		existing.hide()
		existing.set_process(false)
	var actors: Array[PrototypeSlime] = []
	for index: int in range(3):
		var actor: PrototypeSlime = SLIME_SCENE.instantiate() as PrototypeSlime
		game._slime_root.add_child(actor)
		actor.setup(1, Vector2.UP * 220.0, game._planet)
		actor.configure_species(PrototypeSlime.Species.MUCUS, index == 2, 2)
		actor.presentation_scale = game._view.near_slime_scale
		var point: Vector2 = Vector2(790.0 + index * 210.0, 810.0)
		actor.position = game._world.get_global_transform_with_canvas().affine_inverse() * point
		actor.set_process(false)
		actor._update_surface_rotation()
		actor.refresh_presentation()
		actor.slime_art._active.show_frame(&"待机", index)
		var animation: AnimationPlayer = (
			actor.mucus_ground_shadow.get_node("AnimationPlayer") as AnimationPlayer
		)
		animation.seek(index * 0.2, true)
		animation.pause()
		game._slimes.append(actor)
		actors.append(actor)
	game._slime_root._process(0.0)
	game._pipe.hide()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(
		(
			get_viewport().get_texture().get_image().save_png(OUTPUT.path_join("formal_near.png"))
			== OK
		),
		"formal scene screenshot saved"
	)
	game.hide()
	var detail: Node2D = Node2D.new()
	add_child(detail)
	for index: int in range(3):
		var actor: PrototypeSlime = actors[index]
		actor.reparent(detail, false)
		actor.position = Vector2(430.0 + index * 530.0, 680.0)
		actor.rotation = 0.0
		actor.scale = Vector2.ONE * 10.0
		actor.presentation_scale = 1.0
		actor.refresh_presentation()
	await RenderingServer.frame_post_draw
	_check(
		(
			get_viewport().get_texture().get_image().save_png(
				OUTPUT.path_join("detail_three_frames.png")
			)
			== OK
		),
		"detail screenshot saved"
	)
	var manifest: Dictionary = {
		"captured_at_utc": Time.get_datetime_string_from_system(true),
		"game_scene": PLAY_SCENE.resource_path,
		"actor_scene": SLIME_SCENE.resource_path,
		"engine": Engine.get_version_info().string,
		"frames": [0, 1, 2],
		"detail_scale": 10.0
	}
	var file: FileAccess = FileAccess.open(OUTPUT.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	detail.queue_free()
	game.queue_free()
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
