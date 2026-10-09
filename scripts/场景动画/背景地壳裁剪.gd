extends Polygon2D

@export var planet_surface: PlanetSurface
@export var background_canvas: Node2D
@export var reference_size: Vector2 = Vector2(1920.0, 1080.0)


func _ready() -> void:
	assert(planet_surface != null, "背景裁剪缺少地壳轮廓。")
	assert(background_canvas != null, "背景裁剪缺少背景画布。")
	get_viewport().size_changed.connect(_sync_cutout)
	_sync_cutout()


func _process(_delta: float) -> void:
	_sync_cutout()


func _sync_cutout() -> void:
	var contour: PackedVector2Array = planet_surface.get_surface_polygon()
	if polygon != contour:
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
