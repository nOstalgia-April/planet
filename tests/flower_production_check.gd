extends Node

const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Demo = preload("res://scripts/disk_demo.gd")
const Restoration = preload("res://scripts/planet_restoration.gd")
const OUTPUT: String = "res://artifacts/flower_production_20261014"

var _failures: int = 0
var _released: int = 0
var _released_amount: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_tree().root.size = dimensions
		var demo: Demo = PLAY.instantiate() as Demo
		add_child(demo)
		var restoration: Restoration = demo.get_node("PlanetRestoration") as Restoration
		demo.flower_appeared.disconnect(restoration.reveal_flower)
		demo.set_process(false)
		demo._view.set_process(false)
		demo._layout.set_process(false)
		demo._pipe.hide()
		demo._net.hide()
		demo.run.governance_level = 3
		var view: NestView = demo._nest_views[0]
		view.production_released.connect(_on_released)
		var turn: float = angle_difference(demo._world.rotation, -PI / 2.0 - view.position.angle())
		var radius: float = (
			demo._planet.radius * demo._world.scale.x * demo._view.projection_root.scale.x
		)
		demo._view.begin_drag(Vector2.ZERO)
		demo._view.drag_to(Vector2(turn * radius, 0.0))
		demo._view.end_drag()
		await get_tree().process_frame
		await get_tree().process_frame
		for species: int in range(3):
			view.configure_species(species)
			var nest: NestState = demo.run.get_nest(view.nest_id)
			nest.level = 3
			nest.is_tamed = true
			nest.income_clock = 0.0
			nest.income_remainder = 0.0
			view.update_state(3, true, 3, false)
			await get_tree().process_frame
			var before: int = demo.run.candy
			var release_count: int = _released
			demo.run._advance_automatic_income(nest, demo.run.settings.automatic_income_interval)
			var earned: int = demo.run.candy - before
			var sweep_seconds: float = maxf(
				view._production.minimum_sweep_seconds,
				(
					view._art._flower.animation_player.get_animation(&"产出").length
					* view._production.sweep_fraction
				)
			)
			_check(earned > 0 and view._production._active, "Paid production starts the sweep.")
			_check(_released == release_count, "Candy waits for the upward sweep.")
			await get_tree().create_timer(sweep_seconds * 0.45).timeout
			await _save("%d_%d_sweep" % [dimensions.x, species])
			await get_tree().create_timer(sweep_seconds * 0.55 + 0.09).timeout
			_check(
				_released == release_count + 1 and _released_amount == earned,
				"Release matches the paid amount once."
			)
			var reward: CollectionEffect = null
			for effect: Node in demo._effects.get_children():
				if effect is CollectionEffect:
					reward = effect
			_check(reward != null, "The flower launches the shared collection feedback.")
			if reward != null:
				var target: Vector2 = (
					demo._candy_label.get_global_transform_with_canvas()
					* (demo._candy_label.size * 0.5)
				)
				_check(
					reward.to_global(reward._destination).distance_to(target) < 1.0,
					"Candy reaches the current HUD position."
				)
				_check(
					reward._amount_label.text == "+%d" % earned,
					"The flower displays the actual production amount."
				)
			await _save("%d_%d_flight" % [dimensions.x, species])
			await get_tree().create_timer(0.85).timeout
			_check(
				demo.run.candy == before + earned, "Visual completion never credits candy twice."
			)
			_check(
				not view._production._active and not view._production._sparks.emitting,
				"The sweep and particle emitter finish."
			)
			_check(demo._effects.get_child_count() == 0, "Flying candy cleans itself up.")
		# Batched income keeps the total while an existing gesture finishes.
		var release_count: int = _released
		view.pulse_automatic(4)
		view.pulse_automatic(5)
		await get_tree().create_timer(1.0).timeout
		_check(
			_released == release_count + 1 and _released_amount == 9,
			"Overlapping income is preserved without rewinding the gesture."
		)
		demo.restart_run()
		await get_tree().process_frame
		await get_tree().create_timer(0.6).timeout
		_check(demo._effects.get_child_count() == 0, "Restart clears production feedback.")
		demo.queue_free()
		await get_tree().process_frame
	print(
		(
			"Flower production: %d failures; three species, two resolutions, amounts, HUD destination and cleanup."
			% _failures
		)
	)
	get_tree().quit(0 if _failures == 0 else 1)


func _on_released(_nest_id: int, amount: int) -> void:
	_released += 1
	_released_amount = amount


func _save(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
