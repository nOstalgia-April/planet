extends Polygon2D

@export var planet_surface: PlanetSurface
@export var background_canvas: Node2D
@export var reference_size: Vector2 = Vector2(1920.0, 1080.0)
@export_range(0.0, 0.02, 0.001) var art_edge_overlap_ratio: float = 0.005

var _cutout_radius: float = -1.0


func _ready() -> void:
	assert(planet_surface != null, "背景裁剪缺少地壳轮廓。")
	assert(background_canvas != null, "背景裁剪缺少背景画布。")
	get_viewport().size_changed.connect(_sync_cutout)
	_sync_cutout()


func _process(_delta: float) -> void:
	_sync_cutout()


func _sync_cutout() -> void:
	# The artwork is circular; gameplay's irregular relief can extend beyond it
	# and expose the black clear color. Keep the mask just inside the opaque rim.
	var cutout_radius: float = (
		planet_surface.radius * PlanetSurface.SURFACE_RADIUS_RATIO * (1.0 - art_edge_overlap_ratio)
	)
	if not is_equal_approx(_cutout_radius, cutout_radius):
		_cutout_radius = cutout_radius
		var contour: PackedVector2Array = PackedVector2Array()
		for index in range(PlanetSurface.CONTOUR_STEPS):
			var angle: float = float(index) * TAU / float(PlanetSurface.CONTOUR_STEPS)
			contour.append(Vector2.from_angle(angle) * cutout_radius)
		polygon = contour
	var surface_transform: Transform2D = planet_surface.get_global_transform_with_canvas()
	if not transform.is_equal_approx(surface_transform):
		transform = surface_transform
	# The mask follows the planet, while the background stays fixed in the viewport.
	var canvas_transform: Transform2D = Transform2D(
		0.0, get_viewport_rect().size / reference_size, 0.0, Vector2.ZERO
	)
	if not background_canvas.global_transform.is_equal_approx(canvas_transform):
		background_canvas.global_transform = canvas_transform
