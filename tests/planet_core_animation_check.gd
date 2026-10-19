extends Node

const Core = preload("res://scripts/planet_core_animation.gd")
const Game = preload("res://features/场景预览/游玩预览.gd")
const CoreScene: PackedScene = preload("res://scenes/场景动画/星球核心.tscn")
const GameScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const TutorialGame = preload("res://features/tutorial_intro/tutorial_game.gd")
const Tutorial = preload("res://features/tutorial_intro/tutorial_intro.gd")
const TutorialScene: PackedScene = preload("res://features/tutorial_intro/tutorial_game.tscn")
const StoryGame = preload("res://features/tutorial_intro/story_game.gd")
const StoryFlow = preload("res://features/tutorial_intro/story_flow.gd")
const StoryScene: PackedScene = preload("res://scenes/game.tscn")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(120.0, true, false, true).timeout.connect(
		func() -> void: get_tree().quit(1)
	)
	if "--opening-only" in OS.get_cmdline_user_args():
		await _check_opening_core()
		await _check_story_opening_core()
		get_tree().quit()
		return
	var static_core: Core = CoreScene.instantiate() as Core
	static_core.autoplay = false
	add_child(static_core)
	await get_tree().create_timer(0.15).timeout
	assert(not static_core.is_processing() and static_core.current_frame == 0)
	var static_material: ShaderMaterial = static_core.sprite.material as ShaderMaterial
	assert(is_zero_approx(static_material.get_shader_parameter("outer_deformation")))
	static_core.queue_free()
	await get_tree().process_frame
	var core: Core = CoreScene.instantiate() as Core
	core.synchronize_music = false
	add_child(core)
	core.set_process(false)
	assert(core.clip.frame_tiles.size() == 3600)
	assert(core.clip.page_paths.size() == 46)
	assert(core.clip.frame_tiles[2926] == 2926)
	assert(core.clip.frame_tiles[2927] == 2927)
	assert(core.clip.frame_tiles[3599] == 2927, "Deduplication must retain the full final hold.")
	# Traverse every page, then seek backward across arbitrary pages and the loop.
	for page: int in range(46):
		await _seek(core, mini(page * 64 + 1, 2927))
	for frame: int in [3599, 0, 2400, 63, 64, 2927, 3599, 0]:
		await _seek(core, frame)
	core.seek_seconds(-1.0)
	assert(core.current_frame == 0)
	_check_motion_clock(core)
	await _seek(core, 3599)
	core.seek_seconds(180.0)
	assert(core.current_frame == 3599, "The music, not the image clock, owns loop restart.")
	_check_motion_clock(core)
	core.queue_free()
	await get_tree().process_frame
	var game: Game = GameScene.instantiate() as Game
	game.start_in_overview = true
	var live_core: Core = game.get_node("World/PlanetSurface/星球画面/星球核心") as Core
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game._window_has_focus = true
	assert(GameAudio._music_path == "event:/Mx/Mx_GamePlay")
	assert(GameAudio.get_music_position_seconds("event:/Mx/Mx_MainMenu") == -1.0)
	await get_tree().create_timer(0.3).timeout
	var music: FmodEvent = GameAudio._music
	assert(music != null and music.is_valid())
	music.set_paused(true)
	for seconds: float in [0.0, 3.21, 30.0, 70.0, 0.0]:
		music.set_timeline_position(int(seconds * 1000.0))
		FmodServer.update()
		await get_tree().create_timer(0.08).timeout
		var position: float = GameAudio.get_music_position_seconds("event:/Mx/Mx_GamePlay")
		assert(absf(position - seconds) < 0.1, "FMOD exposes the requested timeline position.")
		await _wait_music_frame(live_core, int(floor(position * live_core.frames_per_second)))
	var held_frame: int = live_core.current_frame
	await get_tree().create_timer(0.15).timeout
	assert(live_core.current_frame == held_frame, "Paused music freezes the effect.")
	_check_motion_clock(live_core)
	get_tree().paused = true
	music.set_paused(false)
	await get_tree().create_timer(0.08, true).timeout
	FmodServer.update()
	var paused_position: float = GameAudio.get_music_position_seconds("event:/Mx/Mx_GamePlay")
	await _wait_music_frame(live_core, int(floor(paused_position * live_core.frames_per_second)))
	var tree_held_frame: int = live_core.current_frame
	# FMOD applies resume asynchronously; allow its audio buffer to advance.
	await get_tree().create_timer(0.5, true).timeout
	assert(
		live_core.current_frame > tree_held_frame,
		"Tree pause keeps the music-driven effect following the BGM clock."
	)
	_check_motion_clock(live_core)
	get_tree().paused = false
	await get_tree().create_timer(0.25).timeout
	assert(live_core.current_frame > tree_held_frame, "The BGM clock keeps advancing after resume.")
	_check_motion_clock(live_core)
	music.set_paused(true)
	# Let the real FMOD loop cross its end, rather than simulating only a seek.
	music.set_timeline_position(97200)
	music.set_paused(false)
	FmodServer.update()
	await get_tree().create_timer(0.8).timeout
	music.set_paused(true)
	FmodServer.update()
	await get_tree().create_timer(0.08).timeout
	var loop_position: float = GameAudio.get_music_position_seconds("event:/Mx/Mx_GamePlay")
	assert(loop_position >= 0.0 and loop_position < 1.0, "The actual BGM must loop back.")
	await _wait_music_frame(live_core, int(floor(loop_position * live_core.frames_per_second)))
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_game(game, live_core)
	get_tree().current_scene = null
	game.queue_free()
	await get_tree().process_frame
	await _check_opening_core()
	await _check_story_opening_core()
	GameAudio.play_music("event:/Mx/Mx_MainMenu")
	assert(GameAudio.get_music_position_seconds("event:/Mx/Mx_GamePlay") == -1.0)
	print(
		"PASS: all 46 pages, bounded cache, frame boundaries, final hold, backward/loop seek, FMOD pause, displayed-frame brush clock and scene exit."
	)
	get_tree().quit()


func _check_opening_core() -> void:
	# The preceding clock checks deliberately leave their music instance paused.
	GameAudio.stop_music()
	var game: TutorialGame = TutorialScene.instantiate() as TutorialGame
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game._window_has_focus = true
	var core: Core = game._core
	var material: ShaderMaterial = core.sprite.material as ShaderMaterial
	await get_tree().create_timer(0.15).timeout
	assert(game.tutorial.phase == Tutorial.Phase.OVERVIEW)
	assert(not core.is_processing() and core.current_frame == 0)
	assert(is_zero_approx(material.get_shader_parameter("outer_deformation")))
	var deadline: int = Time.get_ticks_msec() + 5000
	while game.tutorial.phase in [Tutorial.Phase.OVERVIEW, Tutorial.Phase.ZOOMING]:
		assert(not core.is_processing() and core.current_frame == 0)
		assert(Time.get_ticks_msec() < deadline, "Opening camera must finish.")
		await get_tree().process_frame
	assert(not core.is_processing(), "Reaching near view must not start the core.")
	assert(is_zero_approx(material.get_shader_parameter("outer_deformation")))
	game.tutorial.cancel()
	for zoom: float in [-1.0, 1.0, -1.0]:
		game._view.zoom_steps(zoom, false)
		var previous_frame: int = core.current_frame
		await get_tree().create_timer(0.2).timeout
		assert(
			core.current_frame > previous_frame, "Later view switches must keep the core moving."
		)
	# Evict the first atlas to exercise the static reset after a long play session.
	core.set_process(false)
	await _seek(core, 2400)
	game.restart_run()
	assert(game.tutorial.phase == Tutorial.Phase.OVERVIEW)
	assert(not core.is_processing() and core.current_frame == 0)
	assert(is_zero_approx(material.get_shader_parameter("outer_deformation")))
	game.tutorial.cancel()
	assert(not core.is_processing(), "Cancelling alone must not release the static hold.")
	game._view.zoom_steps(1.0, false)
	assert(not core.is_processing())
	game._view.zoom_steps(-1.0, false)
	assert(core.is_processing())
	deadline = Time.get_ticks_msec() + 5000
	while core.current_frame == 0:
		assert(Time.get_ticks_msec() < deadline, "Returning to overview must resume animation.")
		await get_tree().process_frame
	get_tree().current_scene = null
	game.queue_free()
	await get_tree().process_frame
	print("PASS: static opening camera, animated later views, restart and cancellation.")


func _check_story_opening_core() -> void:
	GameAudio.stop_music()
	var game: StoryGame = StoryScene.instantiate() as StoryGame
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game._window_has_focus = true
	var core: Core = game._restoration.core
	_assert_static(core)
	game.story.briefing.reveal_all()
	game.story.briefing.close()
	await game.story.briefing.finished
	await _capture_opening("opening_overview")
	var deadline: int = Time.get_ticks_msec() + 20000
	while game.story.phase != StoryFlow.Phase.WAIT_VIEW:
		_assert_static(core)
		assert(game._view.is_overview(), "Opening dialogue stays in overview.")
		assert(Time.get_ticks_msec() < deadline, "Opening dialogue must finish.")
		if game.story.phase == StoryFlow.Phase.TALKING:
			game.story.active_dialogue.advance()
		await get_tree().process_frame
	assert(core.is_processing(), "Finishing the NPC dialogue starts the core.")
	await _capture_opening("view_hint")
	game.story.restore_save(game.story.capture_save())
	assert(core.is_processing(), "Loading the pending view hint keeps the core moving.")
	assert(game.story.phase == StoryFlow.Phase.WAIT_VIEW)
	game._window_has_focus = true
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame
	assert(game.story.phase == StoryFlow.Phase.ZOOMING)
	deadline = Time.get_ticks_msec() + 10000
	while game.story.phase != StoryFlow.Phase.IDLE:
		assert(core.is_processing(), "Core keeps playing throughout the entrance.")
		assert(Time.get_ticks_msec() < deadline, "Opening entrance must finish.")
		await get_tree().process_frame
	game.story.restore_save(game.story.capture_save())
	assert(core.is_processing(), "Loading an unlocked run keeps animation enabled.")
	for zoom: float in [-1.0, 1.0]:
		game._view.zoom_steps(zoom, false)
		assert(core.is_processing(), "Later view changes must not reset the unlock.")
	game.restart_run()
	_assert_static(core)
	assert(not game.story.view_hint.visible)
	assert(game.story.phase == StoryFlow.Phase.NOTE)
	game.story.cancel()
	get_tree().current_scene = null
	game.queue_free()
	await get_tree().process_frame
	print(
		"PASS: formal overview dialogue, core release before view input, entrance, save/load and restart."
	)


func _assert_static(core: Core) -> void:
	assert(not core.is_processing() and core.current_frame == 0)
	var material: ShaderMaterial = core.sprite.material as ShaderMaterial
	assert(is_zero_approx(material.get_shader_parameter("outer_deformation")))
	assert(is_zero_approx(material.get_shader_parameter("motion_seconds")))


func _capture_opening(label: String) -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find("--opening-capture")
	if index < 0:
		return
	await RenderingServer.frame_post_draw
	var path: String = args[index + 1].path_join(label + ".png")
	assert(get_viewport().get_texture().get_image().save_png(path) == OK)
	print("CAPTURE ", Time.get_datetime_string_from_system(), " ", path)


func _seek(core: Core, frame: int) -> void:
	var start: int = Time.get_ticks_msec()
	while true:
		core._poll_pages()
		core.seek_seconds((float(frame) + 0.01) / core.frames_per_second)
		if core.current_frame == frame:
			break
		assert(Time.get_ticks_msec() - start < 5000, "Atlas streaming timed out.")
		await get_tree().process_frame
	assert(core._pages.size() <= 2 and core._pending.size() <= 2)
	var tile: int = core.clip.frame_tiles[frame]
	assert(core.sprite.texture.resource_path == core.clip.page_paths[tile / 64])
	assert(
		(
			core.sprite.region_rect.position
			== Vector2(tile % 8, (tile % 64) / 8) * Vector2(core.clip.tile_size)
		)
	)
	assert(core.sprite.position == -core.clip.pivot)
	_check_motion_clock(core)


func _wait_music_frame(core: Core, frame: int) -> void:
	var start: int = Time.get_ticks_msec()
	while core.current_frame != frame:
		assert(Time.get_ticks_msec() - start < 5000, "Music-driven atlas streaming timed out.")
		await get_tree().process_frame
	_check_motion_clock(core)


func _check_motion_clock(core: Core) -> void:
	var material: ShaderMaterial = core.sprite.material as ShaderMaterial
	var motion_seconds: float = material.get_shader_parameter("motion_seconds")
	var expected: float = float(core.current_frame) / core.frames_per_second
	assert(
		is_equal_approx(motion_seconds, expected),
		(
			"Brush time must follow displayed frame: frame=%d expected=%.6f actual=%.6f"
			% [core.current_frame, expected, motion_seconds]
		)
	)


func _capture_game(game: Game, core: Core) -> void:
	get_tree().root.mode = Window.MODE_WINDOWED
	game._view.set_process(false)
	game.set_process(false)
	game._layout.set_process(false)
	core.set_process(false)
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_tree().root.size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		game._apply_layout()
		game._view.zoom_steps(-1.0, false)
		for frame: int in [0, 2400]:
			await _seek(core, frame)
			var screen_center: Vector2 = game._world.get_global_transform_with_canvas().origin
			assert(core.get_global_transform_with_canvas().origin.distance_to(screen_center) < 0.01)
			await _capture("overview_%dx%d_%04d" % [resolution.x, resolution.y, frame])
		game._world.rotation = 0.8
		await _capture("rotated_%dx%d" % [resolution.x, resolution.y])
		game._view.zoom_steps(1.0, false)
		await _capture("near_%dx%d" % [resolution.x, resolution.y])
	# Capture actual imported atlas pixels to inspect the compression result.
	var tile: int = core.clip.frame_tiles[core.current_frame]
	var cropped: Image = core.sprite.texture.get_image().get_region(Rect2i(core.sprite.region_rect))
	assert(cropped.save_png("res://artifacts/planet_core_imported_frame_%04d.png" % tile) == OK)


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(
		(
			get_viewport().get_texture().get_image().save_png(
				"res://artifacts/planet_core_%s.png" % label
			)
			== OK
		)
	)
