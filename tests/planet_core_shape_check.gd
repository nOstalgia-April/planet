extends Node

const Core = preload("res://scripts/planet_core_animation.gd")
const CoreScene: PackedScene = preload("res://scenes/场景动画/星球核心.tscn")
const OUTPUT_ROOT: String = "res://artifacts/core_crisp_20261016/validation/shape"

var _views: Array[SubViewport] = []
var _cores: Array[Core] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(OUTPUT_ROOT) == OK)
	for index: int in range(2):
		var viewport: SubViewport = SubViewport.new()
		viewport.size = Vector2i(356, 300)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		_views.append(viewport)
		var core: Core = CoreScene.instantiate() as Core
		core.autoplay = true
		core.synchronize_music = false
		viewport.add_child(core)
		core.position = core.clip.pivot
		core.set_process(false)
		if index == 0:
			# Render the actual old imported frame, bypassing the new material.
			core.sprite.material = null
		_cores.append(core)
	var sample_frames: Array[int] = [0, 50, 51, 58, 63, 64, 2400, 2927]
	for frame: int in sample_frames:
		await _seek(frame)
		var before: Image = _views[0].get_texture().get_image()
		var after: Image = _views[1].get_texture().get_image()
		_check_inner_disk(after, frame)
		_check_outer_extent(before, after, frame)
		assert(before.save_png(OUTPUT_ROOT.path_join("before_%04d.png" % frame)) == OK)
		assert(after.save_png(OUTPUT_ROOT.path_join("after_%04d.png" % frame)) == OK)
	if "--animation" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(OUTPUT_ROOT.path_join("motion"))
		for frame: int in range(30, 120):
			await _seek(frame)
			var comparison: Image = Image.create(712, 300, false, Image.FORMAT_RGBA8)
			for index: int in range(2):
				var image: Image = _views[index].get_texture().get_image()
				image.convert(Image.FORMAT_RGBA8)
				comparison.blit_rect(image, Rect2i(0, 0, 356, 300), Vector2i(index * 356, 0))
			assert(comparison.save_png(OUTPUT_ROOT.path_join("motion/%03d.png" % frame)) == OK)
	for viewport: SubViewport in _views:
		viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print(
		"PASS: fixed opaque core, half-strength outer radii, multiple frames and atlas boundaries."
	)
	get_tree().quit()


func _seek(frame: int) -> void:
	for core: Core in _cores:
		var deadline: int = Time.get_ticks_msec() + 5000
		while true:
			core._poll_pages()
			core.seek_seconds((float(frame) + 0.01) / core.frames_per_second)
			if core.current_frame == frame:
				break
			assert(Time.get_ticks_msec() < deadline, "Shape preview atlas load timed out.")
			await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _check_inner_disk(image: Image, frame: int) -> void:
	# Pigment may flow, but every pixel safely inside the fixed disk stays opaque.
	# Checking the full interior catches shrinkage beyond the old 60x60 center crop.
	for y: int in range(107, 223):
		for x: int in range(120, 236):
			var offset: Vector2 = Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(178.0, 164.5)
			if offset.length() <= 56.5:
				assert(
					image.get_pixel(x, y).a >= 0.99,
					"Core alpha must remain opaque: frame=%d pixel=(%d,%d)" % [frame, x, y]
				)


func _check_outer_extent(before: Image, after: Image, frame: int) -> void:
	# Measure real rendered silhouettes along 16 rays, independently of the shader.
	for ray: int in range(16):
		var direction: Vector2 = Vector2.from_angle(float(ray) * TAU / 16.0)
		var original: float = _radius(before, direction)
		var reduced: float = _radius(after, direction)
		var expected: float = 57.5 + maxf(original - 57.5, 0.0) * 0.5
		assert(
			absf(reduced - expected) <= 2.0,
			(
				"Outer radius must halve its excess: frame=%d ray=%d before=%.1f after=%.1f expected=%.1f"
				% [frame, ray, original, reduced, expected]
			)
		)


func _radius(image: Image, direction: Vector2) -> float:
	var last_opaque: float = 0.0
	for step: int in range(360):
		var radius: float = float(step) * 0.5
		var point: Vector2i = Vector2i(Vector2(178.0, 164.5) + direction * radius)
		if (
			point.x < 0
			or point.y < 0
			or point.x >= image.get_width()
			or point.y >= image.get_height()
		):
			break
		if image.get_pixelv(point).a >= 0.5:
			last_opaque = radius
	return last_opaque
