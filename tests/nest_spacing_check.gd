extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const ItemArt = preload("res://scripts/物品动画/动画物件.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	root.mode = Window.MODE_WINDOWED
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		var demo: DemoScript = DemoScene.instantiate() as DemoScript
		root.add_child(demo)
		current_scene = demo
		demo.set_process(false)
		demo._view.set_process(false)
		demo._layout.set_process(false)
		for _frame: int in range(8):
			await process_frame
		_check(
			is_equal_approx(demo._nest_site_distance, 146.4),
			"Growth, income and spawn frames reserve the 316-unit footprint at 40% scale plus 20 units."
		)
		_check(
			demo._nest_site_angles.size() == 10,
			"The current planet fits ten sites including the expanded spawn gesture."
		)
		for seed_index: int in range(12):
			demo.restart_run()
			demo._site_random.seed = 5300 + seed_index
			for attempt: int in range(16):
				var species: NestState.Species = (attempt % 2) as NestState.Species
				demo.run._pending_nest_species = species
				demo._on_nest_spawn_requested(species)
			_check(demo.run.nests.size() == 10, "Random placement fills each available site once.")
			for first: NestState in demo.run.nests:
				_check(
					(
						first.position.distance_to(
							demo._planet.get_nest_position(first.position.angle())
						)
						< 0.001
					),
					"Every nest remains on the outer contour."
				)
				for second: NestState in demo.run.nests:
					if first.nest_id < second.nest_id:
						_check(
							first.position.distance_to(second.position) >= 146.4,
							"Opening and random nests reserve their full growth footprint."
						)
			_check_visible_bounds(demo)
		var count: int = demo.run.nests.size()
		demo.run._nest_spawn_cooldown_remaining = 0.0
		demo.run._pending_nest_species = NestState.Species.MUCUS
		demo._on_nest_spawn_requested(NestState.Species.MUCUS)
		_check(
			demo.run.nests.size() == count and demo.run._pending_nest_species == -1,
			"A full perimeter declines discovery without adding a nest."
		)
		_check(
			demo.run._nest_spawn_cooldown_remaining == 0.0,
			"A failed placement does not start the success cooldown."
		)
		# Automation shrinks the art but must retain the reserved site.
		demo.run.nests[0].is_tamed = true
		demo.run._pending_nest_species = NestState.Species.SLIME
		demo._on_nest_spawn_requested(NestState.Species.SLIME)
		_check(demo.run.nests.size() == count, "Automated nests still own their full-size site.")
		if "--capture" in OS.get_cmdline_user_args():
			demo._world.rotation = 0.0
			for view: NestView in demo._nest_views:
				view._art.set_stage(2, false)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				"res://artifacts/nest_spacing_%dx%d.png" % [resolution.x, resolution.y]
			)
		demo.restart_run()
		_check(
			demo.run.nests.size() == 2,
			"Restart clears occupied sites and restores the opening pair."
		)
		for audio: Node in demo.get_node("Audio").get_children():
			if audio is AudioStreamPlayer:
				audio.stop()
		current_scene = null
		demo.queue_free()
		await process_frame
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print(
			"PASS: measured full-growth spacing, randomized sites, full perimeter, cooldown, automation, reset and two-resolution rotated art bounds"
		)
	quit(0 if _failures.is_empty() else 1)


func _check_visible_bounds(demo: DemoScript) -> void:
	for heading: int in range(8):
		demo._world.rotation = float(heading) * TAU / 8.0
		for stage: int in range(4):
			for view: NestView in demo._nest_views:
				view._art.set_stage(stage, false)
			_check_no_overlap(demo)
		# Include every frame of the widest upgrade, including its overshoot.
		for frame: int in range(12):
			for view: NestView in demo._nest_views:
				view._art.set_stage(2, false)
				var growth: ItemArt = view._art._growth
				growth.show_frame(&"3-4", mini(frame, growth.get_frame_count(&"3-4") - 1))
				view._art._refresh_bounds()
			_check_no_overlap(demo)
		for stage: int in range(3):
			for view: NestView in demo._nest_views:
				view._art.set_stage(stage, false)
				view.pulse_spawn()
			for frame: int in range(7):
				for view: NestView in demo._nest_views:
					view._art._spawn.show_frame(view._art.SPAWN_CLIPS[stage], frame)
					view._art._refresh_bounds()
				_check_no_overlap(demo)


func _check_no_overlap(demo: DemoScript) -> void:
	var polygons: Array[PackedVector2Array] = []
	for view: NestView in demo._nest_views:
		var half_size: Vector2 = view._art_rect.size * 0.5
		var projection: Transform2D = view._selection_shape.get_global_transform_with_canvas()
		polygons.append(
			(
				projection
				* PackedVector2Array(
					[
						-half_size,
						Vector2(half_size.x, -half_size.y),
						half_size,
						Vector2(-half_size.x, half_size.y)
					]
				)
			)
		)
	for first: int in range(polygons.size()):
		for second: int in range(first + 1, polygons.size()):
			_check(
				Geometry2D.intersect_polygons(polygons[first], polygons[second]).is_empty(),
				"Settled stages, upgrades and spawn frames do not overlap at any sampled heading."
			)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
