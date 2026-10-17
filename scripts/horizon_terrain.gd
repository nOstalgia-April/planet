extends Node2D

# The rocks (hills and peak) and the trees pop up; each plays its sound once.
signal popped(trees: bool)

# Trees are the last piece. Pop moments are seconds into "appear": the hills
# grow from the first frame, the trees start rising at their third frame (8 fps).
const TREE_PIECE: int = 3

@export var rock_pop_seconds: float = 0.0
@export var tree_pop_seconds: float = 0.25
@export var reference_radius: float = 1320.0
@export var surface_radius: float = 256.8
@export var pieces: Array[AnimatedSprite2D] = []
@export var color_progress: Vector3 = Vector3.ZERO

# Seconds since the last replay while visible; negative when no pop is pending.
var _pop_clock: float = -1.0
var _rocks_popped: bool = true
var _trees_popped: bool = true


func _ready() -> void:
	assert(reference_radius > 0.0 and not pieces.is_empty())
	set_surface_radius(surface_radius)
	for piece: AnimatedSprite2D in pieces:
		piece.material = piece.material.duplicate()
	_sync_colors()
	replay()


func _process(delta: float) -> void:
	if _pop_clock < 0.0 or not is_visible_in_tree():
		return
	_pop_clock += delta
	if not _rocks_popped and _pop_clock >= rock_pop_seconds:
		_rocks_popped = true
		popped.emit(false)
	if not _trees_popped and _pop_clock >= tree_pop_seconds:
		_trees_popped = true
		popped.emit(true)
	if _rocks_popped and _trees_popped:
		_pop_clock = -1.0


func set_color_progress(species: int, progress: float) -> void:
	color_progress[species] = clampf(progress, 0.0, 1.0)
	_sync_colors()


func reset_colors() -> void:
	color_progress = Vector3.ZERO
	_sync_colors()


func _sync_colors() -> void:
	for piece: AnimatedSprite2D in pieces:
		var paint: ShaderMaterial = piece.material as ShaderMaterial
		paint.set_shader_parameter("color_progress", color_progress)


func has_visible_color(species: int) -> bool:
	if not is_visible_in_tree() or modulate.a <= 0.0:
		return false
	var viewport_rect: Rect2 = get_viewport_rect()
	for index: int in range(pieces.size()):
		if species not in [[1], [0], [1, 2], [0]][index]:
			continue
		var piece: AnimatedSprite2D = pieces[index]
		var texture: Texture2D = piece.sprite_frames.get_frame_texture(piece.animation, piece.frame)
		var pixels: Image = texture.get_image()
		var screen_transform: Transform2D = piece.get_global_transform_with_canvas()
		# Check painted pixels, not transparent sprite bounds or the planet's hidden hemisphere.
		for y: int in range(0, pixels.get_height(), 8):
			for x: int in range(0, pixels.get_width(), 8):
				var pixel: Color = pixels.get_pixel(x, y)
				if pixel.a < 0.5 or pixel.r < 0.5:
					continue
				if index == 2 and (pixel.r > 0.8) != (species == 2):
					continue
				var point: Vector2 = Vector2(x, y)
				if to_local(piece.to_global(point)).length() <= reference_radius:
					continue
				if viewport_rect.has_point(screen_transform * point):
					return true
	return false


func set_surface_radius(value: float) -> void:
	surface_radius = value
	scale = Vector2.ONE * surface_radius / reference_radius


func set_near_blend(value: float) -> void:
	var was_visible: bool = visible
	modulate.a = clampf(value, 0.0, 1.0)
	visible = value > 0.0
	if visible and not was_visible:
		replay()
	elif not visible and was_visible:
		for piece: AnimatedSprite2D in pieces:
			piece.stop()
		_pop_clock = -1.0


func replay() -> void:
	for piece: AnimatedSprite2D in pieces:
		piece.stop()
		piece.play(&"appear")
	# Counted only while visible, so a replay hidden behind the overview stays silent.
	_pop_clock = 0.0
	_rocks_popped = false
	_trees_popped = false
