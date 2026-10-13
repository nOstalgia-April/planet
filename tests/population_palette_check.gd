extends Node

const Play = preload("res://features/场景预览/游玩预览.gd")
const Palette = preload("res://scripts/population_palette.gd")
const IconButton = preload("res://scripts/ui/menu_icon_button.gd")
const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
var _failures: Array[String] = []
var _demo: Play


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 800)
	_demo = PLAY.instantiate() as Play
	add_child(_demo)
	_demo.set_process(false)
	_demo._view.set_process(false)
	var palette: Palette = _demo._population_palette
	palette.set_process(false)
	await _check_transition_and_pause(palette)
	palette.advance_population(Vector3(100, 80, 0), 0.4)
	_check(palette.dominant_species == 0, "Brief leadership changes do not switch the theme.")
	palette.advance_population(Vector3(100, 80, 0), 1.3)
	_check(
		palette.dominant_species == 1,
		"One hundred pink units lose to eighty blue units at 75 percent weight."
	)
	palette.advance_population(Vector3(108, 80, 0), 3.0)
	_check(
		palette.dominant_species == 1, "Small population fluctuations retain the existing theme."
	)
	palette.advance_population(Vector3.ZERO, 3.0)
	_check(palette.dominant_species == 1, "An empty planet retains its last palette.")
	palette.reset()
	palette.advance_population(Vector3(80, 60, 4), 2.5)
	_check(palette.dominant_species == 0, "Four drill units no longer outweigh eighty pink units.")
	palette.advance_population(Vector3(80, 60, 7), 2.5)
	_check(
		palette.dominant_species == 2,
		"Seven drill units outweigh eighty pink and sixty blue units at ten points each."
	)
	palette.reset()
	palette.advance_population(Vector3(120, 90, 6), 2.5)
	_check(
		palette.dominant_species == 0,
		"Six drill units no longer outweigh one hundred twenty pink units."
	)
	palette.advance_population(Vector3(120, 90, 10), 2.5)
	_check(
		palette.dominant_species == 2,
		"Ten drill units outweigh one hundred twenty pink and ninety blue units."
	)
	palette.advance_population(Vector3(120, 90, 0), 2.5)
	_check(palette.dominant_species != 2, "Capturing drill population releases green dominance.")
	_demo.restart_run()
	_check(palette.dominant_species == 0, "Restart resets the palette to pink.")
	_demo.run.nests[0].alive_slimes = 60
	_demo.run.nests[1].species = NestState.Species.DRILL
	_demo.run.nests[1].alive_slimes = 5
	palette._process(2.5)
	_check(
		palette.population_counts == Vector3(60, 0, 5),
		"Live nest totals retain fusion units and underground drill population."
	)
	_check(palette.dominant_species == 2, "Live population drives the same palette rule.")
	for shader_material: ShaderMaterial in palette._materials:
		var applied: Color = shader_material.get_shader_parameter("palette_dark")
		_check(
			applied.is_equal_approx(palette.settings.green[0]),
			"Every consumer receives the same green palette."
		)
	var exit_brush: TextureRect = _demo._layout._technology.get_node("%Close/Brush") as TextureRect
	var exit_material: ShaderMaterial = exit_brush.material as ShaderMaterial
	_check(
		(exit_material.get_shader_parameter("palette_dark") as Color).is_equal_approx(palette.settings.green[0]),
		"Technology exit graffiti follows the active background theme."
	)
	await _check_technology_accent(palette)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_themes()
	_demo.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print(
			"PASS: weighted populations, drill calibration, stable switching, empty state, reset and all palette consumers"
		)
	else:
		for failure: String in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_transition_and_pause(palette: Palette) -> void:
	palette.advance_population(Vector3(0, 20, 0), 1.19)
	palette.advance_population(Vector3(0, 20, 0), 0.02)
	var transitioning: Color = palette._materials[0].get_shader_parameter("palette_dark")
	_check(palette.dominant_species == 1, "Stable leadership starts a transition.")
	_check(
		not transitioning.is_equal_approx(palette.settings.blue[0]),
		"A newly accepted theme blends instead of jumping to its final color."
	)
	palette.set_process(true)
	get_tree().paused = true
	await get_tree().process_frame
	await get_tree().process_frame
	var paused_color: Color = palette._materials[0].get_shader_parameter("palette_dark")
	_check(
		paused_color.is_equal_approx(transitioning), "Pause freezes an in-flight color transition."
	)
	get_tree().paused = false
	palette.set_process(false)
	palette.advance_population(Vector3(0, 20, 0), 1.0)
	var resumed: Color = palette._materials[0].get_shader_parameter("palette_dark")
	_check(
		resumed.is_equal_approx(palette.settings.blue[0]),
		"The transition can finish after resuming."
	)
	palette.reset()


func _check_technology_accent(palette: Palette) -> void:
	var background: ShaderMaterial = palette.technology_background.material as ShaderMaterial
	_check(
		background.get_shader_parameter("population_palette_enabled") == true,
		"The production technology background enables dynamic recoloring."
	)
	var capture: bool = "--capture-technology" in OS.get_cmdline_user_args()
	var directory: String = (
		"res://artifacts/technology_accent_%d" % int(Time.get_unix_time_from_system())
	)
	if capture:
		DirAccess.make_dir_recursive_absolute(directory)
		print("Technology accent captures: ", directory)
	for species: int in range(3):
		palette.reset()
		palette.emphasize_species(species, 10.0)
		palette.advance_population(Vector3(200, 0, 0), palette.settings.transition_seconds)
		_check(palette.dominant_species == 0, "Temporary emphasis preserves population dominance.")
		var expected: PackedColorArray = palette.settings.colors_for(species)
		for index: int in range(Palette.PARAMETERS.size()):
			var applied: Color = background.get_shader_parameter(Palette.PARAMETERS[index])
			_check(
				applied.is_equal_approx(expected[index]),
				"Technology background follows every temporary accent color."
			)
		_demo._layout._show_technology()
		var frozen: Color = background.get_shader_parameter("palette_mid")
		var remaining: float = palette.accent_remaining
		palette.set_process(true)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(
			is_equal_approx(palette.accent_remaining, remaining)
			and (background.get_shader_parameter("palette_mid") as Color).is_equal_approx(frozen),
			"Opening technology preserves the active accent while gameplay is paused."
		)
		palette.set_process(false)
		if capture:
			_demo.run.candy = 1000
			if _demo.run.governance_level == 0:
				_demo.run.purchase_technology("cultivation")
			_demo.run.economy_changed.emit()
			_demo._layout._technology._show_details("giant")
			_check(
				_demo._layout._technology._detail_effect.text.contains("巨型只能用吸管收割"),
				"The visible giant research explains its capture restriction."
			)
			for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
				get_window().size = dimensions
				_demo._apply_layout()
				await _save(directory, "%d_technology_%d" % [species, dimensions.x])
		_demo._layout.close_panels()
		palette.advance_population(Vector3(200, 0, 0), 10.0)
		_check(
			palette.accent_species == -1
			and (background.get_shader_parameter("palette_mid") as Color).is_equal_approx(
				palette.settings.pink[1]
			),
			"Technology returns to the population color after temporary emphasis expires."
		)
	palette.reset()


func _capture_themes() -> void:
	var directory: String = "res://artifacts/population_palette_20261013"
	DirAccess.make_dir_recursive_absolute(directory)
	var palette: Palette = _demo._population_palette
	for species: int in range(3):
		_demo.restart_run()
		_demo.run.settings = _demo.run.settings.duplicate() as PrototypeSettings
		for kind: int in [NestState.Species.MUCUS, NestState.Species.DRILL, NestState.Species.DRILL]:
			_demo.run._pending_nest_species = kind
			_demo._on_nest_spawn_requested(kind as NestState.Species)
			for _frame: int in range(240):
				var delta: float = 0.05 * Engine.time_scale
				_demo._view._process(delta)
				_demo._nest_discovery._process(delta)
				if not _demo._view.presentation_locked:
					break
		palette.reset()
		_check(
			_demo.run.nests.size() == 5,
			"The production scene fits two drill nests alongside existing species."
		)
		for nest: NestState in _demo.run.nests:
			nest.level = 1 if nest.species == species else 0
			if species in [1, 2] and nest.species == species:
				nest.level = 2
			_demo._on_nest_changed(nest)
			_demo.run._advance_nest_population(nest, 120.0)
		for actor: PrototypeSlime in _demo._slimes:
			actor._process(2.0)
			actor.set_process(false)
		palette._process(2.5)
		_check(
			palette.dominant_species == species,
			"Real spawned populations choose the expected capture palette."
		)
		for button: IconButton in [
			_demo._layout.game_menu._pause,
			_demo._layout.game_menu._music,
			_demo._layout.game_menu._settings
		]:
			button.highlighted = true
			button.queue_redraw()
		_demo._pipe.hide()
		for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
			get_window().size = dimensions
			_demo._apply_layout()
			_demo._view.zoom_steps(1.0, false)
			await _save(directory, "%d_near_%d" % [species, dimensions.x])
			_demo._view.zoom_steps(-1.0, false)
			await _save(directory, "%d_overview_%d" % [species, dimensions.x])
			_demo._layout._show_technology()
			await _save(directory, "%d_technology_%d" % [species, dimensions.x])
			_demo._layout.close_panels()


func _save(directory: String, label: String) -> void:
	for frame: int in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(
		get_viewport().get_texture().get_image().save_png(directory + "/" + label + ".png") == OK,
		"Fresh runtime capture saved."
	)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
