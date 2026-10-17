extends Node

const Play = preload("res://features/场景预览/游玩预览.gd")
const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Victory = preload("res://scripts/victory_meteor_presentation.gd")
const Restoration = preload("res://scripts/planet_restoration.gd")

var _game: Play
var _failures: Array[String] = []
var _goals: int = 0
var _finished: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1920, 1080)
	_game = PLAY.instantiate() as Play
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	for node: Node in [
		_game, _game._view, _game._restoration, _game._nest_discovery, _game._victory
	]:
		node.set_process(false)
	_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_game.run.goal_completed.connect(func() -> void: _goals += 1)
	_game._victory.finished.connect(func() -> void: _finished += 1)
	_check_animation_contract()
	await _check_real_victory_and_waiting()
	await _check_camera_and_playback()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_frames()
	_check_restart_and_overview()
	_game.queue_free()
	await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print(
			"PASS: real flower victory, restoration before camera, four FPS single playback, pause, input lock, duplicate requests and restart."
		)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _player() -> AnimationPlayer:
	return _game._victory.meteors.animation_player


func _check_animation_contract() -> void:
	var animation: Animation = _player().get_animation(_game._victory.meteors.clip)
	_check(_game._victory.meteors.frame_count == 4, "Meteor artwork contains four frames.")
	_check(
		is_equal_approx(_game._victory.meteors.frames_per_second, 4.0),
		"Meteor artwork declares four frames per second."
	)
	_check(is_equal_approx(animation.length, 1.0), "Four meteor frames occupy one full second.")
	_check(animation.loop_mode == Animation.LOOP_NONE, "Victory meteors play once.")
	var texture_track: int = animation.find_track(NodePath("贴图:texture"), Animation.TYPE_VALUE)
	_check(texture_track >= 0, "The meteor clip animates its supplied textures.")
	if texture_track >= 0:
		_check(animation.track_get_key_count(texture_track) == 4, "All four textures are keyed.")
		for frame: int in range(animation.track_get_key_count(texture_track)):
			_check(
				is_equal_approx(animation.track_get_key_time(texture_track, frame), frame * 0.25),
				"Texture changes follow the quarter-second frame intervals."
			)
	_check(not _game._victory.meteors.visible, "Meteors are hidden before victory.")


func _check_real_victory_and_waiting() -> void:
	_game.run._add_nest(NestState.Species.MUCUS, Vector2(240, 0))
	_game.run._add_nest(NestState.Species.DRILL, Vector2(-240, 0))
	_game.run.candy = 100000
	_game.run.purchase_technology("cultivation")
	_game.run.purchase_technology("automation")
	for nest: NestState in _game.run.nests:
		for _stage: int in range(3):
			_check(_game.run.upgrade_nest(nest.nest_id), "Fixture upgrades succeed.")
	_check(not _game.run.is_complete, "Automation alone does not start victory meteors.")
	var deadline: int = Time.get_ticks_msec() + 12000
	while _game.run.unlocked_colors.size() < 3 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_game.run.unlocked_colors.size() == 3, "Three real flowers report their colors.")
	_check(_game.run.is_complete and _goals == 1, "Real flower completion wins exactly once.")
	_check(
		_game._restoration.phase != Restoration.Phase.IDLE,
		"The final flower leaves earned restoration work to present."
	)
	_game._show_completion()
	_check(_game._victory.phase == Victory.Phase.IDLE, "Meteors wait for queued restoration.")
	_check(not _game._completion.visible, "The victory panel waits for the whole sequence.")
	_kill_completion_wait()
	for _frame: int in range(400):
		_game._view._process(0.1)
		_game._restoration._process(0.1)
		if _game._restoration.phase == Restoration.Phase.IDLE:
			break
	_check(
		(
			_game._restoration.phase == Restoration.Phase.IDLE
			and _game._restoration.completed_species.size() == 3
		),
		"All three earned color presentations finish before meteors."
	)
	_check(
		is_equal_approx(_game._restoration.bright_background.modulate.a, 1.0),
		"Victory uses the completed bright background."
	)
	_game.run.record_flower(4)
	_game.run.advance(200.0)
	_check(_goals == 1, "Repeated flower and rules updates do not emit another victory.")


func _check_camera_and_playback() -> void:
	_check(_game._restoration.core.modulate.a == 1.0, "Core survives all color restoration.")
	_game._view.zoom_steps(1.0, false)
	_game._show_completion()
	_check(_game._victory.phase == Victory.Phase.CAMERA, "Near victory starts with camera travel.")
	_check(_game._view.presentation_locked, "Victory owns the camera until meteors finish.")
	_check(not _game._victory.meteors.visible, "Meteors stay hidden during camera travel.")
	_game._victory.play()
	_game._show_completion()
	_game._view.zoom_steps(1.0, false)
	_game._view.begin_drag(Vector2(600, 300))
	_check(
		_game._view.is_overview() and not _game._view.is_dragging(),
		"Zoom and drag input cannot interrupt victory camera travel."
	)
	_check(not _game._can_toggle_view(), "The view shortcut is blocked during victory.")
	_check(
		not _game._can_collect(Vector2(0, -240), 60.0), "Capture input is blocked during victory."
	)
	_game._victory._process(0.0)
	_game._view._process(_game._view.transition_seconds * 0.5)
	_game._victory._process(0.0)
	_check(
		_game._victory.phase == Victory.Phase.CAMERA and not _game._victory.meteors.visible,
		"Targeting overview does not start meteors before the camera arrives."
	)
	await _check_paused_camera()
	_game._view._process(1.0)
	_game._victory._process(0.0)
	_check(_game._victory.phase == Victory.Phase.PLAYING, "Camera arrival starts the meteors.")
	_check(_game._victory.meteors.visible, "Meteor artwork appears at camera arrival.")
	_check(_game._completion.playing, "Credits and meteors start together.")
	_check(_game._restoration.core.modulate.a == 0.0, "Credits use the restored planet artwork.")
	_player().advance(0.375)
	var position: float = _player().current_animation_position
	_game._victory.play()
	_game._show_completion()
	_check(
		is_equal_approx(_player().current_animation_position, position),
		"Repeated play and completion requests do not restart the meteor clip."
	)
	await _check_paused_animation()
	_player().advance(0.615)
	_check(
		_game._victory.phase == Victory.Phase.PLAYING and _finished == 0,
		"The final frame retains its full quarter-second before completion."
	)
	_player().advance(0.02)
	_check(
		_game._victory.phase == Victory.Phase.COMPLETE and _finished == 1,
		"The one-second meteor clip finishes once."
	)
	_check(_game._completion.visible, "The existing victory panel opens after the meteor clip.")
	_check(_game._restoration.core.modulate.a == 0.0, "Core disappears only at the final ending.")
	_check(not _game._view.presentation_locked, "Finished meteors release the camera lock.")
	_check(_game._victory.meteors.visible, "The final meteor frame remains on the victory sky.")
	_game._victory.play()
	_player().advance(2.0)
	_check(
		_game._victory.phase == Victory.Phase.COMPLETE and _finished == 1,
		"A completed meteor presentation cannot repeat in the same run."
	)
	_game._view.zoom_steps(1.0, false)
	_check(
		is_zero_approx(_game._victory.meteors.modulate.a),
		"The retained meteor artwork fades out when returning to near view."
	)
	_game._view.zoom_steps(-1.0, false)
	_check(
		is_equal_approx(_game._victory.meteors.modulate.a, 1.0),
		"The retained meteor artwork returns with the distant sky."
	)


func _check_paused_camera() -> void:
	var zoom: float = _game._view.zoom_amount
	_game._view.set_process(true)
	_game._victory.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.08, true, false, true).timeout
	_check(is_equal_approx(_game._view.zoom_amount, zoom), "Pause freezes victory camera travel.")
	_check(_game._victory.phase == Victory.Phase.CAMERA, "Pause cannot start the meteor clip.")
	get_tree().paused = false
	_game._view.set_process(false)
	_game._victory.set_process(false)


func _check_paused_animation() -> void:
	var position: float = _player().current_animation_position
	_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_game._victory.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.08, true, false, true).timeout
	_check(
		is_equal_approx(_player().current_animation_position, position),
		"Pause freezes the actual meteor AnimationPlayer."
	)
	_check(_finished == 0 and _game._completion.playing, "Pause cannot finish the sequence.")
	get_tree().paused = false
	_game._victory.set_process(false)
	_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func _check_restart_and_overview() -> void:
	_game.restart_run()
	_check(_game._restoration.core.modulate.a == 1.0, "Restart restores the animated core.")
	_check_reset("completed presentation")
	_game._victory.play()
	_game._view._process(0.2)
	_game.restart_run()
	_check_reset("camera travel")
	_game._view.zoom_steps(-1.0, false)
	_game._victory.play()
	_game._victory._process(0.0)
	_check(
		_game._victory.phase == Victory.Phase.PLAYING and not _game._view.is_transitioning(),
		"An existing overview starts the clip without waiting for unnecessary zoom travel."
	)
	_player().advance(0.3)
	_game.restart_run()
	_check_reset("active meteor clip")
	_player().advance(3.0)
	_game._victory._process(3.0)
	_check(_finished == 1, "Cancelled playback cannot later emit a stale completion.")
	_check(not _game._completion.visible, "Restart cannot reopen the previous victory panel.")
	_game._victory.play()
	_game._view._process(1.0)
	_game._victory._process(0.0)
	_check(_game._victory.phase == Victory.Phase.PLAYING, "Restart rearms meteor playback.")
	_game.restart_run()


func _check_reset(context: String) -> void:
	_check(_game._victory.phase == Victory.Phase.IDLE, "Restart clears phase after " + context)
	_check(not _game._victory.meteors.visible, "Restart hides meteors after " + context)
	_check(not _player().is_playing(), "Restart stops the clip after " + context)
	_check(not _game._view.presentation_locked, "Restart releases the lock after " + context)
	_check(not _game._view.is_overview(), "Restart restores near view after " + context)
	_check(not _game.run.is_complete, "Restart clears rules victory after " + context)


func _capture_frames() -> void:
	var directory: String = (
		"res://artifacts/victory_meteor_%d_%d"
		% [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	)
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Screenshot directory exists.")
	_game._completion.hide()
	_game._view.zoom_steps(-1.0, false)
	_game._pipe.hide()
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_window().size = dimensions
		_game._apply_layout()
		for frame: int in range(4):
			_game._victory.meteors.seek_frame(frame)
			for _draw: int in range(3):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path: String = (
				"%s/%dx%d_frame_%d.png" % [directory, dimensions.x, dimensions.y, frame + 1]
			)
			_check(
				get_viewport().get_texture().get_image().save_png(path) == OK,
				"Fresh victory screenshot saved."
			)
			print("CAPTURE: ", path, " ", Time.get_datetime_string_from_system())
	print("CAPTURES: ", ProjectSettings.globalize_path(directory))


func _kill_completion_wait() -> void:
	if _game._completion_tween != null:
		_game._completion_tween.kill()


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
