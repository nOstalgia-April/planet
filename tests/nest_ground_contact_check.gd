extends Node

# Requires rendering; the contact samples come from the actual GPU output.

const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Play = preload("res://features/场景预览/游玩预览.gd")
const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const OUTPUT: String = "res://artifacts/nest_ground_contact_20261014/after"

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		await _check_resolution(dimensions)
	print("Nest ground contact: %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_resolution(dimensions: Vector2i) -> void:
	get_tree().root.size = dimensions
	var label: String = "_%dx%d" % [dimensions.x, dimensions.y]
	var game: Play = PLAY.instantiate() as Play
	add_child(game)
	game.set_process(false)
	game._view.set_process(false)
	game._layout.set_process(false)
	game._pipe.hide()
	game._net.hide()
	var view: NestView = game._nest_views[0]
	var difference: float = angle_difference(
		game._world.rotation, -PI / 2.0 - view.position.angle()
	)
	var screen_radius: float = (
		game._planet.radius * game._world.scale.x * game._view.projection_root.scale.x
	)
	game._view.begin_drag(Vector2.ZERO)
	game._view.drag_to(Vector2(difference * screen_radius, 0.0))
	game._view.end_drag()
	for other: NestView in game._nest_views:
		if other != view:
			other.hide()
	for item: ItemArt in view._art.get_children():
		item.animation_player.callback_mode_process = (
			AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = get_tree().root.size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var sprite: Sprite2D = Sprite2D.new()
	viewport.add_child(sprite)
	for species: int in range(3):
		view.configure_species(species)
		for stage: int in range(3):
			view.update_state(stage, false, 3, false)
			await get_tree().process_frame
			view.refresh_presentation()
			var source: Sprite2D = view._art._sprite
			sprite.texture = source.texture
			sprite.material = source.material
			sprite.centered = source.centered
			sprite.offset = source.offset
			sprite.transform = source.get_global_transform_with_canvas()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var mask: Image = viewport.get_texture().get_image()
			var image: Image = get_tree().root.get_texture().get_image()
			mask.save_png(OUTPUT + "/mask_%d_%d" % [species, stage] + label + ".png")
			image.save_png(OUTPUT + "/formal_%d_%d" % [species, stage] + label + ".png")
			_check_contact(view, mask)
			view._art.play_spawn()
			var item: ItemArt = view._art._spawn
			var clip: StringName = view._art.SPAWN_CLIPS[stage]
			var count: int = item.get_frame_count(clip)
			for frame: int in range(count):
				item.show_frame(clip, frame)
				view._art._refresh_bounds()
				view.refresh_presentation()
				source = view._art._sprite
				sprite.texture = source.texture
				sprite.material = source.material
				sprite.transform = source.get_global_transform_with_canvas()
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				mask = viewport.get_texture().get_image()
				_check_contact(view, mask)
				if frame == int(count / 2.0):
					get_tree().root.get_texture().get_image().save_png(
						OUTPUT + "/spawn_%d_%d" % [species, stage] + label + ".png"
					)
	game.queue_free()
	viewport.queue_free()
	await get_tree().process_frame


func _check_contact(view: NestView, mask: Image) -> void:
	var art: Transform2D = view._art.get_global_transform_with_canvas()
	var bounds: Rect2 = view._art.get_art_bounds()
	for ratio: float in [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]:
		var x: float = lerpf(bounds.position.x, bounds.end.x, ratio)
		var point: Vector2 = art * Vector2(x, view._art.get_ground_contact_y(x))
		var inward: Vector2 = art.y.normalized()
		var pixel: Vector2i = Vector2i((point + inward * 2.0).floor())
		var alpha: float = mask.get_pixelv(pixel).a
		if alpha < 0.2:
			_failures += 1
			print(
				(
					"GAP species=%d stage=%d ratio=%.2f point=%s"
					% [view.species, view._art._display_level, ratio, point]
				)
			)
