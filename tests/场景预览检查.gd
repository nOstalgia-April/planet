extends SceneTree

const FrameArt = preload("res://scripts/场景动画/帧动画.gd")
const PlayPreview = preload("res://features/场景预览/游玩预览.gd")
const ActionPreview = preload("res://features/场景预览/动作预览.gd")
const ItemPreview = preload("res://features/物品动画预览/动画预览.gd")
const Menu = preload("res://scenes/主菜单/主菜单.gd")
const ENTRIES: Array[String] = [
	"res://scenes/主菜单/主菜单.tscn",
	"res://features/场景预览/近景游玩预览.tscn",
	"res://features/场景预览/全景游玩预览.tscn",
	"res://features/场景预览/吸尘器预览.tscn",
	"res://features/场景预览/捕网预览.tscn",
	"res://features/场景预览/黏液怪移动预览.tscn",
	"res://features/物品动画预览/物品动画总览.tscn",
	"res://features/splash_preview/splash_preview.tscn",
	"res://features/slime_suction_preview/slime_suction_preview.tscn",
	"res://features/globe_preview/globe_preview.tscn",
	"res://features/technology_tree_preview/technology_tree_preview.tscn",
]
const RETURN_BUTTONS: Array[NodePath] = [
	^"预览导航/返回主菜单",
	^"预览导航/返回主菜单",
	^"返回主菜单",
	^"返回主菜单",
	^"返回主菜单",
	^"返回主菜单",
	^"UI/Layout/Columns/Playback/返回主菜单",
	^"UI/返回主菜单",
	^"Controls/Row/返回主菜单",
	^"TechnologyPage/Margin/Content/Header/Close",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	for path in ENTRIES:
		var packed: PackedScene = load(path) as PackedScene
		assert(packed != null, path)
		var entry: Node = packed.instantiate()
		root.add_child(entry)
		await process_frame
		if entry is PlayPreview:
			_check_gameplay(entry as PlayPreview)
		elif entry is ActionPreview:
			_check_animation(entry as ActionPreview)
		elif entry is Menu:
			(entry as Menu)._toggle_previews()
		if "--capture" in OS.get_cmdline_user_args():
			for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
				root.size = dimensions
				await create_timer(0.4).timeout
				if entry is ActionPreview:
					(entry as ActionPreview)._seek(3.0)
				elif entry is ItemPreview:
					(entry as ItemPreview)._object_picker.select(7)
					(entry as ItemPreview)._on_object_selected(7)
					(entry as ItemPreview)._on_frame_selected(12.0)
				await RenderingServer.frame_post_draw
				var destination: String = (
					"res://artifacts/scene_art_audit_2026_10_08/%s_%dx%d.png"
					% [path.get_file().get_basename(), dimensions.x, dimensions.y]
				)
				assert(root.get_texture().get_image().save_png(destination) == OK)
		await process_frame
		await process_frame
		entry.queue_free()
		await process_frame
	assert(change_scene_to_file(ENTRIES[0]) == OK)
	await scene_changed
	var menu: Menu = current_scene as Menu
	(menu.get_node("画布/开始") as Button).pressed.emit()
	await scene_changed
	assert(current_scene.scene_file_path == ENTRIES[1], "Start 必须实际切换到近景游玩预览。")
	var game: PlayPreview = current_scene as PlayPreview
	(game.get_node("预览导航/返回主菜单") as Button).pressed.emit()
	await scene_changed
	assert(current_scene.scene_file_path == ENTRIES[0])
	await _check_preview_navigation()
	print(
		"PASS: 11 scenes, all 10 title preview buttons and return paths, frame rates, pause/seek, shared gameplay, Start and return."
	)
	quit()


func _check_preview_navigation() -> void:
	for index: int in range(RETURN_BUTTONS.size()):
		var menu: Menu = current_scene as Menu
		(menu.get_node("画布/预览") as Button).pressed.emit()
		await process_frame
		var previews: GridContainer = menu.get_node("画布/预览选择/列表") as GridContainer
		assert(previews.get_child_count() == RETURN_BUTTONS.size())
		for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
			root.size = dimensions
			await process_frame
			await process_frame
			for child: Button in previews.get_children():
				var rectangle: Rect2 = (
					child.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, child.size)
				)
				assert(root.get_visible_rect().encloses(rectangle), "预览按钮必须完整显示。")
		(previews.get_child(index) as Button).pressed.emit()
		await scene_changed
		assert(current_scene.scene_file_path == ENTRIES[index + 1], "标题预览按钮必须打开对应页面。")
		(current_scene.get_node(RETURN_BUTTONS[index]) as Button).pressed.emit()
		await scene_changed
		assert(current_scene.scene_file_path == ENTRIES[0], "每个预览必须能返回主菜单。")


func _check_gameplay(game: PlayPreview) -> void:
	assert(game._view.is_overview() == game.start_in_overview)
	var original_run: PrototypeRun = game.run
	var nest_positions: Array[Vector2] = []
	for nest in game._nest_views:
		nest_positions.append(nest.position)
	game.run.candy = 17
	(game.get_node("预览导航/切换视角") as Button).pressed.emit()
	assert(game._view.is_overview() != game.start_in_overview)
	assert(game.run == original_run and game.run.candy == 17)
	for index in range(nest_positions.size()):
		assert(game._nest_views[index].position.is_equal_approx(nest_positions[index]))
	(game.get_node("预览导航/切换视角") as Button).pressed.emit()
	assert(game._view.is_overview() == game.start_in_overview)
	var surface: Node = game.get_node("World/PlanetSurface")
	assert((surface.get_node("近景画面") as Node2D).visible != game.start_in_overview)
	assert((surface.get_node("全景画面") as Node2D).visible == game.start_in_overview)
	var near_sprite: Sprite2D = surface.get_node("近景画面/贴图") as Sprite2D
	assert(
		near_sprite.texture.get_size().x <= 4096.0 and near_sprite.texture.get_size().y <= 4096.0
	)


func _check_animation(preview: ActionPreview) -> void:
	var art: FrameArt = preview.view
	var animation: Animation = art.animation_player.get_animation(art.clip)
	var expected_fps: float = 7.0 if preview.name == &"吸尘器预览" else 5.0
	assert(is_equal_approx(art.frames_per_second, expected_fps))
	assert(is_equal_approx(animation.length, float(art.frame_count) / expected_fps))
	preview._seek(2.0)
	assert(not art.animation_player.is_playing())
	assert(preview._frame_label.text.begins_with("03 /"), "逐帧选择必须立即更新帧号。")
	assert(is_equal_approx(art.animation_player.current_animation_position, 2.0 / expected_fps))
	preview._next()
	assert(is_equal_approx(art.animation_player.current_animation_position, 3.0 / expected_fps))
	preview._replay()
	art.animation_player.advance(animation.length + 0.01)
	if art.clip == &"展开":
		assert(animation.loop_mode == Animation.LOOP_NONE)
		assert(preview._finished)
	else:
		assert(animation.loop_mode == Animation.LOOP_LINEAR)
		assert(not preview._finished)
