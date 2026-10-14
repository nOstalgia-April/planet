extends Node

const Area = preload("res://scripts/nest_mucus_area.gd")
const AREA_SCENE: PackedScene = preload("res://scenes/effects/nest_mucus_area.tscn")
const Demo = preload("res://scripts/disk_demo.gd")
const PLAY_SCENE: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const OUTPUT: String = "res://artifacts/nest_mucus_contact_20261014"

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var surface: PlanetSurface = PlanetSurface.new()
	get_tree().root.add_child(surface)
	var area: Area = AREA_SCENE.instantiate() as Area
	get_tree().root.add_child(area)
	var seen: Array[int] = []
	for trial: int in range(90):
		area.configure(surface, Vector2.UP * surface.get_outer_radius(-PI / 2.0), 1, 44.8)
		if not seen.has(area.variant_index):
			seen.append(area.variant_index)
	_check(seen.size() == 3, "random generation reaches all three variants")
	for variant: int in range(3):
		for angle: float in [-PI / 2.0, 0.0, 2.0]:
			area.configure(
				surface,
				Vector2.from_angle(angle) * surface.get_outer_radius(angle),
				1,
				44.8,
				variant
			)
			area.set_process(false)
			var count: int = Area.FRAMES.get_frame_count(area._animation())
			for frame: int in range(count):
				area._process(area.frame_seconds if frame > 0 else 0.0)
				_check_frame(area, surface)
			_check(not area.is_processing(), "growth stops at the last supplied frame")
			var texture: Texture2D = area._outline.texture
			area._process(50.0)
			_check(area._outline.texture == texture, "the pool retains its final shape")
	area.queue_free()
	surface.queue_free()
	await get_tree().process_frame
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(OUTPUT)
		await _check_rendered_masks()
		await _capture_formal_scene()
	print("Nest mucus variants: %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_frame(area: Area, surface: PlanetSurface) -> void:
	var image: Image = area._outline.texture.get_image()
	var visible_points: int = 0
	var clear_points: int = 0
	for y: int in range(2, image.get_height(), 17):
		for x: int in range(2, image.get_width(), 17):
			var point: Vector2 = area._source_to_ground * Vector2(x + 0.5, y + 0.5)
			var crust: bool = (
				Geometry2D.is_point_in_polygon(point, surface.get_surface_polygon())
				and not Geometry2D.is_point_in_polygon(point, surface.get_inner_polygon())
			)
			var expected: bool = image.get_pixel(x, y).a > Area.ALPHA_THRESHOLD and crust
			_check(
				area.contains_ground_point(point) == expected,
				"frame alpha and clipped contact match"
			)
			if expected:
				visible_points += 1
			else:
				clear_points += 1
	_check(
		visible_points > 0 and clear_points > 0,
		"each frame covers paint and rejects transparent gaps"
	)
	for index: int in range(area._outline.polygon.size()):
		_check(
			(
				(area._source_to_ground * area._outline.uv[index]).distance_to(
					area._outline.polygon[index]
				)
				< 0.001
			),
			"rendered UVs use the same transform as contact"
		)
	_check_shore_contact(area, surface)


func _check_shore_contact(area: Area, surface: PlanetSurface) -> void:
	var inward: Vector2 = -area.home_position.normalized()
	var tangent: Vector2 = Vector2(inward.y, -inward.x)
	var contour: PackedVector2Array = surface.get_surface_polygon()
	var ratios: Array[float] = [-0.3, -0.15, 0.0, 0.15, 0.3]
	if area._frame_index == Area.FRAMES.get_frame_count(area._animation()) - 1:
		ratios.append_array([-0.55, 0.55])
	for ratio: float in ratios:
		var x: float = area.coverage_radius * ratio
		var top: float = INF
		for index: int in range(contour.size()):
			var start: Vector2 = contour[index] - area.home_position
			var finish: Vector2 = contour[(index + 1) % contour.size()] - area.home_position
			var first_x: float = start.dot(tangent)
			var last_x: float = finish.dot(tangent)
			if is_equal_approx(first_x, last_x):
				continue
			var weight: float = (x - first_x) / (last_x - first_x)
			if weight >= 0.0 and weight <= 1.0:
				top = minf(top, start.lerp(finish, weight).dot(inward))
		var point: Vector2 = area.home_position + tangent * x + inward * (top + 0.25)
		_check(
			area.contains_ground_point(point),
			(
				"shore contact: variant=%d frame=%d angle=%.2f x=%.2f top=%.2f"
				% [area.variant_index, area._frame_index, area.home_position.angle(), x, top]
			)
		)


func _check_rendered_masks() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(420, 260)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	var area: Area = AREA_SCENE.instantiate() as Area
	viewport.add_child(area)
	area.position = Vector2(210.0, 70.0)
	area.scale = Vector2.ONE * 3.0
	for variant: int in range(3):
		area.variant_index = variant
		area.set_process(false)
		for frame: int in range(Area.FRAMES.get_frame_count(area._animation())):
			area._process(area.frame_seconds if frame > 0 else 0.0)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var rendered: Image = viewport.get_texture().get_image()
			for y: int in range(3, 258, 5):
				for x: int in range(3, 418, 5):
					var local: Vector2 = (Vector2(x + 0.5, y + 0.5) - area.position) / area.scale
					_check(
						(rendered.get_pixel(x, y).a > 0.01) == area.contains_ground_point(local),
						"GPU paint and contact agree at pixel centers"
					)
			if frame == Area.FRAMES.get_frame_count(area._animation()) - 1:
				_check(
					rendered.save_png(OUTPUT + "/variant_%d_mask.png" % (variant + 1)) == OK,
					"mask capture"
				)
	viewport.queue_free()
	await get_tree().process_frame


func _capture_formal_scene() -> void:
	var demo: Demo = PLAY_SCENE.instantiate() as Demo
	get_tree().root.add_child(demo)
	get_tree().current_scene = demo
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	demo.run._pending_nest_species = NestState.Species.MUCUS
	var angle: float = -PI / 2.0
	demo.run.resolve_nest_spawn(Vector2.from_angle(angle) * demo._planet.get_outer_radius(angle))
	var nest: NestState = demo.run.get_nest(3)
	var difference: float = angle_difference(
		demo._world.rotation, -PI / 2.0 - nest.position.angle()
	)
	var screen_radius: float = (
		demo._planet.radius * demo._world.scale.x * demo._view.projection_root.scale.x
	)
	demo._view.begin_drag(Vector2.ZERO)
	demo._view.drag_to(Vector2(difference * screen_radius, 0.0))
	demo._view.end_drag()
	var area: Area = demo._nest_mucus_areas[0]
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_tree().root.size = size
		for variant: int in range(3):
			area.variant_index = variant
			area._process(2.0)
			for frame: int in range(5):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path: String = OUTPUT + "/formal_%d_%dx%d.png" % [variant + 1, size.x, size.y]
			_check(
				get_tree().root.get_texture().get_image().save_png(path) == OK,
				"formal scene capture"
			)
	get_tree().current_scene = null
	demo.queue_free()
	await get_tree().process_frame


func _check(passed: bool, message: String) -> void:
	if not passed:
		_failures += 1
		if _failures < 12:
			push_error(message)
