extends Node

const Intro = preload("res://scenes/开头动画/开头动画.gd")
const Menu = preload("res://scenes/主菜单/主菜单.gd")
const Audio = preload("res://scripts/fmod_audio.gd")
const INTRO_PATH: String = "res://scenes/开头动画/开头动画.tscn"
const FRAME_COUNTS: Array[int] = [4, 6, 3, 3, 7, 13, 9, 14]
const FRAME_RATES: Array[float] = [4.0, 3.0, 3.0, 4.0, 5.0, 4.5, 5.0, 5.0]

var _tree: SceneTree


func _ready() -> void:
	_tree = get_tree()
	_tree.current_scene = null
	_run.call_deferred()


func _run() -> void:
	assert(ProjectSettings.get_setting("application/run/main_scene") == INTRO_PATH)
	assert(_tree.change_scene_to_file(INTRO_PATH) == OK)
	await _tree.scene_changed
	var intro: Intro = _tree.current_scene as Intro
	var audio: Audio = _tree.root.get_node("GameAudio") as Audio
	assert(intro != null)
	var player: AnimationPlayer = intro.animation_player
	var picture: TextureRect = intro.get_node("画面") as TextureRect
	var clip: Animation = player.get_animation(&"开头")
	assert(player.is_playing())
	assert(clip.loop_mode == Animation.LOOP_NONE)
	assert(clip.track_get_key_count(0) == 59)
	assert(audio._music_path.is_empty(), "菜单音乐应在动画结束后开始。")
	if "--natural" in OS.get_cmdline_user_args():
		var started_at: int = Time.get_ticks_msec()
		await _tree.scene_changed
		assert(_tree.current_scene is Menu)
		assert(audio._music_path == "event:/Mx_MainMenu")
		var duration: float = float(Time.get_ticks_msec() - started_at) / 1000.0
		assert(absf(duration - clip.length) < 1.0, "正常播放必须按实际时长结束。")
		print("PASS: natural opening playback entered the menu after %.2f seconds." % duration)
		_tree.quit()
		return
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var elapsed: float = 0.0
	var key: int = 0
	for segment in range(FRAME_COUNTS.size()):
		for frame in range(FRAME_COUNTS[segment]):
			assert(is_equal_approx(clip.track_get_key_time(0, key), elapsed))
			player.seek(elapsed + 0.001, true)
			var expected: String = "res://assets/场景动画/开头动画/p%d/%03d.png" % [segment + 1, frame + 1]
			assert(picture.texture.resource_path == expected, "画面必须按原始帧号顺序播放。")
			assert(picture.texture.get_size() == Vector2(1920, 1080))
			elapsed += 1.0 / FRAME_RATES[segment]
			key += 1
	assert(is_equal_approx(clip.length, elapsed))
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_intro(intro, player)
	player.stop()
	player.play(&"开头")
	player.advance(clip.length - 0.01)
	await _tree.process_frame
	assert(_tree.current_scene == intro, "最后一帧播放结束前必须留在开头动画。")
	assert(picture.texture.resource_path.ends_with("p8/014.png"))
	player.advance(0.02)
	await _tree.scene_changed
	assert(_tree.current_scene is Menu, "播放结束必须自动进入原主菜单。")
	assert(audio._music_path == "event:/Mx_MainMenu")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture("menu")
	var menu: Menu = _tree.current_scene as Menu
	var start_scene: String = menu.start_scene
	(menu.get_node("画布/开始") as Button).pressed.emit()
	await _tree.scene_changed
	assert(_tree.current_scene.scene_file_path == start_scene)
	var game_menu: Control = _tree.current_scene.get_node("HUD/Interface/GameMenu")
	game_menu.set_open(true)
	game_menu.get_node("%MainMenu").pressed.emit()
	game_menu.get_node("%ConfirmAction").pressed.emit()
	await _tree.scene_changed
	assert(_tree.current_scene is Menu, "返回菜单不能重播开头动画。")
	print("PASS: startup, all 59 frames/rates, final-frame hold, menu music, Start and return.")
	_tree.quit()


func _capture_intro(intro: Intro, player: AnimationPlayer) -> void:
	_tree.root.mode = Window.MODE_WINDOWED
	for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		_tree.root.size = dimensions
		await _tree.process_frame
		await _tree.process_frame
		assert(intro.size.x >= 1920.0)
		var picture: TextureRect = intro.get_node("画面") as TextureRect
		assert(picture.size == intro.size)
		assert(picture.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		for sample in [10.6389, 10.8389, 11.0389, 12.2389, 13.4389]:
			player.seek(sample, true)
			await _capture("intro_%dx%d_%.1f" % [dimensions.x, dimensions.y, sample])


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var destination: String = "res://artifacts/opening_animation_part2_20261013_%s.png" % label
	assert(_tree.root.get_texture().get_image().save_png(destination) == OK)
