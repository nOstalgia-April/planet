extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const NestArt = preload("res://scripts/nest_art.gd")
const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const PLAY_SCENE: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")

var _capture: bool = false
var _failures: int = 0


func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = dimensions
		var demo: DemoScript = PLAY_SCENE.instantiate() as DemoScript
		root.add_child(demo)
		current_scene = demo
		demo.set_process(false)
		demo._view.set_process(false)
		demo._layout.set_process(false)
		demo._window_has_focus = true
		await _settle()
		demo.run.candy = 10000
		_check(demo.run.upgrade_pipe())
		_check(demo.run.purchase_technology("net"))
		_check(demo.run.upgrade_pipe())
		_check(demo.run.purchase_technology("cultivation"))
		_check(demo.run.purchase_technology("automation"))
		var views: Array[NestView] = [demo._nest_views[0], demo._nest_views[2]]
		for view: NestView in demo._nest_views:
			_check(is_equal_approx(view._art._growth.frames_per_second, 12.0))
			for item: ItemArt in view._art.get_children():
				item.animation_player.callback_mode_process = (
					AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				)
		demo.run.advance(demo.run.settings.spawn_intervals[0])
		for actor: PrototypeSlime in demo._slimes:
			actor._process(actor.launch_seconds + 0.1)
			actor.set_process(false)
		await _check_nests(demo, views, dimensions)
		await _check_tools(demo, dimensions)
		_check_rapid_upgrades(demo._nest_views[1])
		demo.restart_run()
		_check(demo._nest_views.size() == 2 and demo._net_phase == DemoScript.NetPhase.IDLE)
		_check(demo._nest_views[0]._art._display_level == 0)
		_check(not demo._nest_views[0]._art._transitioning)
		for audio: AudioStreamPlayer in demo.get_node("Audio").get_children():
			audio.stop()
		current_scene = null
		demo.queue_free()
		await process_frame
	if _failures > 0:
		quit(1)
		return
	print(
		"PASS: live nest upgrades/flowers, production, hover bounds, pipe loop, all five net frames, collection, overview and reset at two resolutions."
	)
	quit()


func _check_nests(demo: DemoScript, views: Array[NestView], dimensions: Vector2i) -> void:
	demo._pipe.hide()
	demo._net.hide()
	_check(not demo._region_root.visible, "The old nest region circles remain hidden.")
	for view: NestView in views:
		_check(view._art._display_level == 0)
		_check_bounds(view)
	await _save("stage_0", dimensions)
	await _check_ground_alignment(demo, views, dimensions, 0)
	for level: int in range(1, 4):
		for view: NestView in views:
			_check(demo.run.upgrade_nest(view.nest_id))
			_check(view._art._transitioning)
			var player: AnimationPlayer = view._art._growth.animation_player
			var clip_time: float = player.current_animation_position
			if level == 3 and view.species == 1:
				_check(is_equal_approx(clip_time, 5.0 / 12.0))
				_check(
					view._art._sprite.texture.resource_path.ends_with("3-4/006.png"),
					"Mucus skips exactly five repeated frames at 12 fps."
				)
			# Economy/population updates must not restart an in-flight upgrade.
			view.update_state(level, level == 3, 3)
			_check(is_equal_approx(player.current_animation_position, clip_time))
			player.advance(0.25)
			_check_bounds(view)
		await _save("upgrade_%d" % level, dimensions)
		for view: NestView in views:
			view._art._growth.animation_player.advance(2.0)
			_check(not view._art._transitioning and view._art._display_level == level)
			_check_bounds(view)
		await _save("stage_%d" % level, dimensions)
		if level in [2, 3]:
			demo._select_nest(views[0].nest_id)
			await _settle()
			await _save("details_%d" % level, dimensions)
			demo._clear_nest_selection()
		await _check_ground_alignment(demo, views, dimensions, level)
	for view: NestView in views:
		_check(view._art._flower.visible and not view._art._growth.visible)
		view._art._flower.animation_player.advance(1.0)
		_check(view._art._flower.animation_player.current_animation == &"待机")
		var candy_before: int = demo.run.candy
		var population: int = demo._slimes.size()
		demo.run.advance(1.0)
		_check(demo.run.candy > candy_before, "The production clip follows actual passive income.")
		_check(demo._slimes.size() == population, "Production preserves the existing actors.")
		var player: AnimationPlayer = view._art._flower.animation_player
		_check(player.current_animation == &"产出")
		player.advance(0.125)
		view.pulse_automatic()
		_check(is_equal_approx(player.current_animation_position, 0.125))
		player.advance(1.0)
		_check(player.current_animation == &"待机")
		_check_bounds(view)


func _check_ground_alignment(
	demo: DemoScript, views: Array[NestView], dimensions: Vector2i, stage: int
) -> void:
	for turn: float in [-0.32, 0.32, 0.0]:
		var screen_radius: float = (
			demo._planet.radius * demo._world.scale.x * demo._view.projection_root.scale.x
		)
		demo._view.begin_drag(Vector2.ZERO)
		demo._view.drag_to(Vector2((turn - demo._world.rotation) * screen_radius, 0.0))
		demo._view.end_drag()
		for actor: PrototypeSlime in demo._slimes:
			# Actors are frozen for reproducible captures; run their normal facing update.
			actor._process(0.0)
			_check(
				actor.get_global_transform_with_canvas().x.normalized().dot(Vector2.RIGHT) > 0.999,
				"Slimes stay upright instead of inheriting the nests' surface angle."
			)
		await _settle()
		for view: NestView in views:
			var angle: float = view.position.angle()
			var projection: Transform2D = demo._world.get_global_transform_with_canvas()
			var surface_direction: Vector2 = (
				(
					projection * demo._planet.get_nest_position(angle + 0.02)
					- projection * demo._planet.get_nest_position(angle - 0.02)
				)
				. normalized()
			)
			var picture: Transform2D = view._art._sprite.get_global_transform_with_canvas()
			_check(
				picture.x.normalized().dot(surface_direction) > 0.999,
				"Nest artwork follows the projected surface tangent while the planet rotates."
			)
			_check(
				absf(picture.x.normalized().dot(picture.y.normalized())) < 0.001,
				"Grounded artwork keeps its proportions under the stretched near projection."
			)
			_check(
				view.position.is_equal_approx(demo.run.get_nest(view.nest_id).position),
				"Visual grounding does not move a nest's gameplay position."
			)
			var pixels: Rect2 = Rect2(view._art._sprite.texture.get_image().get_used_rect())
			for fraction: float in [0.0, 0.5, 1.0]:
				var contact: Vector2 = Vector2(
					lerpf(pixels.position.x, pixels.end.x, fraction), pixels.end.y
				)
				var ground: Vector2 = projection.affine_inverse() * picture * contact
				_check(
					ground.length() <= demo._planet.get_outer_radius(ground.angle()) + 2.0,
					"The artwork's base rests against the curved ground at its center and edges."
				)
			_check_bounds(view)
		if stage in [0, 2, 3] and not is_zero_approx(turn):
			await _save("grounded_%d_%s" % [stage, "left" if turn < 0.0 else "right"], dimensions)
	_check(not demo._region_root.visible)


func _check_bounds(view: NestView) -> void:
	var bounds: Rect2 = view.get_hover_rect()
	_check(bounds.has_area())
	_check(view.contains_viewport_point(bounds.get_center()))
	_check(not view.contains_viewport_point(bounds.end + Vector2(12.0, 12.0)))
	var sprite: Sprite2D = view._art._sprite
	var pixels: Rect2 = Rect2(sprite.texture.get_image().get_used_rect())
	var drawn: Rect2 = sprite.get_global_transform_with_canvas() * pixels
	_check(
		bounds.is_equal_approx(drawn),
		"Hover geometry must follow visible artwork through every frame."
	)


func _check_tools(demo: DemoScript, dimensions: Vector2i) -> void:
	demo._window_has_focus = true
	var point: Vector2 = (
		demo._world.get_global_transform_with_canvas().affine_inverse()
		* (root.get_visible_rect().size * Vector2(0.55, 0.65))
	)
	demo._pipe._art.animation_player.callback_mode_process = (
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	)
	demo._drive_tool(0.0, point, false)
	_check(demo._pipe.visible and demo._pipe._art.animation_player.is_playing())
	var pipe_sprite: Sprite2D = demo._pipe._art.get_node("贴图") as Sprite2D
	var first: Texture2D = pipe_sprite.texture
	demo._pipe._art.animation_player.advance(0.3)
	_check(pipe_sprite.texture != first)
	demo._drive_tool(0.0, point, false)
	_check(is_equal_approx(demo._pipe._art.animation_player.current_animation_position, 0.3))
	var mouth_screen: Vector2 = (
		pipe_sprite.get_global_transform_with_canvas()
		* (demo._pipe.mouth_pixel - pipe_sprite.texture.get_size() * 0.5)
	)
	_check(mouth_screen.distance_to(demo._world.get_global_transform_with_canvas() * point) < 0.01)
	await _save("pipe", dimensions)
	demo._select_tool(DemoScript.ToolMode.NET)
	_check(not demo._pipe._art.animation_player.is_playing())
	demo._drive_tool(0.0, point, false)
	await _save("net_preview", dimensions)
	var candy_before: int = demo.run.candy
	var population_before: int = demo._slimes.size()
	var actor: PrototypeSlime = demo._slimes[0]
	actor.position = point - point.normalized() * actor.body_size * 0.65
	actor.rotation = actor.position.angle() + PI / 2.0
	demo._drive_tool(0.0, point, true)
	var net_sprite: Sprite2D = demo._net._art.get_node("贴图") as Sprite2D
	var textures: Array[Texture2D] = [net_sprite.texture]
	for step: float in [0.065, 0.065, 0.05, 0.001, 0.13]:
		demo._drive_tool(step, point, false)
		if not textures.has(net_sprite.texture):
			textures.append(net_sprite.texture)
		if demo._net_phase == DemoScript.NetPhase.CLOSING:
			await _save("net_%d" % textures.size(), dimensions)
	_check(textures.size() == 5, "The actual cast visits all five source frames.")
	demo._drive_tool(0.22, point, false)
	_check(demo._net_phase == DemoScript.NetPhase.RESULT)
	_check(demo.run.candy > candy_before and demo._slimes.size() < population_before)
	await _save("net_result", dimensions)
	demo._drive_tool(0.31, point, false)
	demo._drive_tool(0.0, point, false)
	_check(demo._net._presentation == CaptureNet.Presentation.COOLDOWN)
	await _save("net_cooldown", dimensions)
	demo._view.zoom_steps(-1.0)
	demo._drive_tool(0.0, point, false)
	_check(not demo._pipe.visible and not demo._net.visible)
	demo._view.zoom_steps(1.0)
	demo._select_tool(DemoScript.ToolMode.PIPE)
	demo._drive_tool(0.0, point, false)
	demo._on_window_focus_exited()
	_check(not demo._pipe._art.animation_player.is_playing())


func _check_rapid_upgrades(view: NestView) -> void:
	for level: int in range(1, 4):
		view.update_state(level, level == 3, 3)
	for level: int in range(1, 4):
		_check(
			view._art._growth.animation_player.current_animation == NestArt.TRANSITIONS[level - 1]
		)
		view._art._growth.animation_player.advance(2.0)
	_check(view._art._display_level == 3 and view._art._flower.visible)
	view.update_state(0, false, 3)
	_check(view._art._display_level == 0 and not view._art._flower.visible)


func _settle() -> void:
	for frame: int in range(4):
		await process_frame


func _save(label: String, dimensions: Vector2i) -> void:
	if not _capture:
		return
	await RenderingServer.frame_post_draw
	var path: String = (
		"res://artifacts/runtime_art_integration/%s_%dx%d.png" % [label, dimensions.x, dimensions.y]
	)
	_check(root.get_texture().get_image().save_png(path) == OK)


func _check(
	condition: bool, message: String = "Runtime art integration expectation failed."
) -> void:
	if not condition:
		_failures += 1
		push_error(message)
