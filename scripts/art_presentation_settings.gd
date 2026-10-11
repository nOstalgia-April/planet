class_name ArtPresentationSettings
extends Resource

@export_group("统一调整")
@export_range(0.25, 2.0, 0.01) var all_scale: float = 1.0
@export_range(-30.0, 30.0, 0.25) var all_sink: float = 0.0
@export_range(0.25, 2.0, 0.01) var nest_scale: float = 1.0
@export_range(-30.0, 30.0, 0.25) var nest_sink: float = 0.0
@export_range(0.25, 2.0, 0.01) var monster_scale: float = 1.0
@export_range(-30.0, 30.0, 0.25) var monster_sink: float = 0.0
@export var curved_seating: bool = true
@export_range(0.1, 1.0, 0.05) var nest_bend_height_ratio: float = 0.35
@export_group("各巢穴：史莱姆、黏液、地鼠，每种四阶段")
@export var nest_scales: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
@export var nest_sinks: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
@export_group("各怪物：史莱姆、黏液、地鼠")
@export var monster_scales: Array[float] = [1.0, 1.0, 1.0]
@export var monster_sinks: Array[float] = [0.0, 0.0, 0.0]


func get_nest_scale(species: int, stage: int) -> float:
	return all_scale * nest_scale * nest_scales[species * 4 + stage]


func get_nest_sink(species: int, stage: int) -> float:
	return all_sink + nest_sink + nest_sinks[species * 4 + stage]


func get_monster_scale(species: int) -> float:
	return all_scale * monster_scale * monster_scales[species]


func get_monster_sink(species: int) -> float:
	return all_sink + monster_sink + monster_sinks[species]


func get_maximum_nest_scale() -> float:
	return all_scale * nest_scale * nest_scales.max()


func copy_from(source: ArtPresentationSettings) -> void:
	all_scale = source.all_scale
	all_sink = source.all_sink
	nest_scale = source.nest_scale
	nest_sink = source.nest_sink
	monster_scale = source.monster_scale
	monster_sink = source.monster_sink
	curved_seating = source.curved_seating
	nest_bend_height_ratio = source.nest_bend_height_ratio
	nest_scales = source.nest_scales.duplicate()
	nest_sinks = source.nest_sinks.duplicate()
	monster_scales = source.monster_scales.duplicate()
	monster_sinks = source.monster_sinks.duplicate()
	emit_changed()
