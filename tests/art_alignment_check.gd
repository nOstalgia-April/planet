extends Node

const Preview = preload("res://features/art_alignment_preview/art_alignment_preview.gd")
const PreviewScene: PackedScene = preload("res://features/art_alignment_preview/art_alignment_preview.tscn")
const DrillView = preload("res://scripts/drill_monster.gd")
const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const SourceDrillNest: PackedScene = preload("res://scenes/物品动画/地鼠巢穴1-2-3-4.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().root.mode = Window.MODE_WINDOWED
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		var preview: Preview = PreviewScene.instantiate() as Preview
		get_tree().root.add_child(preview)
		await _settle()
		_check_source_sizes(preview)
		_check(preview._target.item_count == 18, "all groups, twelve nests and three monsters are selectable")
		_check(Rect2(Vector2.ZERO, get_tree().root.get_visible_rect().size).encloses(preview._panel.get_global_rect()), "controls fit viewport")
		preview._toggle_menu()
		await _settle()
		await _capture("collapsed_%dx%d" % [resolution.x, resolution.y])
		preview._toggle_menu()
		var clearance: Rect2 = preview._layout.get_tool_clearance_rect()
		var projection: Transform2D = preview._world.get_global_transform_with_canvas()
		for corner: Vector2 in [clearance.position, clearance.end, Vector2(clearance.position.x, clearance.end.y), Vector2(clearance.end.x, clearance.position.y)]:
			_check(not preview._planet.contains_surface_point(projection.affine_inverse() * corner), "toolbar plus clearance is entirely inside hole")
		_check(preview._planet.inner_radius_ratio > 0.6, "near hole expands beyond original radius")
		for species: int in range(3):
			var monster: PrototypeSlime = preview._slimes[species]
			for sample: int in range(200):
				monster.refresh_surface_bounds()
				monster._move_on_surface(monster._random_destination(), 10.0)
				_check(preview._planet.contains_surface_point(monster.position, preview._planet.activity_edge_inset), "all species stay in annular crust")
		for target: int in range(18):
			preview._target.select(target)
			preview._select_target(target)
			preview._edit_scale(1.15)
			preview._edit_sink(-3.0)
			_check(is_equal_approx(preview._get_scale(target), 1.15), "selected scale changes")
			_check(is_equal_approx(preview._get_sink(target), -3.0), "selected sink changes")
			preview._reset_settings()
		preview._target.select(15)
		preview._select_target(15)
		var capture_before: Vector2 = preview._slimes[0].get_capture_point()
		preview._edit_sink(5.0)
		_check(preview._slimes[0].get_capture_point().distance_to(capture_before) > 4.9, "capture center follows visual sinking")
		_check(is_equal_approx(preview._slimes[1].get_presentation_sink(), 0.0), "individual edits leave other species unchanged")
		preview._reset_settings()
		preview._place_samples()
		for stage: int in range(4):
			preview._stage.select(stage)
			preview._change_stage(stage)
			await _settle()
			for nest: NestView in preview._nest_views:
				var bounds: Rect2 = nest.get_hover_rect()
				_check(bounds.size.x > 0 and bounds.size.y > 0, "each nest stage has visible art and selection bounds")
				print("DISPLAY %s stage %d: %s" % [Preview.SPECIES_NAMES[nest.species], stage, str(bounds.size)])
				var sprite: Sprite2D = nest._art._sprite
				var source_width: float = sprite.texture.get_image().get_used_rect().size.x
				_check(is_equal_approx(nest._art.get_art_bounds().size.x, source_width), "nest bounds retain original visible PNG width at every stage")
				var common_scale: float = preview._slimes[2]._art_sprite.get_parent().get_global_transform_with_canvas().x.length()
				_check(is_equal_approx(sprite.get_global_transform_with_canvas().x.length(), common_scale), "nests, flowers and monsters share one viewing scale")
				_check_window_pixels(sprite)
			await _capture("stage_%d_%dx%d" % [stage, resolution.x, resolution.y])
		preview._play_spawn()
		await _settle()
		preview._target.select(0)
		preview._select_target(0)
		var original_multiplier: float = preview.settings.all_scale
		preview._toggle_native_sizes()
		await _settle()
		_check(preview._native_gallery._pictures.size() == 6, "native gallery includes all source art")
		var screen_ratio: float = float(get_tree().root.size.x) / get_tree().root.get_visible_rect().size.x
		for picture: TextureRect in preview._native_gallery._pictures:
			_check(is_equal_approx(picture.get_global_transform_with_canvas().x.length() * screen_ratio, 1.0), "native PNG pixels display at 1:1 screen pixels")
			_check(picture.size.is_equal_approx(picture.texture.get_size()), "native image preserves full canvas")
		_check(is_equal_approx(preview.settings.all_scale, original_multiplier), "native view does not overwrite game scale")
		await _capture("native_%dx%d" % [resolution.x, resolution.y])
		preview._toggle_menu()
		await _settle()
		await _capture("native_collapsed_%dx%d" % [resolution.x, resolution.y])
		preview._toggle_menu()
		preview._toggle_native_sizes()
		_check(preview._nests.visible and not preview._native_gallery.visible, "native toggle restores source-sized planet view")
		_check_monster_pixels(preview)
		preview._reset_settings()
		if resolution == Vector2i(1920, 1080) and "--fullscreen" in OS.get_cmdline_user_args():
			get_tree().root.mode = Window.MODE_FULLSCREEN
			await _settle()
			print("FULLSCREEN: window %s, viewport %s, screen transform %s" % [get_tree().root.size, get_tree().root.get_visible_rect().size, get_tree().root.get_screen_transform()])
			_check_monster_pixels(preview)
			await _capture("fullscreen")
			get_tree().root.mode = Window.MODE_WINDOWED
			get_tree().root.size = resolution
			await _settle()
			_check_monster_pixels(preview)
		preview.settings.monster_scales[2] = 1.25
		_check(ResourceSaver.save(preview.settings, "res://artifacts/art_alignment/roundtrip.tres") == OK, "settings save")
		var saved: ArtPresentationSettings = ResourceLoader.load("res://artifacts/art_alignment/roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as ArtPresentationSettings
		_check(is_equal_approx(saved.monster_scales[2], 1.25), "saved individual settings roundtrip")
		var defaults: ArtPresentationSettings = load(Preview.SETTINGS_PATH) as ArtPresentationSettings
		_check(is_equal_approx(defaults.monster_scales[2], 1.0), "unsaved preview edits leave game defaults unchanged")
		preview.queue_free()
		await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	print("PASS: art controls, stages, local edits, persistence, capture geometry and toolbar clearance" if _failures.is_empty() else "FAIL: art alignment")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_source_sizes(preview: Preview) -> void:
	for nest: NestView in preview._nest_views:
		for art: ItemArt in nest._art._get_art_items():
			_check(art.scale.is_equal_approx(Vector2.ONE), "source art root drops inherited flower scale")
			_check_source_animation(art)
	for monster: PrototypeSlime in preview._slimes:
		_check(is_equal_approx(monster.presentation_scale, preview._source_view_scale), "all species use the same viewing scale")
		if monster is DrillView:
			var drill: DrillView = monster as DrillView
			_check(is_equal_approx(drill.art_scale, 1.0), "drill monster drops gameplay art scale")
			_check(drill.art.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "drill keeps smooth HD filtering")
		else:
			_check(is_equal_approx(monster.slime_art_scale, 1.0), "ordinary monsters drop gameplay art scale")
			_check(monster.get_source_texture().resource_path.contains("高清怪兽"), "monster preview keeps calibrated HD art")
	var original: ItemArt = SourceDrillNest.instantiate() as ItemArt
	add_child(original)
	original.show_frame(&"1-2", 0)
	var source_sprite: Sprite2D = original.get_node("画面/贴图") as Sprite2D
	_check(is_equal_approx(source_sprite.scale.x, 0.1854305), "preview leaves shared gameplay animations unchanged")
	original.queue_free()
	_check_monster_pixels(preview)


func _check_monster_pixels(preview: Preview) -> void:
	for monster: PrototypeSlime in preview._slimes:
		var sprite: Sprite2D
		if monster is DrillView:
			sprite = (monster as DrillView)._art_sprite
		else:
			sprite = monster.slime_art._sprite
		var parent_transform: Transform2D = sprite.get_parent().get_global_transform_with_canvas()
		var window_ratio: float = float(get_tree().root.size.x) / get_tree().root.get_visible_rect().size.x
		_check(is_equal_approx(parent_transform.x.length() * window_ratio, 1.0), "monster viewing scale keeps calibrated artwork at window pixel size")
		var screen_ratio: float = float(get_tree().root.size.x) / get_tree().root.get_visible_rect().size.x
		var canvas: Vector2 = sprite.texture.get_size()
		var display: Vector2 = Vector2(
			sprite.get_global_transform_with_canvas().x.length() * canvas.x,
			sprite.get_global_transform_with_canvas().y.length() * canvas.y
		) * screen_ratio
		_check(display.is_equal_approx(canvas * sprite.scale.abs()), "HD texture retains its calibrated scale in window pixels")
		print("SOURCE PIXELS species %d: PNG %s, window %s" % [monster.species, canvas, display])


func _check_window_pixels(sprite: Sprite2D) -> void:
	var screen_ratio: float = float(get_tree().root.size.x) / get_tree().root.get_visible_rect().size.x
	var transform: Transform2D = sprite.get_global_transform_with_canvas()
	_check(is_equal_approx(transform.x.length() * screen_ratio, 1.0), "planet art maps each source pixel to one window pixel horizontally")
	_check(is_equal_approx(transform.y.length() * screen_ratio, 1.0), "planet art maps each source pixel to one window pixel vertically")
	var screen_transform: Transform2D = sprite.get_screen_transform()
	var window_transform: Transform2D = get_tree().root.get_screen_transform()
	_check(is_equal_approx(screen_transform.x.length() * window_transform.x.length(), 1.0), "window stretch preserves horizontal PNG pixels")
	_check(is_equal_approx(screen_transform.y.length() * window_transform.y.length(), 1.0), "window stretch preserves vertical PNG pixels")


func _check_source_animation(art: ItemArt) -> void:
	for clip: StringName in art.animation_player.get_animation_list():
		var animation: Animation = art.animation_player.get_animation(clip)
		var track: int = animation.find_track(NodePath("画面/贴图:scale"), Animation.TYPE_VALUE)
		for key: int in range(animation.track_get_key_count(track)):
			var size: Vector2 = animation.track_get_key_value(track, key)
			_check(size.is_equal_approx(Vector2.ONE), "every animation frame keeps source dimensions, including spawn and flower production")


func _settle() -> void:
	for frame: int in range(4):
		await get_tree().process_frame


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	await get_tree().process_frame
	RenderingServer.force_draw()
	get_tree().root.get_texture().get_image().save_png("res://artifacts/art_alignment/%s.png" % label)


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _failures:
		_failures.append(message)

