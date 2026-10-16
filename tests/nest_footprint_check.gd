extends Node

const NestScene: PackedScene = preload("res://scenes/world/nest.tscn")
const NestArt = preload("res://scripts/nest_art.gd")


func _ready() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var view: NestView = NestScene.instantiate() as NestView
	var art: NestArt = view.get_node("NestArt") as NestArt
	assert(not view.is_inside_tree())
	assert(art._texture_bounds.is_empty() and art._texture_feet.is_empty())
	var authored_width: float = art.maximum_footprint_width
	assert(is_equal_approx(authored_width, 325.0))
	assert(is_equal_approx(view.get_maximum_footprint_width(), authored_width * 1.05))
	view.art_settings = view.art_settings.duplicate() as ArtPresentationSettings
	view.art_settings.all_scale = 0.8
	view.art_settings.nest_scale = 1.2
	view.art_settings.nest_scales = view.art_settings.nest_scales.duplicate()
	view.art_settings.nest_scales[11] = 1.25
	assert(is_equal_approx(view.get_maximum_footprint_width(), authored_width * 1.2))
	art.maximum_footprint_width = 400.0
	assert(is_equal_approx(view.get_maximum_footprint_width(), 480.0))
	art.maximum_footprint_width = authored_width
	assert(
		art._texture_bounds.is_empty() and art._texture_feet.is_empty(),
		"Reading configured spacing must not scan images or initialize animation nodes."
	)
	add_child(view)
	var started: int = Time.get_ticks_usec()
	var measured_width: float = art.measure_maximum_footprint_width()
	var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	assert(
		is_equal_approx(authored_width, measured_width),
		"Animation art changed: update the configured footprint after checking nest spacing."
	)
	print(
		(
			"PASS: off-tree footprint, adjustable art/scales, no image reads; all-animation width %.0f matches authored data (measurement %.2f ms, %d textures)."
			% [measured_width, elapsed_ms, art._texture_bounds.size()]
		)
	)
	view.free()
	get_tree().quit()
