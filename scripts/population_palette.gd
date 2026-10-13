extends Node

const Settings = preload("res://scripts/population_palette_settings.gd")
const BottomDock = preload("res://scripts/ui/bottom_dock.gd")
const ART_SHADER: Shader = preload("res://shaders/population_art.gdshader")
const PARAMETERS: PackedStringArray = [
	"palette_dark", "palette_mid", "palette_ink", "palette_bright", "palette_light"
]

@export var settings: Settings
@export var run: PrototypeRun
@export var background_sprites: Array[Sprite2D] = []
@export var core_sprite: Sprite2D
@export var technology_background: ColorRect
@export var button_brushes: Array[TextureRect] = []
@export var ecology_backdrop: ColorRect
@export var bottom_dock: BottomDock

var dominant_species: int = NestState.Species.SLIME
var population_counts: Vector3 = Vector3.ZERO
var scores: Vector3 = Vector3.ZERO
var accent_species: int = -1
var accent_remaining: float = 0.0
var _display_species: int = NestState.Species.SLIME
var _candidate: int = -1
var _candidate_seconds: float = 0.0
var _transition_elapsed: float = 0.0
var _colors: PackedColorArray = PackedColorArray()
var _from_colors: PackedColorArray = PackedColorArray()
var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	assert(settings != null and run != null)
	assert(core_sprite != null and technology_background != null and ecology_backdrop != null)
	assert(background_sprites.size() == 2 and button_brushes.size() == 4)
	assert(settings.pink.size() == 5 and settings.blue.size() == 5 and settings.green.size() == 5)
	var artwork: ShaderMaterial = ShaderMaterial.new()
	artwork.shader = ART_SHADER
	_materials.append(artwork)
	for sprite: Sprite2D in background_sprites:
		sprite.material = artwork
	for brush: TextureRect in button_brushes:
		brush.material = artwork
	_materials.append(core_sprite.material as ShaderMaterial)
	_materials.append(technology_background.material as ShaderMaterial)
	for shader_material: ShaderMaterial in _materials:
		assert(shader_material != null)
		shader_material.set_shader_parameter("population_palette_enabled", true)
	reset()


func reset() -> void:
	dominant_species = NestState.Species.SLIME
	_display_species = dominant_species
	accent_species = -1
	accent_remaining = 0.0
	_candidate = -1
	_candidate_seconds = 0.0
	_transition_elapsed = settings.transition_seconds
	population_counts = Vector3.ZERO
	scores = Vector3.ZERO
	_colors = settings.colors_for(dominant_species).duplicate()
	_from_colors = _colors.duplicate()
	_apply_colors()


func emphasize_species(species: int, seconds: float) -> void:
	assert(species >= 0 and species < 3 and seconds >= 0.0)
	accent_species = species if seconds > 0.0 else -1
	accent_remaining = seconds
	_set_display_species(species if seconds > 0.0 else dominant_species)


func _set_display_species(species: int) -> void:
	if _display_species == species:
		return
	_display_species = species
	_from_colors = _colors.duplicate()
	_transition_elapsed = 0.0


func _process(delta: float) -> void:
	# Nest population includes underground drill monsters and all units in fused slimes.
	population_counts = Vector3.ZERO
	for nest: NestState in run.nests:
		population_counts[nest.species] += nest.alive_slimes
	advance_population(population_counts, delta)


func advance_population(counts: Vector3, delta: float) -> void:
	population_counts = counts
	scores = counts * settings.population_weights
	var winner: int = dominant_species
	for species: int in range(3):
		if scores[species] > scores[winner]:
			winner = species
	if (
		winner != dominant_species
		and scores[winner] > scores[dominant_species] * (1.0 + settings.lead_margin)
	):
		if _candidate != winner:
			_candidate = winner
			_candidate_seconds = 0.0
		_candidate_seconds += delta
		if _candidate_seconds >= settings.confirmation_seconds:
			dominant_species = winner
			_candidate = -1
			_candidate_seconds = 0.0
	else:
		_candidate = -1
		_candidate_seconds = 0.0
	# Keep the population decision current beneath the temporary discovery color.
	accent_remaining = maxf(0.0, accent_remaining - delta)
	if accent_remaining <= 0.0:
		accent_species = -1
	_set_display_species(accent_species if accent_species >= 0 else dominant_species)
	if _transition_elapsed >= settings.transition_seconds:
		return
	_transition_elapsed = minf(_transition_elapsed + delta, settings.transition_seconds)
	var progress: float = smoothstep(0.0, 1.0, _transition_elapsed / settings.transition_seconds)
	var target: PackedColorArray = settings.colors_for(_display_species)
	for index: int in range(5):
		_colors[index] = _from_colors[index].lerp(target[index], progress)
	_apply_colors()


func _apply_colors() -> void:
	for shader_material: ShaderMaterial in _materials:
		for index: int in range(PARAMETERS.size()):
			shader_material.set_shader_parameter(PARAMETERS[index], _colors[index])
	ecology_backdrop.color = _colors[0].darkened(0.65)
	if bottom_dock != null:
		bottom_dock.set_accent(_colors[1])
