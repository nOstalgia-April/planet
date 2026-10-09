extends SceneTree

const AnimationView = preload("res://scripts/物品动画/动画物件.gd")
const Preview = preload("res://features/物品动画预览/动画预览.gd")
const PreviewScene: PackedScene = preload("res://features/物品动画预览/物品动画总览.tscn")

var _failures: int = 0
var _completed: int = 0


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var preview: Preview = PreviewScene.instantiate() as Preview
	root.add_child(preview)
	_check(preview.object_scenes.size() == 9, "九个独立物件场景")
	for packed_scene in preview.object_scenes:
		var view: AnimationView = packed_scene.instantiate() as AnimationView
		root.add_child(view)
		var expected_fps: float = 12.0 if "巢穴" in packed_scene.resource_path else 8.0
		_check(is_equal_approx(view.frames_per_second, expected_fps), "巢穴12帧，其他物件8帧")
		_check(not view.animation_player.is_playing(), "物件实例不自动触发演出")
		for clip_name in view.animation_order:
			var animation: Animation = view.animation_player.get_animation(clip_name)
			var frame_count: int = view.get_frame_count(clip_name)
			_check(is_equal_approx(animation.length, frame_count / expected_fps), "动画时长匹配帧率")
			_check(is_equal_approx(animation.step, 1.0 / expected_fps), "时间轴步长匹配帧率")
			_check(animation.track_get_key_count(0) == frame_count, "帧数与贴图轨道一致")
			for frame in range(frame_count):
				_check(
					is_equal_approx(animation.track_get_key_time(0, frame), frame / expected_fps),
					"每帧时间间隔正确"
				)
				view.show_frame(clip_name, frame)
				var sprite: Sprite2D = view.get_node("画面/贴图") as Sprite2D
				var expected: Texture2D = animation.track_get_key_value(0, frame) as Texture2D
				_check(sprite.texture == expected, "中文路径贴图按数字顺序显示")
				_check(not view.animation_player.is_playing(), "逐帧查看保持暂停")
		view.free()
	_check_nest(preview.object_scenes[6], 26, "008.png")
	_check_nest(preview.object_scenes[7], 19, "012.png")
	_check_nest(preview.object_scenes[8], 25, "009.png")
	var original_view: AnimationView = preview.object_scenes[0].instantiate() as AnimationView
	root.add_child(original_view)
	preview._on_repeat_toggled(false)
	_check(
		preview.current_view.animation_player.get_animation(&"待机").loop_mode == Animation.LOOP_NONE,
		"预览关闭循环生效"
	)
	_check(
		original_view.animation_player.get_animation(&"待机").loop_mode == Animation.LOOP_LINEAR,
		"预览控制不改变共享动画资源"
	)
	preview._on_frame_selected(3.0)
	var paused_position: float = preview.current_view.animation_player.current_animation_position
	await create_timer(0.2).timeout
	_check(
		is_equal_approx(
			preview.current_view.animation_player.current_animation_position, paused_position
		),
		"暂停期间帧不推进"
	)
	preview._on_next_frame()
	_check(
		is_equal_approx(preview.current_view.animation_player.current_animation_position, 0.5),
		"下一帧推进0.125秒"
	)
	preview._on_object_selected(7)
	_check(preview.current_clip == &"1-2-3-4", "巢穴默认完整串联")
	_check(preview.current_view.get_frame_count(preview.current_clip) == 19, "切换场景复位旧播放状态")
	preview._on_frame_selected(3.0)
	preview._on_next_frame()
	_check(
		is_equal_approx(
			preview.current_view.animation_player.current_animation_position, 4.0 / 12.0
		),
		"巢穴逐帧推进1/12秒"
	)
	_check(preview._frame_label.text == "05 / 19 · 12帧/秒", "巢穴显示实际帧率和正确帧号")
	original_view.free()
	preview.queue_free()
	await process_frame
	print("物品动画检查：", "通过" if _failures == 0 else "失败", "；失败数=", _failures)
	quit(0 if _failures == 0 else 1)


func _check_nest(packed_scene: PackedScene, count: int, final_file: String) -> void:
	var view: AnimationView = packed_scene.instantiate() as AnimationView
	root.add_child(view)
	_check(view.get_frame_count(&"1-2-3-4") == count, "巢穴完整串联帧数")
	view.show_frame(&"1-2-3-4", count - 1)
	var sprite: Sprite2D = view.get_node("画面/贴图") as Sprite2D
	_check(sprite.texture.resource_path.ends_with("3-4/" + final_file), "完整升级停在花形终态")
	_completed = 0
	view.clip_finished.connect(_on_clip_finished)
	view.play_clip(&"1-2-3-4")
	for frame in range(count + 2):
		view.animation_player.advance(1.0 / 12.0)
	_check(_completed == 1, "单次升级仅报告一次完成")
	_check(not view.animation_player.is_playing(), "物件完整升级不自行重播")
	view.free()


func _on_clip_finished(_clip_name: StringName) -> void:
	_completed += 1


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)
