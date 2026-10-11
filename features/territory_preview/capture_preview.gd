extends SceneTree

const PreviewScene: PackedScene = preload(
	"res://features/territory_preview/flower_claim_preview.tscn"
)
const PreviewScript = preload("res://features/territory_preview/flower_claim_preview.gd")
const ClaimedCrust = preload("res://scripts/claimed_crust.gd")
const FlowField = preload("res://scripts/paint_flow_field.gd")
const OUTPUT: String = "res://artifacts/territory_color/flat_flow"
const CAPTURE_SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 800)]
const CAPTURE_PROGRESS: Array[float] = [0.0, 0.24, 0.5, 0.65, 0.84, 0.94, 1.0]


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.mode = Window.MODE_WINDOWED
	var preview: PreviewScript = PreviewScene.instantiate() as PreviewScript
	preview.autoplay = false
	root.add_child(preview)
	current_scene = preview
	assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK)
	var crust: ClaimedCrust = preview.get_node("Canvas/染色地壳") as ClaimedCrust
	_check_field(crust.flow_image)
	_check_drip_sequence(preview, crust)
	if "--overwrite-only" in OS.get_cmdline_user_args():
		await _check_overwrite(preview, crust)
		quit()
		return
	for viewport_size in CAPTURE_SIZES:
		root.size = viewport_size
		for _frame in range(4):
			await process_frame
		preview.set_controls_visible(false)
		for progress in CAPTURE_PROGRESS:
			preview.set_claim_progress(progress)
			await _save(
				"overlap_%dx%d_%03d.png" % [viewport_size.x, viewport_size.y, int(progress * 100)]
			)
		preview.set_controls_visible(true)
		await _save("controls_%dx%d.png" % [viewport_size.x, viewport_size.y])
		if "--quick" in OS.get_cmdline_user_args():
			print("PASS: quick rendered sequence and two-channel flow map.")
			quit()
			return
	preview.set_controls_visible(false)
	preview.set_preview_mode(1)
	assert(is_zero_approx(crust.mucus_progress))
	await _save("pink_only.png")
	preview.set_preview_mode(2)
	assert(is_zero_approx(crust.claim_progress))
	await _save("blue_only.png")
	preview.set_preview_mode(0)
	preview.swap_coverage()
	preview.set_claim_progress(1.0)
	assert(not crust.mucus_on_top)
	await _save("pink_covers_blue.png")
	preview.swap_coverage()
	preview.set_claim_progress(1.0)
	assert(crust.mucus_on_top)
	var original_field: PackedByteArray = crust.flow_image.get_data()
	preview.set_patch_sizes(0.55, 1.35)
	await process_frame
	preview.set_claim_progress(1.0)
	assert(original_field != crust.flow_image.get_data())
	await _save("small_pink_large_blue.png")
	preview.set_patch_sizes(1.35, 0.55)
	await process_frame
	await _save("large_pink_small_blue.png")
	preview.randomize_patches()
	await process_frame
	preview.set_claim_progress(1.0)
	assert(crust.shape_seed == 49)
	await _save("random_seed49.png")
	crust.shape_seed = 12
	preview.set_patch_sizes(0.82, 0.94)
	await process_frame
	preview.replay_claim()
	await create_timer(1.8).timeout
	assert(crust.claim_progress > 0.0 and crust.claim_progress < 1.0)
	assert(crust.mucus_progress > 0.0 and crust.mucus_progress < crust.claim_progress)
	preview.set_claim_progress(0.0)
	await create_timer(0.15).timeout
	assert(is_zero_approx(crust.claim_progress) and is_zero_approx(crust.mucus_progress))
	preview.replay_claim()
	await create_timer(preview.spread_seconds + 0.2).timeout
	assert(
		is_equal_approx(crust.claim_progress, 1.0) and is_equal_approx(crust.mucus_progress, 1.0)
	)
	if "--animation" in OS.get_cmdline_user_args():
		await _capture_animation(preview)
	preview.set_controls_visible(true)
	var menu_button: Button = preview.get_node("Canvas/Controls/Panel/Rows/Buttons/Menu") as Button
	menu_button.pressed.emit()
	for _frame in range(5):
		await process_frame
	var menu: Control = current_scene as Control
	var previews_button: Button = menu.get_node("画布/预览") as Button
	previews_button.pressed.emit()
	await process_frame
	var claim_button: Button = menu.get_node("画布/预览选择/列表/花朵地块染色") as Button
	assert(claim_button.get_global_rect().end.y <= root.get_visible_rect().size.y)
	claim_button.pressed.emit()
	for _frame in range(5):
		await process_frame
	assert(current_scene is PreviewScript)
	print(
		"PASS: two sizes, two flowers, overlap, separate modes, unequal sizes, new seed, replay and menu."
	)
	quit()


func _check_field(field: Image) -> void:
	var overlap: int = 0
	var pink_only: int = 0
	var blue_only: int = 0
	for y in range(field.get_height()):
		for x in range(field.get_width()):
			var value: Color = field.get_pixel(x, y)
			if value.b < 0.0 and value.a < 0.0:
				overlap += 1
			elif value.b < 0.0:
				pink_only += 1
			elif value.a < 0.0:
				blue_only += 1
	assert(overlap > 100 and pink_only > 100 and blue_only > 100, "缺少真实交叠区或单色区。")
	print("Flow cells: overlap=%d, pink=%d, blue=%d" % [overlap, pink_only, blue_only])


func _check_drip_sequence(preview: PreviewScript, crust: ClaimedCrust) -> void:
	preview.set_claim_progress(0.0)
	var flower: Node2D = preview.get_node("Canvas/花") as Node2D
	assert(not flower.visible and crust.drip_progress == Vector2.ZERO)
	preview.set_claim_progress(0.065)
	assert(flower.visible and crust.claim_progress > 0.0)
	preview.set_claim_progress(0.65)
	assert(
		is_equal_approx(crust.claim_progress, 1.0) and is_equal_approx(crust.mucus_progress, 1.0)
	)
	assert(crust.drip_progress == Vector2.ZERO, "蔓延刚结束时不应滴落。")
	preview.set_claim_progress(0.84)
	assert(crust.drip_progress.x > 0.0 and crust.drip_progress.y > 0.0)
	assert(crust.pink_drips[0].z > 0.0 and crust.blue_drips[0].z > 0.0)
	print("Drip outlets: pink=%s blue=%s" % [crust.pink_drips, crust.blue_drips])
	preview.set_claim_progress(1.0)


func _capture_animation(preview: PreviewScript) -> void:
	root.size = Vector2i(960, 540)
	preview.set_controls_visible(false)
	assert(DirAccess.make_dir_recursive_absolute(OUTPUT.path_join("frames")) == OK)
	for _frame in range(5):
		await process_frame
	for index in range(126):
		preview.set_claim_progress(float(index) / 125.0)
		await _save("frames/frame_%03d.png" % index)
	root.size = Vector2i(1280, 800)
	for _frame in range(5):
		await process_frame


func _check_overwrite(preview: PreviewScript, crust: ClaimedCrust) -> void:
	root.size = Vector2i(1280, 800)
	crust.animation_player.pause()
	preview.set_controls_visible(false)
	preview.set_claim_progress(1.0)
	var blue_over_pink: Image = await _save("verified_blue_over_pink.png")
	preview.set_preview_mode(2)
	var blue_only: Image = await _save("verified_blue_only.png")
	preview.set_preview_mode(1)
	var pink_only: Image = await _save("verified_pink_only.png")
	preview.set_preview_mode(0)
	preview.swap_coverage()
	preview.set_claim_progress(1.0)
	var pink_over_blue: Image = await _save("verified_pink_over_blue.png")
	var canvas: Node2D = preview.get_node("Canvas") as Node2D
	var screenshot_scale: Vector2 = (
		Vector2(pink_over_blue.get_size()) / root.get_visible_rect().size
	)
	var checked: int = 0
	for y in range(2, FlowField.GRID.y - 2, 3):
		for x in range(2, FlowField.GRID.x - 2, 3):
			var inside_both: bool = true
			for offset in FlowField.NEIGHBORS:
				var arrival: Color = crust.flow_image.get_pixelv(Vector2i(x, y) + offset * 2)
				inside_both = inside_both and arrival.b < -0.005 and arrival.a < -0.005
			var ground: Vector2 = (
				FlowField.BOUNDS.position
				+ (
					(Vector2(x, y) + Vector2.ONE * 0.5)
					/ Vector2(FlowField.GRID)
					* FlowField.BOUNDS.size
				)
			)
			if not inside_both or ground.y < 0.1 or ground.y > 0.3:
				continue
			var pixel: Vector2i = Vector2i(
				(
					canvas.to_global(
						(
							PreviewScript.PLANET_CENTER
							+ Vector2(ground.x, ground.y - 1.0) * PreviewScript.PLANET_RADIUS
						)
					)
					* screenshot_scale
				)
			)
			assert(
				blue_over_pink.get_pixelv(pixel).is_equal_approx(blue_only.get_pixelv(pixel)),
				"蓝色覆盖后仍受粉色影响。"
			)
			assert(
				pink_over_blue.get_pixelv(pixel).is_equal_approx(pink_only.get_pixelv(pixel)),
				(
					"粉色覆盖采样 %s：%s / %s"
					% [pixel, pink_over_blue.get_pixelv(pixel), pink_only.get_pixelv(pixel)]
				)
			)
			checked += 1
	assert(checked > 50, "可见交叠采样不足。")
	print("PASS: %d interior pixels exactly match the top color alone, in both orders." % checked)


func _save(filename: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	assert(frame.save_png(OUTPUT.path_join(filename)) == OK)
	return frame
