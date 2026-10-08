extends SceneTree

const PreviewScene: PackedScene = preload("res://features/splash_preview/splash_preview.tscn")
const PreviewScript = preload("res://features/splash_preview/splash_preview.gd")
const ElasticScene: PackedScene = preload("res://features/splash_preview/effects/elastic_splash.tscn")
const SplashEffect = preload("res://features/splash_preview/effects/splash_effect_base.gd")

const OUTPUT_DIRECTORY: String = "res://artifacts/splash_preview"
const FRAME_RATE: float = 30.0
const ANIMATION_FRAMES: int = 48
const HOLD_FRAMES: int = 9


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.mode = Window.MODE_WINDOWED
	await _extract_original()
	var preview: PreviewScript = PreviewScene.instantiate() as PreviewScript
	root.add_child(preview)
	current_scene = preview
	await process_frame
	preview.set_process(false)
	var create_result: Error = DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY)
	assert(create_result == OK)
	for viewport_size: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = viewport_size
		for _frame: int in range(5):
			await process_frame
		for seconds: float in [0.14, 0.3, 0.55, 1.15]:
			preview.set_preview_time(seconds)
			await process_frame
			await RenderingServer.frame_post_draw
			var frame: Image = root.get_texture().get_image()
			var output_path: String = "%s/compare_%dx%d_%03dms.png" % [
				OUTPUT_DIRECTORY, viewport_size.x, viewport_size.y, int(seconds * 1000.0)
			]
			var save_result: Error = frame.save_png(output_path)
			assert(save_result == OK)
	root.size = Vector2i(1280, 800)
	for _frame: int in range(5):
		await process_frame
	preview.set_preview_tint(Color("087aff"))
	preview.set_preview_intensity(2.0)
	preview.set_preview_time(0.3)
	await _save_window("%s/compare_blue_intensity2_1280x800.png" % OUTPUT_DIRECTORY)
	preview.set_preview_time(0.55)
	await _save_window("%s/compare_blue_intensity2_1280x800_550ms.png" % OUTPUT_DIRECTORY)
	preview.set_preview_tint(Color("ff0060"))
	preview.set_preview_intensity(1.0)
	await _capture_frames(preview)
	print("PASS: original silhouette, two-size comparisons, blue intensity 2 and 57 frames captured")
	quit()


func _extract_original() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(66, 64)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var effect: SplashEffect = ElasticScene.instantiate() as SplashEffect
	effect.display_size = 45.0
	effect.position = Vector2(33.0, 32.0)
	viewport.add_child(effect)
	effect.set_intensity(0.0)
	effect.seek(effect.duration)
	for _frame: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var silhouette: Image = viewport.get_texture().get_image()
	var result: Error = silhouette.save_png("res://assets/splash_preview/central_splash_original.png")
	assert(result == OK)
	viewport.queue_free()
	await process_frame


func _capture_frames(preview: PreviewScript) -> void:
	var frame_directory: String = "%s/frames" % OUTPUT_DIRECTORY
	var create_result: Error = DirAccess.make_dir_recursive_absolute(frame_directory)
	assert(create_result == OK)
	for index: int in range(ANIMATION_FRAMES + HOLD_FRAMES):
		var seconds: float = float(index) / FRAME_RATE if index < ANIMATION_FRAMES else 1.6
		preview.set_preview_time(seconds)
		await _save_window("%s/frame_%03d.png" % [frame_directory, index])


func _save_window(output_path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	var result: Error = frame.save_png(output_path)
	assert(result == OK)
