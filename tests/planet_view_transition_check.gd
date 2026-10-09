extends SceneTree

const PlayScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const PlayScript = preload("res://features/场景预览/游玩预览.gd")
const PlanetViewController = preload("res://scripts/planet_view_controller.gd")
const PlanetArt = preload("res://scripts/场景动画/星球贴图.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		var game: PlayScript = PlayScene.instantiate() as PlayScript
		root.add_child(game)
		current_scene = game
		game.set_process(false)
		game._view.set_process(false)
		game._layout.set_process(false)
		game._window_has_focus = true
		await process_frame
		await process_frame
		game._apply_layout()
		var art: PlanetArt = game._planet.get_node("星球画面") as PlanetArt
		art.animation_player.callback_mode_process = (
			AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		)
		art.animation_player.advance(0.25)
		_check_reference_framing(art, resolution)
		var nests: Array[NestView] = game._nest_views.duplicate()
		var positions: Array[Vector2] = []
		for nest: NestView in nests:
			positions.append(nest.position)
		var near_transform: Transform2D = game._world.get_global_transform_with_canvas()
		await _check_direction(game, false, resolution)
		await _check_direction(game, true, resolution)
		_check(
			game._world.get_global_transform_with_canvas().is_equal_approx(near_transform),
			"round trip returns to the exact original near framing"
		)
		_check(game._nest_views == nests, "transitions keep the same nest instances")
		for index: int in range(nests.size()):
			_check(
				nests[index].position == positions[index], "transitions preserve world positions"
			)
		_check_interruptions(game)
		await _check_bubble_focus(game, resolution)
		current_scene = null
		game.queue_free()
		await process_frame
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print(
			"PASS: shared planet, stable zoom/reversal, bubble navigation to local monster groups, UI/tool input gates and preserved world state at both resolutions."
		)
	quit(0 if _failures.is_empty() else 1)


func _check_direction(game: PlayScript, to_near: bool, resolution: Vector2i) -> void:
	var camera: PlanetViewController = game._view
	var steps: float = 1.0 if to_near else -1.0
	var initial: Transform2D = game._world.get_global_transform_with_canvas()
	var initial_blend: float = camera.near_blend
	var rotation: float = game._world.rotation
	var art: PlanetArt = game._planet.get_node("星球画面") as PlanetArt
	var original_texture: Texture2D = art.sprite.texture
	var original_phase: float = art.animation_player.current_animation_position
	var local_art: Transform2D = (
		game._world.get_global_transform_with_canvas().affine_inverse()
		* art.sprite.get_global_transform_with_canvas()
	)
	var source_projection: Transform2D = art.sprite.get_global_transform_with_canvas()
	var label: String = "in" if to_near else "out"
	var pointer: Vector2 = Vector2(16.0, 280.0)
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.position = pointer
	wheel.global_position = pointer
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP if to_near else MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	root.push_input(wheel, true)
	_check(camera.is_transitioning(), "wheel starts an animated transition")
	_check(camera.transition_seconds <= 1.0, "default transition takes at most one second")
	_check(
		game._world.get_global_transform_with_canvas().is_equal_approx(initial),
		"wheel input has no first-frame transform jump"
	)
	_check(is_equal_approx(camera.near_blend, initial_blend), "wheel preserves initial artwork")
	await _capture(game, label, 0, resolution)
	var previous_scale: float = game._world.scale.y
	for frame: int in range(1, 49):
		camera._process(camera.transition_seconds / 48.0)
		var next_scale: float = game._world.scale.y
		_check(
			next_scale >= previous_scale if to_near else next_scale <= previous_scale,
			"zoom scale moves monotonically toward its destination"
		)
		previous_scale = next_scale
		_check(
			(
				game._planet.get_child_count() == 1
				and art.visible
				and is_equal_approx(art.modulate.a, 1.0)
			),
			"one opaque planet sprite is used throughout the zoom"
		)
		_check(
			(
				art.sprite.texture == original_texture
				and is_equal_approx(art.animation_player.current_animation_position, original_phase)
			),
			"view changes do not replace the texture or restart its animation phase"
		)
		for uv: Vector2 in [Vector2(0.35, 0.26), Vector2(0.56, 0.18), Vector2(0.24, 0.57)]:
			var texel: Vector2 = original_texture.get_size() * uv
			var displayed: Vector2 = art.sprite.get_global_transform_with_canvas() * texel
			var world_point: Vector2 = (
				game._world.get_global_transform_with_canvas().affine_inverse() * displayed
			)
			_check(
				world_point.distance_to(local_art * texel) < 0.001,
				"each texture landmark remains attached to the same world-space point"
			)
		_check(
			absf(camera.projection_root.scale.x / camera.projection_root.scale.y - 1.0) < 0.036,
			"temporary lens pull stays below four percent instead of flattening the planet"
		)
		_check(
			absf(angle_difference(game._world.rotation, rotation)) < 0.0001,
			"rotation remains fixed throughout zoom"
		)
		if frame == 12:
			_check(
				(
					camera.projection_root.scale.y > 1.0
					if to_near
					else camera.projection_root.scale.y < 1.0
				),
				"the zoom has a small directional lens pull"
			)
			_check(
				absf(next_scale / initial.y.length() - 1.0) > 0.08,
				"first 0.2 seconds produce a visible size change"
			)
			_check(
				is_equal_approx(camera.near_blend, initial_blend),
				"first zoom beat retains source artwork in both directions"
			)
			camera.zoom_steps(steps)
			camera.begin_drag(pointer)
			_check(not camera.is_dragging(), "dragging cannot interrupt transition framing")
			var ground: Vector2 = game._planet.get_nest_position(-PI / 2.0)
			_check(
				not game._can_collect(ground, game.run.get_pipe_radius()),
				"tools cannot collect against a moving projection"
			)
		if frame in [12, 24, 30, 36, 48]:
			await _capture(game, label, frame, resolution)
	# Absorb floating point accumulation without advancing idle rotation.
	if camera.is_transitioning():
		camera._process(0.00001)
	_check(not camera.is_transitioning(), "repeated wheel input does not extend the transition")
	_check(
		camera.projection_root.scale.is_equal_approx(Vector2.ONE),
		"both endpoint views use uniform scale"
	)
	var relative_projection: Transform2D = (
		art.sprite.get_global_transform_with_canvas() * source_projection.affine_inverse()
	)
	_check(
		(
			is_equal_approx(relative_projection.x.length(), relative_projection.y.length())
			and absf(relative_projection.x.dot(relative_projection.y)) < 0.001
			and absf(relative_projection.get_rotation()) < 0.0001
		),
		"near and overview textures differ only by uniform zoom and camera translation"
	)
	_check(camera.near_blend == (1.0 if to_near else 0.0), "art reaches its exact endpoint")
	_check(game._nests.visible == to_near, "detail layers finish in the intended view")
	_check(game._near_background.visible == to_near, "near background finishes correctly")
	_check(game._overview_background.visible != to_near, "overview background finishes correctly")
	print("TRANSITION ", resolution, " ", label, " duration=", camera.transition_seconds)


func _check_reference_framing(art: PlanetArt, resolution: Vector2i) -> void:
	if resolution != Vector2i(1920, 1080):
		return
	# Measured against the supplied 4000 x 2251 composition, independently of
	# camera settings. These anchors catch a wrong heading, radius or crop.
	var source_uvs: Array[Vector2] = [Vector2(0.13, 0.30), Vector2(0.19, 0.48), Vector2(0.23, 0.64)]
	var reference_points: Array[Vector2] = [
		Vector2(3545.563, 1307.667),
		Vector2(2195.120, 1743.583),
		Vector2(994.731, 2034.177),
	]
	for index: int in range(source_uvs.size()):
		var texel: Vector2 = art.sprite.texture.get_size() * source_uvs[index]
		var displayed: Vector2 = art.sprite.get_global_transform_with_canvas() * texel
		var expected: Vector2 = (
			reference_points[index] / Vector2(4000.0, 2251.0) * Vector2(resolution)
		)
		_check(
			displayed.distance_to(expected) < 2.0,
			"near-view texture anchors match the supplied reference within two pixels"
		)


func _check_interruptions(game: PlayScript) -> void:
	var camera: PlanetViewController = game._view
	camera.zoom_steps(-1.0)
	camera._process(0.35)
	var midway: Transform2D = game._world.get_global_transform_with_canvas()
	var blend: float = camera.near_blend
	camera.zoom_steps(1.0)
	camera._process(0.0)
	_check(
		game._world.get_global_transform_with_canvas().is_equal_approx(midway),
		"reverse wheel starts from the displayed transform"
	)
	_check(is_equal_approx(camera.near_blend, blend), "reverse wheel preserves the displayed blend")
	camera._process(0.1)
	_check(game._world.scale.y > midway.y.length(), "reverse wheel smoothly zooms back in")
	camera.configure(game._layout.apply_layout(root.get_visible_rect().size), game._planet.radius)
	_check(camera.is_transitioning(), "layout refresh preserves the active transition")
	camera._process(1.0)
	_check(not camera.is_transitioning() and not camera.is_overview(), "reverse completes in time")
	camera.zoom_steps(-1.0)
	camera._process(0.4)
	game.restart_run()
	_check(
		not camera.is_transitioning() and camera.zoom_amount == 1.0 and camera.near_blend == 1.0,
		"restart cancels animation and restores near presentation"
	)
	camera._process(1.0)
	_check(camera.zoom_amount == 1.0, "cancelled transition cannot resume after reset")
	camera.transition_seconds = 0.0
	camera.zoom_steps(-1.0)
	_check(
		camera.is_overview() and not camera.is_transitioning() and camera.zoom_amount == 0.0,
		"zero duration supports immediate layout setup"
	)
	game.restart_run()


func _check_bubble_focus(game: PlayScript, resolution: Vector2i) -> void:
	game._view.transition_seconds = 0.8
	game.run.advance(game.run.settings.spawn_intervals[0] + game.run.settings.spawn_interval_jitter)
	game._active_tool = game.ToolMode.NET
	game.run.net_unlocked = true
	var actors: Array[PrototypeSlime] = game._slimes.duplicate()
	var nests: Array[NestView] = game._nest_views.duplicate()
	var candy: int = game.run.candy
	var screen: Vector2 = root.get_visible_rect().size
	# Both sides of the angle seam, both species and a side-facing cluster.
	for angle: float in [0.4, PI - 0.03, -PI + 0.03]:
		for index: int in range(actors.size()):
			var actor: PrototypeSlime = actors[index]
			actor._process(actor.launch_seconds)
			actor.set_process(false)
			actor.species = (
				PrototypeSlime.Species.SLIME if index % 2 == 0 else PrototypeSlime.Species.MUCUS
			)
			actor.position = Vector2.from_angle(angle) * game._planet.radius * 0.96
		var position_before: Vector2 = actors[0].position
		game._view.zoom_steps(-1.0, false)
		game._world.rotation = -angle + 0.3
		game._apply_layout()
		game._view._process(5.0)
		game._refresh_overview()
		game._overview._process(10.0)
		var bubble: OverviewEcology.Bubble = game._overview.bubbles[0]
		var pointer: Vector2 = bubble.get_global_transform_with_canvas().origin
		_check(not game._layout.is_over_ui(pointer), "bubble fixture is accessible outside the HUD")
		_check(game._overview.get_bubble_at(pointer) != null, "visible bubble body is clickable")
		_check(game._overview.get_bubble_at(Vector2.ZERO) == null, "blank sky is not a bubble")
		var selected_angle: float = game._overview.get_bubble_at(pointer).cluster.angle
		var target: Vector2 = (
			Vector2.from_angle(selected_angle) * game._planet.get_outer_radius(selected_angle)
		)
		var initial: Transform2D = game._world.get_global_transform_with_canvas()
		game._layout._show_technology()
		_bubble_click(pointer, true)
		_bubble_click(pointer, false)
		_check(game._view.is_overview(), "technology overlay blocks bubble clicks")
		game._layout.close_panels()
		game._on_window_focus_exited()
		_bubble_click(pointer, true)
		_bubble_click(pointer, false)
		_check(game._view.is_overview(), "unfocused window blocks bubble clicks")
		game._on_window_focus_entered()
		game._view.begin_drag(Vector2.ZERO)
		_bubble_click(pointer, true)
		_bubble_click(pointer, false)
		_check(game._view.is_overview(), "active right drag blocks left-click navigation")
		game._view.end_drag()
		await _capture(game, "bubble_overview", 0, resolution)
		_bubble_click(pointer, true)
		_check(
			not game._view.is_overview() and game._view.is_transitioning(),
			"left click starts near navigation"
		)
		_check(
			game._world.get_global_transform_with_canvas().is_equal_approx(initial),
			"bubble navigation has no first-frame jump"
		)
		game._view._process(0.0)
		_check(
			game._world.get_global_transform_with_canvas().is_equal_approx(initial),
			"navigation preserves the displayed starting rotation"
		)
		game._view._process(0.4)
		var midway: Transform2D = game._world.get_global_transform_with_canvas()
		_bubble_click(pointer, true)
		_check(
			game._world.get_global_transform_with_canvas().is_equal_approx(midway),
			"repeated clicks cannot retarget an active transition"
		)
		await _capture(game, "bubble_midway", 0, resolution)
		game._view._process(0.4)
		_check(
			not game._view.is_transitioning(),
			"bubble navigation finishes within the existing transition duration"
		)
		var near_target: Vector2 = game._world.get_global_transform_with_canvas() * target
		var near_center_x: float = screen.x * (0.5 + game._view.near_horizontal_offset_ratio)
		_check(
			absf(near_target.x - near_center_x) < 0.1,
			"selected monster region reaches the near horizon center"
		)
		_check(
			near_target.y < game._world.get_global_transform_with_canvas().origin.y,
			"selected region appears at the upper horizon"
		)
		_check(
			game._nests.visible and game._slime_root.visible and game._near_background.visible,
			"near gameplay layers are restored"
		)
		_check(
			game._overview.get_bubble_at(pointer) == null, "hidden overview cannot accept clicks"
		)
		game._process(0.0)
		_check(
			game._view_blocks_tool_until_release and game._net_phase == game.NetPhase.IDLE,
			"holding the bubble click cannot cast a net after arrival"
		)
		_check(game.run.net_cooldown_remaining == 0.0, "navigation does not spend a net cooldown")
		_bubble_click(pointer, false)
		game._process(0.0)
		_check(
			not game._view_blocks_tool_until_release,
			"releasing the navigation click restores tool input"
		)
		_check(
			game._can_collect(actors[0].position, game.run.get_net_radius()),
			"the selected monster group is playable after arrival"
		)
		_check(
			game._slimes == actors and game._nest_views == nests and game.run.candy == candy,
			"navigation preserves live entities and progress"
		)
		_check(actors[0].position == position_before, "navigation does not teleport monsters")
		await _capture(game, "bubble_near", 0, resolution)
	# A disappearing cluster may remain visible during its fade, but is not a target.
	game._view.zoom_steps(-1.0, false)
	game._overview._process(10.0)
	var old_center: Vector2 = game._overview.bubbles[0].position
	game._overview.update_ecology(PackedVector2Array(), PackedInt32Array(), true, screen)
	_check(
		game._overview.get_bubble_at(old_center) == null,
		"retired bubbles cannot navigate to an empty group"
	)


func _bubble_click(position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = root.get_final_transform() * position
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _capture(game: PlayScript, direction: String, frame: int, resolution: Vector2i) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	game._overview._process(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = (
		"res://artifacts/zoom_%s_%02d_%dx%d.png" % [direction, frame, resolution.x, resolution.y]
	)
	_check(root.get_texture().get_image().save_png(path) == OK, "transition screenshot saved")


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
