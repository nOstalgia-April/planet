extends Node

const Play = preload("res://features/场景预览/游玩预览.gd")
const PLAY_SCENE: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Drill = preload("res://scripts/drill_monster.gd")
const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const Shine = preload("res://scripts/effects/jewelry_shine.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_window().size = Vector2i(1920, 1080)
	var game: Play = PLAY_SCENE.instantiate() as Play
	add_child(game)
	game.set_process(false)
	game._view.set_process(false)
	game._layout.close_panels()
	for frame: int in range(3):
		await get_tree().process_frame
	game._apply_layout()
	for old_actor: PrototypeSlime in game._slimes:
		old_actor.hide()
		old_actor.set_process(false)
	for kind: int in range(3):
		for copy_index: int in range(2):
			var scene: PackedScene = game.drill_scene if kind == 2 else game.slime_scene
			var actor: PrototypeSlime = scene.instantiate() as PrototypeSlime
			game._slime_root.add_child(actor)
			actor.setup(1, Vector2.UP * 220.0, game._planet)
			actor.configure_species(kind as PrototypeSlime.Species, true, 6)
			actor.presentation_scale = game._view.near_slime_scale
			if kind == 2:
				(actor as Drill)._enter_phase(Drill.Phase.EXPOSED, 10.0, &"夹夹")
			var screen_position: Vector2 = Vector2(480.0 + kind * 370.0 + copy_index * 145.0, 800.0)
			actor.position = (
				game._world.get_global_transform_with_canvas().affine_inverse() * screen_position
			)
			actor.set_process(false)
			actor._update_surface_rotation()
			actor.refresh_presentation()
			game._slimes.append(actor)
			var art: ItemArt = (actor as Drill).art if kind == 2 else actor.slime_art._active
			art.show_frame(&"待机", 0)
			var effect: Shine = art.get_node("JewelryShine") as Shine
			if copy_index == 0:
				effect._shine_elapsed = 0.27
				effect._process(0.0)
			else:
				effect._finish_shine()
			effect.set_process(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var capture_index: int = args.find("--capture")
	if capture_index >= 0:
		assert(capture_index + 1 < args.size())
		assert(get_viewport().get_texture().get_image().save_png(args[capture_index + 1]) == OK)
	print("PASS: current game renders three independent pairs with original art and jewelry shader")
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit()
