extends Node

const Demo = preload("res://scripts/disk_demo.gd")
const Trail = preload("res://scripts/mucus_field.gd")
const DEMO_SCENE: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const TRAIL_SCENE: PackedScene = preload("res://scenes/effects/mucus_field.tscn")
const SLIME_SCENE: PackedScene = preload("res://scenes/world/slime.tscn")

var _demo: Demo


func _ready() -> void:
	_build.call_deferred()


func _build() -> void:
	_demo = DEMO_SCENE.instantiate() as Demo
	add_child(_demo)
	_demo.set_process(false)
	_demo._view.set_process(false)
	_demo._layout.set_process(false)
	for frame: int in range(5):
		await get_tree().process_frame
	for actor: PrototypeSlime in _demo._slimes:
		actor.set_process(false)
		actor.hide()
	_demo._pipe.hide()
	_demo._net.hide()
	_demo._layout.hide()
	# Real game surface and actors; staged crossings make contact easy to inspect.
	for index: int in range(3):
		var origin: Vector2 = Vector2(-79.0 + index * 61.0, -233.0 + (index % 2) * 7.0)
		var trail: Trail = TRAIL_SCENE.instantiate() as Trail
		_demo._mucus_root.add_child(trail)
		trail.configure(_demo._planet, origin, index, _demo.run.settings.mucus_trail_half_width, 7.0)
		for step: int in range(1, 29):
			trail.advance(0.07, false)
			trail.append_ground_point(origin + Vector2(step * 0.86, sin(step * 0.12 + index) * 3.0), false)
		trail.advance(0.45)
		var end: Vector2 = trail.get_ground_points()[-1]
		_actor(end, PrototypeSlime.Species.MUCUS)
		if index != 1:
			var contact: Vector2 = trail.get_ground_points()[10] + Vector2(0.0, 3.2)
			var pink: PrototypeSlime = _actor(contact, PrototypeSlime.Species.SLIME)
			pink.on_mucus = trail.contains_ground_point(contact)
			assert(pink.is_anchored(), "Pink slime on the spread must use real mucus contact.")
		_actor(origin + Vector2(-12.0, 16.0), PrototypeSlime.Species.SLIME)
	for frame: int in range(5):
		await get_tree().process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var output: String = "res://artifacts/mucus_spread_oct13_preview.png"
		assert(get_viewport().get_texture().get_image().save_png(output) == OK)
		print("MUCUS_SPREAD_PREVIEW: ", Time.get_datetime_string_from_system(), " ", output)
		get_tree().quit()


func _actor(at: Vector2, species: PrototypeSlime.Species) -> PrototypeSlime:
	var actor: PrototypeSlime = SLIME_SCENE.instantiate() as PrototypeSlime
	_demo._slime_root.add_child(actor)
	actor.configure_species(species, false, 1)
	actor.setup(1, at, _demo._planet)
	actor.position = at
	actor.presentation_scale = _demo._view.near_slime_scale
	actor.set_process(false)
	actor.refresh_presentation()
	return actor
