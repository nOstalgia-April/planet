extends Node

const DemoScript = preload("res://scripts/disk_demo.gd")
const PipeCursor = preload("res://scripts/pipe_cursor.gd")
const VacuumSkin = preload("res://scripts/vacuum_skin.gd")
const DemoScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const NET_ANCHOR: Vector2 = Vector2(0.0, -235.0)

var _failures: int = 0

@onready var root: Window = get_tree().root


func _ready() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	get_tree().current_scene = demo
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	demo._window_has_focus = true
	demo.run.settings = demo.run.settings.duplicate() as PrototypeSettings
	demo.run.settings.spawn_interval_jitter = 0.0
	await _check_pipe_transport(demo)
	await _check_skin_states(demo)
	for child: Node in demo.get_node("Audio").get_children():
		if child is AudioStreamPlayer:
			child.stop()
	get_tree().current_scene = null
	demo.queue_free()
	await get_tree().process_frame
	if _failures == 0:
		print(
			"PASS: empty tube, cancelled intake, confirmed single capture, continuous transport, queued capture, target loss, tool switch, focus, restart, species skin, combo priority, expiry and queued bottom-up transitions."
		)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_pipe_transport(demo: DemoScript) -> void:
	demo.restart_run()
	var actor: PrototypeSlime = _prepare_one(demo)
	var player: AnimationPlayer = demo._pipe._art.animation_player
	var callback_mode: AnimationMixer.AnimationCallbackModeProcess = player.callback_mode_process
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var duration: float = player.get_animation(demo._pipe._art.clip).length
	var empty_point: Vector2 = NET_ANCHOR + Vector2.RIGHT * 80.0
	var sprite: Sprite2D = demo._pipe._art.get_node("贴图") as Sprite2D

	demo._drive_tool(0.1, actor.get_capture_point(), false)
	_check(
		actor.capture_progress > 0.0 and not player.is_playing(),
		"An unfinished capture never starts material transport."
	)
	demo._drive_tool(0.1, empty_point, false)
	_check(
		demo._pipe.visible and not player.is_playing(),
		"Empty hovering and cancelled progress keep the visible tube idle."
	)
	await _save(demo, "idle")
	demo._drive_tool(demo.run.get_pipe_capture_seconds(), actor.get_capture_point(), false)
	_check(
		player.is_playing() and demo._pipe.transport_state == PipeCursor.TransportState.SINGLE,
		"An actual paid capture starts one transport cycle."
	)
	player.advance(0.6)
	demo._drive_tool(0.0, empty_point, false)
	_check(
		player.is_playing() and is_equal_approx(player.current_animation_position, 0.6),
		"Moving to empty ground lets a confirmed transport finish without rewinding."
	)
	await _save(demo, "single")
	player.advance(duration - 0.6 + 0.01)
	_check(
		(
			demo._pipe.transport_state == PipeCursor.TransportState.IDLE
			and not player.is_playing()
			and sprite.texture.resource_path.ends_with("001.png")
		),
		"One capture finishes exactly one cycle and restores the empty tube."
	)
	await _save(demo, "finished")

	demo.restart_run()
	actor = _prepare_one(demo)
	var next_actor: PrototypeSlime = demo._slimes[1]
	_place_body(next_actor, NET_ANCHOR)
	demo._drive_tool(demo.run.get_pipe_capture_seconds(), actor.get_capture_point(), false)
	player.advance(0.35)
	demo._drive_tool(0.1, next_actor.get_capture_point(), false)
	_check(
		(
			demo._pipe.transport_state == PipeCursor.TransportState.CONTINUOUS
			and is_equal_approx(player.current_animation_position, 0.35)
		),
		"The next target sustains transport without restarting its current cycle."
	)
	player.advance(duration - 0.35 + 0.01)
	_check(player.is_playing(), "Ongoing intake continues across the animation boundary.")
	player.advance(0.2)
	demo._drive_tool(demo.run.get_pipe_capture_seconds(), next_actor.get_capture_point(), false)
	_check(
		is_equal_approx(player.current_animation_position, 0.2),
		"A second confirmed capture never rewinds the in-flight cycle."
	)
	demo._drive_tool(0.0, empty_point, false)
	player.advance(duration - 0.2 + 0.01)
	_check(player.is_playing(), "A capture during playback receives a complete final cycle.")
	player.advance(duration + 0.01)
	_check(
		not player.is_playing() and demo._pipe.transport_state == PipeCursor.TransportState.IDLE,
		"Continuous intake drains and returns to idle after the last confirmed capture."
	)

	for interruption: String in ["target_loss", "tool", "focus", "restart"]:
		demo.restart_run()
		actor = _prepare_one(demo)
		next_actor = demo._slimes[1]
		_place_body(next_actor, NET_ANCHOR)
		demo._drive_tool(demo.run.get_pipe_capture_seconds(), actor.get_capture_point(), false)
		player.advance(0.3)
		demo._drive_tool(0.1, next_actor.get_capture_point(), false)
		match interruption:
			"target_loss":
				demo._drive_tool(0.0, empty_point, false)
				_check(
					player.is_playing(), "Losing an unfinished target completes the current cycle."
				)
				player.advance(duration - 0.3 + 0.01)
			"tool":
				demo.run.candy = (
					demo.run.settings.net_unlock_cost + demo.run.get_pipe_upgrade_cost()
				)
				_check(demo.run.upgrade_pipe(), "The net fixture buys its pipe prerequisite.")
				_check(
					demo.run.purchase_technology("net"), "The net fixture unlocks the second tool."
				)
				demo._select_tool(DemoScript.ToolMode.NET)
			"focus":
				demo._on_window_focus_exited()
				demo._on_window_focus_entered()
			"restart":
				demo.restart_run()
		_check(
			(
				not player.is_playing()
				and demo._pipe.transport_state == PipeCursor.TransportState.IDLE
			),
			"Transport clears at the %s boundary." % interruption
		)
	player.callback_mode_process = callback_mode


func _save(demo: DemoScript, label: String) -> void:
	if not ("--capture" in OS.get_cmdline_user_args()):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder: String = "res://artifacts/vacuum_skin_20261013"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_check(
		root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK,
		"The rendered %s state is saved." % label
	)
	demo._window_has_focus = true


func _check_skin_states(demo: DemoScript) -> void:
	demo.restart_run()
	var art: VacuumSkin = demo._pipe._art
	art.set_process(false)
	var actor: PrototypeSlime = _prepare_one(demo)
	demo._drive_tool(0.01, actor.get_capture_point(), false)
	_check(
		art.requested_skin == VacuumSkin.SkinKind.DEFAULT, "Partial capture does not change skin."
	)
	demo._drive_tool(demo.run.get_pipe_capture_seconds(), actor.get_capture_point(), false)
	_check(art.target_skin == VacuumSkin.SkinKind.PINK, "A collected pink slime starts pink skin.")
	art._process(art.transition_seconds * 0.5)
	_check(
		is_equal_approx(art.progress, 0.5), "The bottom-up wipe advances over its configured time."
	)
	await _save(demo, "pink_half")
	art._process(art.transition_seconds)
	_check(art.current_skin == VacuumSkin.SkinKind.PINK, "Pink skin finishes.")
	art.seek_frame(3)
	_check(
		art.get_node("贴图").texture == art.pink_frames[3],
		"The skin follows the same transport frame."
	)
	demo._pipe.reset_transport()
	_check(art.current_skin == VacuumSkin.SkinKind.PINK, "Finishing transport preserves skin.")
	await _save(demo, "pink")

	actor = _prepare_one(demo)
	actor.species = PrototypeSlime.Species.MUCUS
	actor.slime_art.configure_species(actor.species)
	# Place the body away from mucus so this fixture tests collection, not detachment.
	actor.on_mucus = false
	actor.detached_remaining = 10.0
	demo._drive_tool(demo._capture_seconds_for(actor) + 1.0, actor.get_capture_point(), false)
	_check(
		art.target_skin == VacuumSkin.SkinKind.BLUE, "A collected mucus slime selects blue skin."
	)
	art._process(art.transition_seconds)
	await _save(demo, "blue")

	# Keep rule ownership in PrototypeRun and reach the actual configured combo threshold.
	for index: int in range(demo.run.get_combo_target()):
		demo.run.advance(demo.run.settings.spawn_intervals[0])
	demo.run.combo_level = 1
	for index: int in range(demo.run.get_combo_target()):
		actor = _prepare_one(demo, false)
		demo._drive_tool(demo.run.get_pipe_capture_seconds(), actor.get_capture_point(), false)
		art._process(art.transition_seconds)
	_check(
		demo.run.combo_count == 0 and art.requested_skin == VacuumSkin.SkinKind.RAINBOW,
		"The actual combo threshold requests rainbow skin."
	)
	art._process(art.transition_seconds)
	await _save(demo, "rainbow")
	_check(art.current_skin == VacuumSkin.SkinKind.RAINBOW, "Rainbow skin takes priority.")
	demo._pipe._advance_combo_burst(3.0)
	demo._drive_tool(0.0, NET_ANCHOR + Vector2.RIGHT * 80.0, false)
	art._process(art.transition_seconds)
	_check(
		art.current_skin == VacuumSkin.SkinKind.PINK, "Completed burst restores the latest species."
	)

	art.request_skin(VacuumSkin.SkinKind.BLUE)
	art._process(art.transition_seconds * 0.25)
	art.request_skin(VacuumSkin.SkinKind.RAINBOW)
	art.request_skin(VacuumSkin.SkinKind.PINK)
	_check(
		art.target_skin == VacuumSkin.SkinKind.BLUE and is_equal_approx(art.progress, 0.25),
		"Rapid requests do not rewind or replace the current wipe."
	)
	art._process(art.transition_seconds)
	_check(art.target_skin == VacuumSkin.SkinKind.PINK, "Only the latest pending skin is retained.")
	art._process(art.transition_seconds)
	demo._pipe.hide()
	demo._pipe.show()
	_check(art.current_skin == VacuumSkin.SkinKind.PINK, "Temporary hiding preserves the skin.")
	demo.restart_run()
	_check(
		(
			art.current_skin == VacuumSkin.SkinKind.DEFAULT
			and art.transition == VacuumSkin.Transition.STABLE
		),
		"Restart clears current skin and pending transitions."
	)
	art.set_process(true)


func _prepare_one(demo: DemoScript, spawn: bool = true) -> PrototypeSlime:
	demo._window_has_focus = true
	demo._select_tool(DemoScript.ToolMode.PIPE)
	if spawn:
		demo.run.advance(demo.run.settings.spawn_intervals[0])
	assert(demo._slimes.size() >= 2, "The transport fixture needs two real actors.")
	for actor: PrototypeSlime in demo._slimes:
		actor.restore_to_surface(Vector2.LEFT * 235.0)
		actor.set_process(false)
	var actor: PrototypeSlime = demo._slimes[0]
	_place_body(actor, NET_ANCHOR)
	return actor


func _place_body(actor: PrototypeSlime, point: Vector2) -> void:
	actor.restore_to_surface(point)
	actor.set_process(false)
	actor.position += point - actor.get_capture_point()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
