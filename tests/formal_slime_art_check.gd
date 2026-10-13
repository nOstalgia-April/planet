extends Node

const SlimeScene: PackedScene = preload("res://scenes/world/slime.tscn")
const GiantScene: PackedScene = preload("res://scenes/world/giant_slime.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var surface: PlanetSurface = PlanetSurface.new()
	add_child(surface)
	for species: int in range(2):
		var actor: PrototypeSlime = SlimeScene.instantiate() as PrototypeSlime
		add_child(actor)
		actor.configure_species(species as PrototypeSlime.Species, false, 2)
		actor.setup(1, Vector2.UP * 240.0, surface)
		actor.set_process(false)
		actor.slime_art._active.animation_player.pause()
		_check(
			actor.get_source_texture().resource_path.contains("史莱姆" if species == 0 else "黏液怪"),
			"formal source texture is used"
		)
		actor.refresh_presentation()
		var expected: Vector2 = (
			actor.position
			+ (actor.slime_art.transform * actor.slime_art.get_art_bounds().get_center()).rotated(
				actor.rotation
			)
		)
		_check(
			actor.get_capture_point().distance_to(expected) < 0.001,
			"capture center matches alpha-bounded picture"
		)
		var initial_width: float = actor.get_visual_rect().size.x
		actor.art_settings = actor.art_settings.duplicate(true) as ArtPresentationSettings
		actor.art_settings.monster_scales[species] = 1.5
		actor.art_settings.monster_sinks[species] = 4.0
		actor.refresh_presentation()
		_check(
			is_equal_approx(actor.get_visual_rect().size.x / initial_width, 1.5),
			"art scales through presentation settings"
		)
		var initial: Vector2 = actor.get_visual_rect().size
		actor.apply_capture(0.3, 1.0, actor.get_capture_point())
		actor.refresh_presentation()
		_check(actor.get_visual_rect().size.x < initial.x, "suction shrinks original art")
		_check(not actor.consumed, "partial capture keeps actor alive")
		actor.release_capture(1.0)
		actor.configure_species(species as PrototypeSlime.Species, true, 6)
		actor.refresh_presentation()
		_check(
			actor.get_source_texture().resource_path.contains("高价值怪物"),
			"valuable individual uses supplied crown artwork"
		)
		actor.launch(Vector2.RIGHT)
		actor.set_process(false)
		if species == 0:
			_check(
				actor.slime_art._active.animation_player.current_animation == &"跳跃",
				"pink launch uses source jump"
			)
			actor.slime_art._active.animation_player.advance(actor.launch_seconds + 0.01)
			_check(
				actor.slime_art._active.animation_player.current_animation == &"待机",
				"jump returns to idle"
			)
		else:
			_check(
				actor.slime_art._active.animation_player.current_animation == &"待机",
				"mucus retains available idle animation"
			)
		actor.queue_free()
		await get_tree().process_frame
	var giant: PrototypeSlime = GiantScene.instantiate() as PrototypeSlime
	add_child(giant)
	giant.setup(1, Vector2.UP * 240.0, surface)
	giant.set_process(false)
	_check(
		giant.slime_art != null and giant.get_source_texture() != null,
		"giants inherit formal species art"
	)
	for failure: String in _failures:
		push_error(failure)
	print(
		(
			"PASS: formal species art, launch/idle, crowns, giant, presentation settings and capture geometry"
			if _failures.is_empty()
			else "FAIL: formal slime art"
		)
	)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
