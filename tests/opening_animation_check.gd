extends Node

const Intro = preload("res://scenes/开头动画/开头动画.gd")
const Menu = preload("res://scenes/主菜单/主菜单.gd")
const Audio = preload("res://scripts/fmod_audio.gd")
const StoryFlow = preload("res://features/tutorial_intro/story_flow.gd")
const MENU_PATH: String = "res://scenes/主菜单/主菜单.tscn"
const INTRO_PATH: String = "res://scenes/开头动画/开头动画.tscn"
const FRAME_COUNTS: Array[int] = [4, 4, 3, 3, 7, 11, 9]
const FRAME_RATES: Array[float] = [4.0, 3.0, 3.0, 4.0, 5.0, 4.5, 5.0]

var _tree: SceneTree
var _capture_directory: String = ""


func _ready() -> void:
	_tree = get_tree()
	_tree.current_scene = null
	_run.call_deferred()


func _run() -> void:
	assert(ProjectSettings.get_setting("application/run/main_scene") == MENU_PATH)
	assert(_tree.change_scene_to_file(MENU_PATH) == OK)
	await _tree.scene_changed
	var audio: Audio = _tree.root.get_node("GameAudio") as Audio
	var menu: Menu = _tree.current_scene as Menu
	assert(menu != null)
	assert(audio._music_path == "event:/Mx/Mx_MainMenu", "启动先显示主菜单并播放菜单音乐。")
	(menu.get_node("画布/开始") as Button).pressed.emit()
	assert(audio.is_transition_playing(), "点击开始游戏时立即播放开始音效。")
	assert(_tree.current_scene == menu, "开始音效到交接点之前停留在主菜单。")
	await _tree.scene_changed
	assert(not audio.is_transition_playing(), "开始音效到交接点后才进入片头。")
	assert(_tree.current_scene.scene_file_path == INTRO_PATH)
	var intro: Intro = _tree.current_scene as Intro
	assert(intro != null)
	var player: AnimationPlayer = intro.animation_player
	var picture: TextureRect = intro.get_node("画面") as TextureRect
	var clip: Animation = player.get_animation(&"开头")
	assert(player.is_playing())
	assert(clip.loop_mode == Animation.LOOP_NONE)
	assert(clip.track_get_key_count(0) == 41)
	assert(audio._music_path.is_empty(), "进入片头后菜单音乐应淡出。")
	if "--natural" in OS.get_cmdline_user_args():
		var started_at: int = Time.get_ticks_msec()
		var notice_seconds: float = (
			intro._briefing.transition_seconds * 2.0
			+ intro._briefing.reveal_seconds * 3.0
			+ intro._briefing.section_hold_seconds * 2.0
			+ intro._briefing.final_hold_seconds
		)
		while not intro._briefing.playing:
			await _tree.process_frame
		_assert_briefing_music(audio)
		while audio.is_transition_playing():
			await _tree.process_frame
		assert(
			audio._music_path == "event:/Mx/Mx_GamePlay" and _tree.current_scene == intro,
			"片头音效淡出后、委托书期间游戏音乐开始。"
		)
		await _tree.scene_changed
		assert(_tree.current_scene.scene_file_path == Menu.DEFAULT_START_SCENE)
		var duration: float = float(Time.get_ticks_msec() - started_at) / 1000.0
		await _check_opening_zoom(_tree.current_scene.get_node("StoryFlow") as StoryFlow)
		assert(absf(duration - clip.length - notice_seconds) < 1.5, "开头动画和委托书均按实际时长播放。")
		print(
			(
				"PASS: menu Start played the opening and entered gameplay after %.2f seconds."
				% duration
			)
		)
		_tree.quit()
		return
	# Drive the animation manually, while keeping gameplay's background load poll active.
	intro._syncing_sound = false
	player.speed_scale = 1.0
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
	assert(picture.texture.resource_path.ends_with("p7/009.png"))
	player.advance(0.02)
	assert(intro._briefing.playing, "开头动画结束后先显示不可跳过的委托书。")
	_assert_briefing_music(audio)
	await _tree.scene_changed
	assert(_tree.current_scene.scene_file_path == Menu.DEFAULT_START_SCENE, "片头播放结束必须自动进入正式游戏。")
	assert(_tree.current_scene.has_node("StoryFlow"), "正式游戏挂载七段看板娘剧情。")
	assert(not _tree.current_scene.has_node("PreviewNavigation"), "正式游戏不能带入预览快捷跳段。")
	assert(not _tree.paused and is_equal_approx(Engine.time_scale, 1.0))
	assert(not _tree.current_scene.is_processing(), "开场演出期间暂停玩法推进。")
	_assert_gameplay_music(audio)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture("gameplay")
	var game_menu: Control = _tree.current_scene.get_node("HUD/Interface/GameMenu")
	game_menu.set_open(true)
	game_menu.get_node("%MainMenu").pressed.emit()
	game_menu.get_node("%ConfirmAction").pressed.emit()
	await _tree.scene_changed
	assert(_tree.current_scene is Menu, "返回菜单不能重播开头动画。")
	assert(is_equal_approx(Engine.time_scale, 1.0), "退出剧情后恢复全局速度。")
	print(
		"PASS: menu startup, Start, all 41 frames/rates, final-frame hold, gameplay music and return."
	)
	_tree.quit()


# The briefing requests gameplay music in its far-view mix.
func _assert_briefing_music(audio: Audio) -> void:
	_assert_gameplay_music(audio)
	assert(
		is_equal_approx(FmodServer.get_global_parameter_by_name("IsDistantView"), 1.0),
		"委托书出现时游戏音乐以远景混音（IsDistantView = 1）开始。"
	)


# The game opens on the far view, then zooms in with ZoomIn while the music
# follows to its near-view mix.
func _check_opening_zoom(story: StoryFlow) -> void:
	var distant: Callable = func() -> float:
		return FmodServer.get_global_parameter_by_name("IsDistantView")
	assert(story.phase == StoryFlow.Phase.OVERVIEW and is_equal_approx(distant.call(), 1.0))
	var zoom_in: FmodEventDescription = FmodServer.get_event("event:/UI/ZoomIn")
	var zooms: int = zoom_in.get_instance_count()
	while story.phase == StoryFlow.Phase.OVERVIEW:
		await _tree.process_frame
	assert(zoom_in.get_instance_count() > zooms, "远景切到近景时播放 ZoomIn。")
	while story.phase == StoryFlow.Phase.ZOOMING:
		await _tree.process_frame
	assert(is_zero_approx(distant.call()), "切到近景后 IsDistantView 回到 0。")


func _assert_gameplay_music(audio: Audio) -> void:
	assert(
		(
			audio._music_path == "event:/Mx/Mx_GamePlay"
			or audio._pending_music_path == "event:/Mx/Mx_GamePlay"
		),
		"片头结束后应直接进入游戏音乐。"
	)


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
		for sample in [2.001, 2.334, 7.707, 7.929, 9.529]:
			player.seek(sample, true)
			await _capture("intro_%dx%d_%.1f" % [dimensions.x, dimensions.y, sample])


func _capture(label: String) -> void:
	if _capture_directory.is_empty():
		_capture_directory = (
			"res://artifacts/opening_animation_%d_%d"
			% [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		)
		assert(DirAccess.make_dir_recursive_absolute(_capture_directory) == OK)
		print("CAPTURE: " + _capture_directory)
	await _tree.process_frame
	await _tree.process_frame
	await RenderingServer.frame_post_draw
	var destination: String = "%s/%s.png" % [_capture_directory, label]
	assert(_tree.root.get_texture().get_image().save_png(destination) == OK)
