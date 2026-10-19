extends Node

const PLAY = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const Drill = preload("res://scripts/drill_monster.gd")
var output: String = "res://artifacts/upgrade_feedback_%d/" % Time.get_unix_time_from_system()
var failures: int = 0
var game: Play


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _run() -> void:
	get_window().size = Vector2i(1280, 800)
	game = PLAY.instantiate()
	add_child(game)
	game.set_process(false)
	game._view.set_process(false)
	game._window_has_focus = true
	await get_tree().create_timer(0.2).timeout
	var layout: DiskDemoLayout = game._layout
	var dock = layout._tool_dock
	dock.set_process(false)
	game.run.candy = 9
	game._refresh_hud()
	check(not dock._upgrade_guide_active, "before first affordability no guide")
	game.run.candy = 10
	game._refresh_hud()
	check(dock._upgrade_guide_active, "first affordability starts both guide borders")
	await get_tree().create_timer(0.35).timeout
	var edge: float = (
		(dock.technology_button.get_node("Backing").material as ShaderMaterial)
		. get_shader_parameter("guide_amount")
	)
	check(edge > 0.5, "guide border actually tweens")
	check(
		is_equal_approx(
			edge,
			(dock.upgrades[0].get_node("Backing").material as ShaderMaterial).get_shader_parameter(
				"guide_amount"
			)
		),
		"two guide borders stay synchronized"
	)
	await capture("guide_1280")
	dock._advance_technology_notice(4.99)
	check(dock._notice_tween == null, "no notice before five seconds")
	game._refresh_hud()
	dock._advance_technology_notice(0.02)
	check(dock._notice_tween != null, "economy refresh preserves continuous affordability timer")
	await get_tree().create_timer(0.23).timeout
	check(
		(
			float((dock.badge.material as ShaderMaterial).get_shader_parameter("outline_progress"))
			> 0.0
		),
		"white contour starts drawing"
	)
	await capture("trace_1280")
	await get_tree().create_timer(0.40).timeout
	check(dock.badge.scale.x > 1.1, "notice grows after contour")
	await capture("pulse_1280")
	var loop: Tween = dock._notice_tween
	game._refresh_hud()
	check(dock._notice_tween == loop, "economy refresh does not restart loop")
	layout._show_technology()
	var frozen: Vector2 = dock.badge.scale
	await get_tree().create_timer(0.2).timeout
	check(dock.badge.scale.is_equal_approx(frozen), "notice pauses behind panel")
	layout.close_panels()
	await get_tree().process_frame
	await get_tree().process_frame
	game.run.candy = 0
	game._refresh_hud()
	check(
		dock._notice_tween == null and dock._technology_wait == 0.0,
		"losing affordability resets timer and loop"
	)
	check(
		dock.badge.scale == Vector2.ONE and not dock.badge.visible,
		"losing affordability restores badge"
	)
	game.run.candy = 10
	game._refresh_hud()
	dock._advance_technology_notice(4.9)
	check(dock._notice_tween == null, "regaining affordability waits a fresh five seconds")
	game._on_quick_upgrade(0)
	check(not dock._upgrade_guide_active, "purchase ends first guide borders")
	game.run.candy = 100
	game._refresh_hud()
	check(not dock._upgrade_guide_active, "later affordability does not repeat first guide")
	game.run.governance_level = 1
	game.run.candy = 3000
	game._refresh_hud()
	check(is_equal_approx(dock.badge.scale.x, 1.65), "automation keeps its existing larger badge")
	dock.suppress(false)
	dock._advance_technology_notice(5.1)
	await get_tree().create_timer(0.65).timeout
	check(dock.badge.scale.x > 1.65, "automation also pulses after delay")
	get_window().size = Vector2i(1920, 1080)
	game._apply_layout()
	await get_tree().create_timer(0.1).timeout
	await capture("automation_1920")
	await get_tree().create_timer(3.0).timeout
	check(
		dock._notice_tween != null and dock._notice_tween.is_running(),
		"notice continues repeating beyond first cycle"
	)
	check_nests()
	await check_moles()
	game.restart_run()
	game.set_process(false)
	game.run.candy = 10
	game._refresh_hud()
	check(
		dock._upgrade_guide_active and dock._technology_wait == 0.0,
		"restart resets guide and notice"
	)
	layout._process(layout.tool_upgrade_guide_seconds + 0.1)
	check(not dock._upgrade_guide_active, "guide expiry stops border loop")
	game.queue_free()
	await get_tree().process_frame
	print("Upgrade feedback and capture checks: %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func check_nests() -> void:
	game._window_has_focus = true
	for view: NestView in game._nest_views:
		for turn: float in [0.0, 0.65, -0.65]:
			game._world.rotation = -PI * 0.5 - view.position.angle() + turn
			view.refresh_presentation()
			var shape: Transform2D = view._selection_shape.get_global_transform_with_canvas()
			var upper: Vector2 = shape * Vector2(0, -view._selection_rect.size.y * 0.25)
			var lower: Vector2 = shape * Vector2(0, view._selection_rect.size.y * 0.25)
			check(view.blocks_vacuum_at(upper), "nest upper half blocks vacuum at rotated view")
			check(not view.blocks_vacuum_at(lower), "nest lower half allows vacuum at rotated view")
			game._update_nest_hover(lower)
			check(
				not game._is_over_selected_nest(lower),
				"selected nest lower half remains collectible"
			)
	game._world.rotation = -PI * 0.5 - game._nest_views[0].position.angle()
	var view: NestView = game._nest_views[0]
	var lower: Vector2 = (
		view._selection_shape.get_global_transform_with_canvas()
		* Vector2(0, view._selection_rect.size.y * 0.3)
	)
	game._update_nest_hover(lower)
	var target: Vector2 = game._world.get_global_transform_with_canvas().affine_inverse() * lower
	check(
		game._can_collect(target, game.run.get_pipe_radius()), "actual tool gate allows lower nest"
	)


func check_moles() -> void:
	game._clear_nest_selection()
	game._world.rotation = 0.0
	for valuable: bool in [false, true]:
		var actor: Drill = game.drill_scene.instantiate()
		game._slime_root.add_child(actor)
		actor.setup(1, Vector2.UP * game._planet.radius, game._planet)
		actor.configure_species(PrototypeSlime.Species.DRILL, valuable, 0)
		actor.presentation_scale = game._view.near_slime_scale
		actor.set_process(false)
		game._slimes.append(actor)
		for phase: int in [Drill.Phase.EXPOSED, Drill.Phase.LAUNCH]:
			if phase == Drill.Phase.EXPOSED:
				actor._enter_phase(Drill.Phase.EXPOSED, 100.0, &"夹夹")
			else:
				actor.launch(Vector2.UP)
			actor.refresh_presentation()
			var bounds: Rect2 = (
				actor._get_art_rect() if phase == Drill.Phase.LAUNCH else actor._exposed_art_rect
			)
			for factor: float in [0.05, 0.95]:
				var body: Transform2D = (
					actor.transform
					* (
						actor.art.transform
						if phase == Drill.Phase.LAUNCH
						else actor._get_base_art_transform()
					)
				)
				var edge: Vector2 = (
					body
					* Vector2(lerpf(bounds.position.x, bounds.end.x, factor), bounds.get_center().y)
				)
				check(
					actor.get_capture_distance_squared(edge) < 0.01,
					"mole full body edge is inside hitbox"
				)
				game._capture_at(0.1, edge, true)
				check(game._capture_targets.has(actor), "vacuum acquires mole body edge")
				if phase == Drill.Phase.EXPOSED and factor > 0.9:
					game._pipe.show()
					game._pipe.set_tool_state(edge, edge, true)
					await capture("mole_edge_%s" % valuable)
				game._capture_at(0.0, edge, false)
			var body: Transform2D = (
				actor.transform
				* (
					actor.art.transform
					if phase == Drill.Phase.LAUNCH
					else actor._get_base_art_transform()
				)
			)
			var outside: Vector2 = body * Vector2(bounds.end.x + 1000.0, bounds.get_center().y)
			check(
				actor.get_capture_distance_squared(outside) > pow(game.run.get_pipe_radius(), 2),
				"far outside mole remains uncollectible"
			)
		game._slimes.erase(actor)
		actor.queue_free()


func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	DirAccess.make_dir_recursive_absolute(output)
	await RenderingServer.frame_post_draw
	check(
		get_viewport().get_texture().get_image().save_png(output + label + ".png") == OK,
		"fresh visual capture " + label
	)
