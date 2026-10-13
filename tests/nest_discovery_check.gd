extends Node

const Play = preload("res://features/场景预览/游玩预览.gd")
const PLAY: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const Discovery = preload("res://scripts/nest_discovery_presentation.gd")
const Restoration = preload("res://scripts/planet_restoration.gd")

var _game: Play
var _failures: Array[String] = []
var _reveal_count: int = 0
var _capture_directory: String = ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 800)
	_game = PLAY.instantiate() as Play
	add_child(_game)
	for node: Node in [
		_game, _game._view, _game._population_palette, _game._nest_discovery, _game._restoration
	]:
		node.set_process(false)
	_game._nest_discovery.nest_revealed.connect(_on_revealed)
	_game.run.nest_added.connect(_on_added)
	_check_sequence_and_triggers()
	await _check_pause_and_accent()
	_check_serial_presentations()
	_check_cancellation()
	if "--capture" in OS.get_cmdline_user_args():
		_capture_directory = (
			"res://artifacts/nest_emergence_%d" % int(Time.get_unix_time_from_system())
		)
		DirAccess.make_dir_recursive_absolute(_capture_directory)
		await _capture_sequence()
	_game.restart_run()
	_request(NestState.Species.MUCUS)
	_step(0.5)
	_game.queue_free()
	await get_tree().process_frame
	_check(is_equal_approx(Engine.time_scale, 1.0), "Scene exit restores the global time scale.")
	if _failures.is_empty():
		print(
			"PASS: phased discovery, emergence, delayed production, triggers, pause and cancellation"
		)
	else:
		for failure: String in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _request(species: NestState.Species) -> void:
	_game.run._pending_nest_species = species
	_game._on_nest_spawn_requested(species)


func _step(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.00001:
		var delta: float = minf(remaining, 0.025) * Engine.time_scale
		_game._view._process(delta)
		_game._nest_discovery._process(delta)
		if not _capture_directory.is_empty():
			_game._population_palette._process(delta)
		remaining -= 0.025


func _until(target: Discovery.Phase) -> void:
	for _frame: int in range(600):
		if _game._nest_discovery.phase == target:
			return
		_step(0.025)
	_check(false, "Discovery reaches phase %d." % target)


func _on_revealed(_nest_id: int, _species: int) -> void:
	_reveal_count += 1


func _on_added(nest: NestState) -> void:
	if not nest.is_discovering:
		return
	_check(not _game._view.is_transitioning(), "Nest creation waits for camera arrival.")
	_check(
		is_equal_approx(
			_game._view.presentation_magnification, _game._nest_discovery.closeup_magnification
		),
		"Nest creation waits for the closeup."
	)
	_check(
		absf(angle_difference(nest.position.angle() + _game._world.rotation, -PI / 2.0)) < 0.001,
		"The new nest is centered on the near horizon."
	)


func _check_sequence_and_triggers() -> void:
	var discovery: Discovery = _game._nest_discovery
	_check(discovery.discovered_species == [0], "Opening nests seed known species.")
	_check(discovery.phase == Discovery.Phase.IDLE, "Opening nests do not trigger discovery.")
	_request(NestState.Species.SLIME)
	_check(discovery.bubble.visible, "The species cue appears before the camera moves.")
	_check(_game._view.presentation_locked, "Discovery locks camera and capture input.")
	_game._view.zoom_steps(-1.0)
	_game._view.begin_drag(Vector2(600, 300))
	_check(not _game._view.is_dragging(), "Input cannot interrupt discovery.")
	var start_rotation: float = _game._world.rotation
	var start_color: float = discovery.bubble.density
	_step(0.625)
	_check(is_equal_approx(Engine.time_scale, 0.18), "Anticipation slows the world to 18 percent.")
	_check(discovery.bubble.density != start_color, "The species bubble flashes its background.")
	_step(0.35)
	_check(discovery.phase == Discovery.Phase.ANTICIPATE, "The warning lasts a full real second.")
	_check(
		is_equal_approx(start_rotation, _game._world.rotation), "Camera holds during anticipation."
	)
	_check(_game.run.nests.size() == 2, "The site remains empty during the warning.")
	_until(Discovery.Phase.TURN)
	_check(
		is_equal_approx(Engine.time_scale, 1.0), "Camera travel restores the previous time scale."
	)
	_step(0.4)
	_check(_game._view.is_transitioning(), "Camera rotation has a continuous travel phase.")
	_check(is_equal_approx(_game._view.presentation_magnification, 1.0), "Rotation precedes zoom.")
	_until(Discovery.Phase.LAND)
	_check(_game.run.nests.size() == 2, "The bubble lands before nest creation.")
	var anchor: Vector2 = _game._world.get_global_transform_with_canvas() * discovery._position
	_check(
		discovery.bubble.anchor.distance_to(anchor) < 0.1, "Landed bubble points at the real site."
	)
	_until(Discovery.Phase.RISE)
	var nest: NestState = _game.run.nests.back()
	var nest_view: NestView = _game._nest_views.back()
	_check(
		nest.is_discovering and nest_view.emergence_progress == 0.0, "New art begins underground."
	)
	_game.run._advance_nest_population(nest, 20.0)
	_check(
		nest.alive_slimes == 0 and nest.spawn_clock == 0.0, "Emerging nests cannot produce early."
	)
	_step(0.35)
	_check(
		nest_view.emergence_progress > 0.0 and nest_view.emergence_progress < 1.0,
		"The rise advances the shader continuously."
	)
	_until(Discovery.Phase.RECOVER)
	_check(nest_view.emergence_progress == 1.0, "The shader restores the full original artwork.")
	_game.run._advance_nest_population(nest, 20.0)
	_check(nest.alive_slimes == 0, "Production remains blocked during camera recovery.")
	var final_heading: float = _game._world.rotation
	_until(Discovery.Phase.IDLE)
	_check(not nest.is_discovering and nest.spawn_clock == 0.0, "Production starts after recovery.")
	_check(
		is_equal_approx(_game._view.presentation_magnification, 1.0),
		"Recovery ends at normal distance."
	)
	_check(is_equal_approx(final_heading, _game._world.rotation), "Recovery stays at the new nest.")
	_check(
		not _game._view.presentation_locked and not discovery.bubble.visible,
		"Presentation cleans up."
	)
	_game.run._advance_nest_population(nest, _game.run.get_nest_spawn_interval(nest.nest_id) + 0.01)
	_check(nest.alive_slimes > 0, "The nest produces normally after recovery.")
	_check(_reveal_count == 1, "First new slime nest receives one reveal.")
	_request(NestState.Species.SLIME)
	_check(
		_game.run.nests.size() == 4 and _reveal_count == 1, "Later known species appear normally."
	)
	for species: int in [NestState.Species.MUCUS, NestState.Species.DRILL]:
		_game._view.zoom_steps(-1.0, false)
		_request(species as NestState.Species)
		_until(Discovery.Phase.LAND)
		_check(
			_game._view.is_overview(), "An overview start rotates before pushing into near view."
		)
		_until(Discovery.Phase.IDLE)
		_check(not _game._view.is_overview(), "New species ends in near view.")
		_check(_game._population_palette.accent_species == species, "Each species gets its accent.")
	_check(_reveal_count == 3, "Each newly discovered species receives one reveal.")


func _check_pause_and_accent() -> void:
	var palette: Play.PopulationPalette = _game._population_palette
	palette.advance_population(Vector3(200, 0, 0), 9.99)
	_check(palette.accent_species == 2, "The green accent lasts through 9.99 seconds.")
	palette.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.05, true, false, true).timeout
	_check(is_equal_approx(palette.accent_remaining, 0.01), "Pause freezes the accent timer.")
	get_tree().paused = false
	palette.set_process(false)
	palette.advance_population(Vector3(200, 0, 0), 1.0)
	_check(palette.accent_species == -1, "Accent expires after ten seconds.")
	_check(
		palette._colors[0].is_equal_approx(palette.settings.pink[0]),
		"Population regains the palette."
	)
	for target: Discovery.Phase in [Discovery.Phase.ANTICIPATE, Discovery.Phase.RISE]:
		_game.restart_run()
		_request(NestState.Species.MUCUS)
		_until(target)
		_step(0.2)
		var elapsed: float = _game._nest_discovery._elapsed
		_game._view.set_process(true)
		_game._nest_discovery.set_process(true)
		get_tree().paused = true
		await get_tree().create_timer(0.05, true, false, true).timeout
		_check(
			is_equal_approx(elapsed, _game._nest_discovery._elapsed),
			"Pause freezes discovery phases."
		)
		get_tree().paused = false
		_game._view.set_process(false)
		_game._nest_discovery.set_process(false)
	_game.restart_run()


func _finish_restoration() -> void:
	for _frame: int in range(20):
		_game._view._process(1.0)
		_game._restoration._process(1.0)
		if _game._restoration.phase == Restoration.Phase.IDLE:
			return
	_check(false, "Restoration completes its queued presentation.")


func _check_serial_presentations() -> void:
	_game._restoration.reveal_flower(1, 0)
	_request(NestState.Species.MUCUS)
	_step(1.0)
	_check(
		_game._nest_discovery.phase == Discovery.Phase.WAITING,
		"Discovery waits behind restoration."
	)
	_check(
		is_equal_approx(Engine.time_scale, 1.0),
		"Waiting discovery does not slow another presentation."
	)
	_finish_restoration()
	_until(Discovery.Phase.IDLE)
	_game.restart_run()
	_request(NestState.Species.MUCUS)
	_game._restoration.reveal_flower(1, 0)
	_game._restoration._process(1.0)
	_check(
		_game._restoration.phase == Restoration.Phase.IDLE, "Restoration waits behind discovery."
	)
	_until(Discovery.Phase.RISE)
	_request(NestState.Species.DRILL)
	_check(_game.run.nests.size() == 3, "Rapid new species waits through the previous rise.")
	_until(Discovery.Phase.ANTICIPATE)
	_check(_game.run.nests.size() == 3, "Queued species receives its own warning.")
	_until(Discovery.Phase.IDLE)
	_check(_game.run.nests.size() == 4, "Queued species completes its own reveal.")
	_game._restoration._process(0.0)
	_check(
		_game._restoration.phase == Restoration.Phase.CONFIRM, "Restoration starts after discovery."
	)
	_finish_restoration()


func _check_cancellation() -> void:
	for target: Discovery.Phase in [
		Discovery.Phase.ANTICIPATE,
		Discovery.Phase.TURN,
		Discovery.Phase.LAND,
		Discovery.Phase.ZOOM,
		Discovery.Phase.RISE,
		Discovery.Phase.RECOVER
	]:
		_game.restart_run()
		_request(NestState.Species.MUCUS)
		_until(target)
		_step(0.05)
		_game.restart_run()
		_check(_game.run.nests.size() == 2, "Restart removes unfinished discoveries.")
		_check(
			is_equal_approx(Engine.time_scale, 1.0), "Restart restores time scale from every phase."
		)
		_check(not _game._view.presentation_locked, "Restart releases the camera lock.")
		_check(
			is_equal_approx(_game._view.presentation_magnification, 1.0), "Restart clears closeup."
		)
		_check(not _game._nest_discovery.first_discovery_shown, "Restart rearms discovery.")
	_request(NestState.Species.MUCUS)
	_game.run._pending_nest_species = -1
	_until(Discovery.Phase.IDLE)
	_check(
		not _game._nest_discovery.first_discovery_shown,
		"Failed resolution does not consume discovery."
	)
	_request(NestState.Species.MUCUS)
	_step(0.5)
	_game.run.is_complete = true
	_step(0.05)
	_check(
		not _game._view.presentation_locked and Engine.time_scale == 1.0,
		"Completion cancels slowdown."
	)
	_game.restart_run()
	Engine.time_scale = 0.75
	_request(NestState.Species.MUCUS)
	_until(Discovery.Phase.IDLE)
	_check(is_equal_approx(Engine.time_scale, 0.75), "Discovery preserves an existing time scale.")
	Engine.time_scale = 1.0
	_game.restart_run()


func _capture_sequence() -> void:
	for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_window().size = dimensions
		_game._apply_layout()
		for species: int in range(3):
			_game.restart_run()
			_game._site_random.seed = 173 + species
			_game._pipe.hide()
			if species == 1:
				_game._view.zoom_steps(-1.0, false)
			_request(species as NestState.Species)
			_step(0.65)
			await _save("%d_%d_1_warning" % [dimensions.x, species])
			_until(Discovery.Phase.TURN)
			_step(0.45)
			await _save("%d_%d_2_turn" % [dimensions.x, species])
			_until(Discovery.Phase.LAND)
			await _save("%d_%d_3_landed" % [dimensions.x, species])
			_until(Discovery.Phase.RISE)
			_step(0.18)
			await _save("%d_%d_4_rise_start" % [dimensions.x, species])
			_step(0.14)
			await _save("%d_%d_5_rise_middle" % [dimensions.x, species])
			_step(0.26)
			await _save("%d_%d_6_rise_top" % [dimensions.x, species])
			_until(Discovery.Phase.IDLE)
			await _save("%d_%d_7_recovered" % [dimensions.x, species])
	print("CAPTURES: ", ProjectSettings.globalize_path(_capture_directory))


func _save(label: String) -> void:
	for _frame: int in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(
		(
			get_viewport().get_texture().get_image().save_png(
				_capture_directory + "/" + label + ".png"
			)
			== OK
		),
		"Fresh screenshot saved."
	)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
