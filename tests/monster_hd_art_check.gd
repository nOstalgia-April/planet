extends SceneTree

const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const SlimeScene: PackedScene = preload("res://scenes/world/slime.tscn")
const GiantScene: PackedScene = preload("res://scenes/world/giant_slime.tscn")
const DrillScene: PackedScene = preload("res://scenes/world/drill_monster.tscn")
const Drill = preload("res://scripts/drill_monster.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_frame_geometry()
	var surface: PlanetSurface = PlanetSurface.new()
	root.add_child(surface)
	for kind: int in range(3):
		var scene: PackedScene = DrillScene if kind == 2 else SlimeScene
		var actor: PrototypeSlime = scene.instantiate() as PrototypeSlime
		root.add_child(actor)
		actor.configure_species(kind as PrototypeSlime.Species, false, 2)
		actor.setup(kind + 1, Vector2.UP * 240.0, surface)
		actor.set_process(false)
		if kind == 2:
			(actor as Drill)._enter_phase(Drill.Phase.EXPOSED, 3.5, &"夹夹")
		var art: ItemArt = (actor as Drill).art if kind == 2 else actor.slime_art._active
		art.animation_player.pause()
		var ordinary: Texture2D = actor.get_source_texture()
		_check(ordinary.resource_path.contains("高清怪兽"), "ordinary actor uses HD artwork")
		var resting: Rect2 = actor.get_visual_rect()
		actor.apply_attraction(0.02, actor.get_capture_point(), 0.7)
		_check(actor.get_source_texture() == ordinary, "attraction alone keeps ordinary expression")
		actor.apply_capture(0.1 if kind == 2 else 0.2, 1.0, actor.get_capture_point())
		actor.refresh_presentation()
		_check(
			actor.get_source_texture().resource_path.contains("/吸入/"),
			"actual suction shows crying expression"
		)
		if kind == 2:
			_check(
				actor.get_visual_rect().size.distance_to(resting.size) < 0.02,
				"drill suction keeps its exposed visible size"
			)
		else:
			_check(
				actor.get_visual_rect().size.x < resting.size.x, "suction retains gameplay shrinking"
			)
		_check(
			actor.get_visual_rect().has_point(actor.get_capture_point()),
			"capture point stays inside crying art"
		)
		actor.release_capture(0.02)
		_check(
			actor.get_source_texture() == ordinary,
			"release restores previous pose before progress fully recovers"
		)
		actor.apply_capture(0.02, 1.0, actor.get_capture_point())
		actor._process(0.2)
		if kind == 2:
			_check(
				actor.get_source_texture().resource_path.contains("/吸入/"),
				"drill suction remains locked across slow frames until explicit release"
			)
			actor.release_capture(0.02)
		_check(
			not actor.get_source_texture().resource_path.contains("/吸入/"),
			"lost suction recovers expression"
		)
		actor.configure_species(kind as PrototypeSlime.Species, true, 6)
		actor.apply_capture(0.02, 1.0, actor.get_capture_point())
		actor.refresh_presentation()
		_check(
			actor.high_value
			and actor.get_source_texture().resource_path.contains("高价值怪物")
			and actor.get_source_texture().resource_path.contains("/吸入/"),
			"valuable suction keeps supplied upgraded artwork"
		)
		actor.queue_free()
		await process_frame
	var giant: PrototypeSlime = GiantScene.instantiate() as PrototypeSlime
	root.add_child(giant)
	giant.setup(1, Vector2.UP * 240.0, surface)
	giant.apply_capture(0.02, 1.0, giant.get_capture_point())
	_check(
		giant.get_source_texture().resource_path.contains("/吸入/"),
		"giants share the suction expression"
	)
	for failure: String in _failures:
		push_error(failure)
	print(
		(
			"PASS: HD imports, original frame size/anchors, mipmaps and three suction expressions"
			if _failures.is_empty()
			else "FAIL: HD monster artwork"
		)
	)
	quit(0 if _failures.is_empty() else 1)


func _check_frame_geometry() -> void:
	_check_scene_geometry("res://assets/物品动画/高清怪兽/来源与缩放.json", false)
	_check_scene_geometry("res://assets/物品动画/高价值怪物/来源与缩放.json", true)


func _check_scene_geometry(manifest_path: String, valuable: bool) -> void:
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(manifest_path)
	)
	var views: Dictionary[String, ItemArt] = {}
	var species_names: Array[String] = ["史莱姆", "黏液怪", "地鼠"]
	for species: String in species_names:
		var scene_path: String = "res://scenes/物品动画/%s%s.tscn" % ["高价值" if valuable else "", species]
		var scene: PackedScene = load(scene_path) as PackedScene
		var art: ItemArt = scene.instantiate() as ItemArt
		root.add_child(art)
		views[species] = art
		_check(
			art.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
			"monster art uses smooth mipmap filtering"
		)
	for binding: Dictionary in manifest["绑定"]:
		var art: ItemArt = views[binding["场景"]]
		art.show_frame(StringName(binding["动作"]), int(binding["帧"]))
		var sprite: Sprite2D = art.get_node("画面/贴图") as Sprite2D
		_check(
			sprite.texture.resource_path == binding["项目路径" if valuable else "高清路径"],
			"animation actually binds its supplied frame"
		)
		_check(sprite.texture.get_image().has_mipmaps(), "HD texture imports mipmaps")
		if binding.get("按主体校准", false):
			continue
		var original: Texture2D = load(binding["普通路径" if valuable else "旧路径"]) as Texture2D
		var old_position: Array = binding["普通位置" if valuable else "旧位置"]
		var old_scale: Array = binding["普通缩放" if valuable else "旧缩放"]
		var expected: Rect2 = Rect2(original.get_image().get_used_rect())
		expected.position = (
			Vector2(old_position[0], old_position[1])
			+ expected.position * Vector2(old_scale[0], old_scale[1])
		)
		expected.size *= Vector2(old_scale[0], old_scale[1])
		var actual: Rect2 = sprite.transform * Rect2(sprite.texture.get_image().get_used_rect())
		_check(
			actual.position.distance_to(expected.position) < 0.02,
			"HD frame retains original anchor"
		)
		_check(
			actual.size.distance_to(expected.size) < 0.02, "HD frame retains original visible size"
		)
	for art: ItemArt in views.values():
		art.free()


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
