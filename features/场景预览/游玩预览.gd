extends "res://scripts/disk_demo.gd"

const BlendedPlanetArt = preload("res://scripts/场景动画/双视角星球.gd")
const PlanetRestoration = preload("res://scripts/planet_restoration.gd")
const PopulationPalette = preload("res://scripts/population_palette.gd")
const NestDiscovery = preload("res://scripts/nest_discovery_presentation.gd")

@export var start_in_overview: bool = false

@onready var _near_background: Node2D = $美术背景/地壳裁剪/画布/近景背景
@onready var _overview_background: Node2D = $美术背景/地壳裁剪/画布/全景背景
@onready var _planet_art: BlendedPlanetArt = $World/PlanetSurface/星球画面
@onready var _restoration: PlanetRestoration = $PlanetRestoration
@onready var _population_palette: PopulationPalette = $PopulationPalette
@onready var _nest_discovery: NestDiscovery = $NestDiscoveryPresentation


func _ready() -> void:
	_restoration.palette_changed.connect(_on_palette_changed)
	super._ready()
	flower_appeared.connect(_restoration.reveal_flower)
	_restoration.presentation_started.connect(_on_restoration_started)
	_nest_discovery.presentation_started.connect(_on_restoration_started)
	_nest_discovery.emergence_progressed.connect(_on_emergence_progressed)
	_view.view_changed.connect(_sync_art)
	_view.projection_changed.connect(_sync_art)
	RenderingServer.set_default_clear_color(Color.BLACK)
	if start_in_overview:
		_view.zoom_steps(-1.0, false)
	_sync_art()


func restart_run() -> void:
	_nest_discovery.cancel()
	_restoration.reset()
	super.restart_run()
	_population_palette.reset()
	_nest_discovery.reset()


func _present_discovered_nest(species: NestState.Species, position: Vector2) -> void:
	_nest_discovery.request_discovery(species, position)


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
	# A final capture can happen during the flower's growth animation.
	# Let all earned reveals finish before the victory panel covers the globe.
	var waiting_for_flower: bool = false
	for nest: NestState in run.nests:
		if nest.is_tamed and nest.species not in _restoration.unlocked_species:
			waiting_for_flower = true
	if _restoration.phase != PlanetRestoration.Phase.IDLE or waiting_for_flower:
		_completion_tween = create_tween()
		_completion_tween.tween_interval(0.25)
		_completion_tween.tween_callback(_show_completion)
		return
	super._show_completion()


func _sync_art() -> void:
	_planet_art.set_zoom(_view.zoom_amount)
	_near_background.visible = _view.near_blend > 0.0
	_overview_background.visible = _view.near_blend < 1.0
	_overview_background.modulate.a = 1.0 - _view.near_blend


func _switch_view() -> void:
	_view.zoom_steps(1.0 if _view.is_overview() else -1.0)
