extends SceneTree

const OverviewScript = preload("res://scripts/overview_ecology.gd")
const OverviewScene: PackedScene = preload("res://scenes/world/overview_ecology.tscn")
const PlanetScene: PackedScene = preload("res://scenes/world/planet_surface.tscn")

var _failures: int = 0


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var container: Node2D = Node2D.new()
	root.add_child(container)
	current_scene = container
	var world: Node2D = Node2D.new()
	container.add_child(world)
	var surface: PlanetSurface = PlanetScene.instantiate() as PlanetSurface
	world.add_child(surface)
	var overview: OverviewScript = OverviewScene.instantiate() as OverviewScript
	container.add_child(overview)
	overview.configure(surface, world)
	await process_frame
	await process_frame
	var viewport_size: Vector2 = root.get_visible_rect().size
	world.position = viewport_size * 0.5
	world.scale = (
		Vector2.ONE * viewport_size.y * 0.31 / (surface.radius * PlanetSurface.SURFACE_RADIUS_RATIO)
	)
	_check_surface_statistics(overview, surface)
	overview.update_ecology(48, 14, true, viewport_size)
	overview.set_process(false)
	overview._process(2.0)
	_check(
		overview.bubble_radii.x > overview.bubble_radii.y,
		"more slimes produce a larger slime bubble"
	)
	_check(
		overview._target_color.r > overview._target_color.b,
		"slime majority produces a pink backdrop target"
	)
	_check(
		overview.population_counts == Vector2i(48, 14),
		"bubble labels use the actual supplied populations"
	)
	_check(
		overview._planet_center.distance_to(viewport_size * 0.5) < 0.01,
		"overlay geometry follows the world center"
	)
	await _capture("overview_module_pink.png")
	overview.update_ecology(8, 52, true, viewport_size)
	overview.set_process(false)
	overview._process(2.0)
	_check(
		overview.bubble_radii.y > overview.bubble_radii.x,
		"more mucus monsters produce a larger mucus bubble"
	)
	_check(
		overview._target_color.b > overview._target_color.r,
		"mucus majority produces a blue backdrop target"
	)
	await _capture("overview_module_blue.png")
	overview.update_ecology(20, 20, true, viewport_size)
	overview.set_process(false)
	overview._process(2.0)
	_check(
		overview._target_color.is_equal_approx(overview.neutral_color),
		"ties retain a neutral blend without selecting a false winner"
	)
	_check(
		absf(overview.bubble_radii.x - overview.bubble_radii.y) < 0.1,
		"equal populations have equal-sized bubbles"
	)
	overview.update_ecology(0, 0, true, viewport_size)
	overview.set_process(false)
	overview._process(2.0)
	_check(
		overview._target_radii == Vector2.ZERO and overview._target_activity == 0.0,
		"empty ecology removes bubbles and uses the quiet backdrop"
	)
	await _capture("overview_module_neutral.png")
	overview.update_ecology(20, 4, false, viewport_size)
	_check(
		not overview.visible and not overview._backdrop_layer.visible,
		"near view hides both bubble overlay and separate backdrop layer"
	)
	current_scene = null
	container.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: proportional surface arcs, depth-independent statistics, actual-count bubbles and near-view isolation"
		)
	quit(0 if _failures == 0 else 1)


func _check_surface_statistics(overview: OverviewScript, surface: PlanetSurface) -> void:
	_check(
		(
			overview._surface_sector_for_position(Vector2.from_angle(-PI * 0.5 - 0.00001)) == 15
			and overview._surface_sector_for_position(Vector2.from_angle(-PI * 0.5 + 0.00001)) == 0
		),
		"the top seam wraps between sectors 15 and 0"
	)
	var nests: Array[NestState] = []
	for sector: int in range(OverviewScript.SURFACE_SECTORS):
		var angle: float = (
			-PI * 0.5 + (float(sector) + 0.5) * TAU / float(OverviewScript.SURFACE_SECTORS)
		)
		for index: int in range(4):
			var nest: NestState = NestState.new()
			nest.species = NestState.Species.SLIME if index == 0 else NestState.Species.MUCUS
			nest.position = Vector2.from_angle(angle) * (110.0 + float(index) * 38.0)
			nests.append(nest)
	overview.update_nest_clusters(nests)
	var totals: Vector2i = Vector2i.ZERO
	for sector: int in range(OverviewScript.SURFACE_SECTORS):
		_check(
			overview._surface_counts[sector] == Vector2i(1, 3),
			"each nest contributes once regardless of depth"
		)
		totals += overview._surface_counts[sector]
		var slime: PackedVector2Array = overview._surface_band_polygon(sector, 0)
		var mucus: PackedVector2Array = overview._surface_band_polygon(sector, 1)
		var slime_span: float = absf(slime[0].angle_to(slime[12]))
		var mucus_span: float = absf(mucus[0].angle_to(mucus[12]))
		_check(
			is_equal_approx(mucus_span, slime_span * 3.0),
			"mixed species occupy adjacent arcs in count proportion"
		)
		_check(
			slime[12].is_equal_approx(mucus[0]), "mixed species meet without overlap or a false gap"
		)
		for band: PackedVector2Array in [slime, mucus]:
			for point: Vector2 in band:
				var depth: float = surface.get_outer_radius(point.angle()) - point.length()
				_check(
					depth >= 1.49 and depth <= overview.surface_band_width + 1.51,
					"summary color remains a narrow surface band"
				)
	_check(totals == Vector2i(16, 48), "all sectors preserve species nest totals")
	var bands: Array[PackedVector2Array] = overview._surface_bands.duplicate()
	for nest: NestState in nests:
		nest.position = nest.position.normalized() * 170.0
	overview.update_nest_clusters(nests)
	_check(
		overview._surface_bands == bands, "changing crust depth cannot change the surface summary"
	)
	_check(
		overview._surface_counts[0] == Vector2i(1, 3), "repeated updates do not accumulate counts"
	)
	for nest: NestState in nests:
		_check(
			nest.level == 0 and not nest.is_tamed, "summary updates preserve actual nest governance"
		)


func _capture(filename: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	_check(
		root.get_texture().get_image().save_png("res://artifacts/" + filename) == OK,
		"saved " + filename
	)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
