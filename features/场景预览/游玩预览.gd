extends "res://scripts/disk_demo.gd"

const BlendedPlanetArt = preload("res://scripts/场景动画/双视角星球.gd")
const PlanetRestoration = preload("res://scripts/planet_restoration.gd")
const PopulationPalette = preload("res://scripts/population_palette.gd")
const HorizonTerrain = preload("res://scripts/horizon_terrain.gd")
const NestDiscovery = preload("res://scripts/nest_discovery_presentation.gd")
const VictoryMeteors = preload("res://scripts/victory_meteor_presentation.gd")

@export var start_in_overview: bool = false

@onready var _horizon_terrain: HorizonTerrain = $World/HorizonTerrain
@onready var _near_background: Node2D = $美术背景/地壳裁剪/画布/近景背景
@onready var _overview_background: Node2D = $美术背景/地壳裁剪/画布/全景背景
@onready var _planet_art: BlendedPlanetArt = $World/PlanetSurface/星球画面
@onready var _restoration: PlanetRestoration = $PlanetRestoration
@onready var _population_palette: PopulationPalette = $PopulationPalette
@onready var _nest_discovery: NestDiscovery = $NestDiscoveryPresentation
@onready var _victory: VictoryMeteors = $VictoryMeteorPresentation


func _ready() -> void:
	_restoration.palette_changed.connect(_on_palette_changed)
	_victory.started.connect(_on_restoration_started)
	_victory.playback_started.connect(_on_victory_playback_started)
	super._ready()
	_completion.visibility_changed.connect(_sync_ending_art)
	flower_appeared.connect(_restoration.reveal_flower)
	_restoration.color_fill_started.connect(_planet_audio.color_recovered)
	_restoration.background_restore_started.connect(_planet_audio.planet_turned_white)
	_restoration.background_restore_finished.connect(_layout.show_final_cleanup_guide)
	_population_palette.display_species_changed.connect(_planet_audio.palette_changed_to)
	_restoration.presentation_started.connect(_on_restoration_started)
	_nest_discovery.presentation_started.connect(_on_restoration_started)
	_nest_discovery.presentation_started.connect(_monster_audio.new_nest_discovered)
	_horizon_terrain.popped.connect(_planet_audio.terrain_popped)
	_nest_discovery.emergence_progressed.connect(_on_emergence_progressed)
	_nest_discovery.rotation_guide_changed.connect(_layout.set_rotation_guide_visible)
	_view.view_changed.connect(_sync_art)
	_view.projection_changed.connect(_sync_art)
	RenderingServer.set_default_clear_color(Color.BLACK)
	if start_in_overview:
		_view.zoom_steps(-1.0, false)
	_sync_art()


# Read every frame rather than from start/finish signals, so a cancelled or
# reset presentation can never leave the music dipped.
func _process(delta: float) -> void:
	_sync_presentation_audio()
	super._process(delta)


func _sync_presentation_audio() -> void:
	var restoring: bool = _restoration.phase != PlanetRestoration.Phase.IDLE
	var discovering: bool = _nest_discovery.phase >= NestDiscovery.Phase.ANTICIPATE
	GameAudio.set_music_ducked(restoring or discovering)
	_planet_audio.zoom_sounds_muted = restoring
	_monster_audio.monster_sounds_muted = discovering


func _exit_tree() -> void:
	GameAudio.set_music_ducked(false)


func restart_run() -> void:
	_victory.reset()
	_nest_discovery.cancel()
	_monster_audio.stop_new_nest()
	_restoration.reset()
	super.restart_run()
	_population_palette.reset()
	_nest_discovery.reset()
	_horizon_terrain.replay()


func _present_discovered_nest(species: NestState.Species, nest_position: Vector2) -> void:
	_nest_discovery.request_discovery(species, nest_position)


func _on_emergence_progressed(nest_id: int, progress: float) -> void:
	_nest_views[nest_id - 1].set_emergence_progress(progress)
	for area: NestMucusArea in _nest_mucus_areas:
		if area.source_nest_id == nest_id:
			area.modulate.a = smoothstep(0.15, 0.8, progress)


func _on_restoration_started() -> void:
	_layout.close_panels()
	_clear_nest_selection()
	_cancel_view_drag()
	_capture_at(0.0, _tool_pointer, false)


func _on_palette_changed(progress: float) -> void:
	_candy_label.add_theme_color_override(
		"font_color", Color(0.9187172, 0.95208365, 0.92662764).lerp(Color("364b50"), progress)
	)


func _show_completion() -> void:
	if _victory.phase != VictoryMeteors.Phase.IDLE:
		return
	# A final capture can happen during the flower's growth animation.
	# Let all earned reveals finish before the victory panel covers the globe.
	var waiting_for_flower: bool = false
	for nest: NestState in run.nests:
		if nest.is_tamed and nest.species not in _restoration.unlocked_species:
			waiting_for_flower = true
	if (
		_restoration.phase != PlanetRestoration.Phase.IDLE
		or waiting_for_flower
		or _nest_discovery.phase != NestDiscovery.Phase.IDLE
		or _view.presentation_locked
	):
		if _completion_tween != null:
			_completion_tween.kill()
		_completion_tween = create_tween()
		_completion_tween.tween_interval(0.25)
		_completion_tween.tween_callback(_show_completion)
		return
	_victory.play()


func _on_victory_playback_started() -> void:
	_restoration.core.modulate.a = 0.0
	super._show_completion()


func set_opening_note_backdrop(enabled: bool) -> void:
	_near_background.get_node("星星").visible = not enabled
	_overview_background.get_node("星星").visible = not enabled
	_restoration.core.visible = not enabled
	_layout.game_menu.visible = not enabled
	_layout.get_node("Economy").visible = not enabled


func _sync_ending_art() -> void:
	# Keep the original drawing for credits without changing restoration or population colors.
	_planet_art.set_ending_presentation(_completion.visible)


func _sync_art() -> void:
	_horizon_terrain.set_surface_radius(_planet.radius * PlanetSurface.SURFACE_RADIUS_RATIO)
	_horizon_terrain.set_near_blend(_view.near_blend)
	_planet_art.set_zoom(_view.zoom_amount)
	_near_background.visible = _view.near_blend > 0.0
	_overview_background.visible = _view.near_blend < 1.0
	_overview_background.modulate.a = 1.0 - _view.near_blend


func _switch_view() -> void:
	_view.zoom_steps(1.0 if _view.is_overview() else -1.0)
