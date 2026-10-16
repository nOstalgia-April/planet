extends Node

const POINTER: Texture2D = preload("res://assets/ui/technology/pointer.tres")
const HOTSPOT: Vector2 = Vector2(8.0, 1.0)
const OUTLINE_PADDING: int = 7
const ACCENT_UPDATE_SECONDS: float = 0.05
const DEFAULT_PALETTE = preload("res://resources/population_palette.tres")

var _vacuum: Node2D
var _pointer_image: Image
var _outline_alpha: PackedFloat32Array = PackedFloat32Array()
var _cursor_size: Vector2i
var _accent: Color
var _applied_accent: Color = Color.TRANSPARENT
var _accent_update_remaining: float = 0.0
var _cursor_texture: ImageTexture


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Read scripted resource defaults at runtime, after editor documentation parsing.
	var palette_colors: PackedColorArray = DEFAULT_PALETTE.colors_for(NestState.Species.SLIME)
	_accent = palette_colors[1]
	_prepare_outline()
	_apply_accent()


func set_accent(color: Color) -> void:
	_accent = color


func _prepare_outline() -> void:
	_pointer_image = POINTER.get_image()
	_pointer_image.convert(Image.FORMAT_RGBA8)
	_cursor_size = _pointer_image.get_size() + Vector2i.ONE * OUTLINE_PADDING * 2
	_outline_alpha.resize(_cursor_size.x * _cursor_size.y)
	# Build the soft silhouette once; palette transitions only recolor it.
	for y: int in range(_pointer_image.get_height()):
		for x: int in range(_pointer_image.get_width()):
			var alpha: float = _pointer_image.get_pixel(x, y).a
			if alpha <= 0.0:
				continue
			for dy: int in range(-OUTLINE_PADDING, OUTLINE_PADDING + 1):
				for dx: int in range(-OUTLINE_PADDING, OUTLINE_PADDING + 1):
					var distance: float = maxf(Vector2(dx, dy).length() - 1.0, 0.0)
					var coverage: float = alpha * exp(-distance * distance / 6.0) * 0.9
					var index: int = (
						(y + dy + OUTLINE_PADDING) * _cursor_size.x + x + dx + OUTLINE_PADDING
					)
					_outline_alpha[index] = maxf(_outline_alpha[index], coverage)


func _apply_accent() -> void:
	var image: Image = Image.create(_cursor_size.x, _cursor_size.y, false, Image.FORMAT_RGBA8)
	for y: int in range(_cursor_size.y):
		for x: int in range(_cursor_size.x):
			image.set_pixel(x, y, Color(_accent, _outline_alpha[y * _cursor_size.x + x]))
	image.blend_rect(
		_pointer_image,
		Rect2i(Vector2i.ZERO, _pointer_image.get_size()),
		Vector2i.ONE * OUTLINE_PADDING
	)
	_cursor_texture = ImageTexture.create_from_image(image)
	# Padding must move the hotspot too, keeping the original arrow tip under the mouse.
	for shape: int in range(Input.CURSOR_ARROW, Input.CURSOR_HELP + 1):
		Input.set_custom_mouse_cursor(
			_cursor_texture, shape, HOTSPOT + Vector2.ONE * OUTLINE_PADDING
		)
	_applied_accent = _accent
	_accent_update_remaining = ACCENT_UPDATE_SECONDS


func register_vacuum(vacuum: Node2D) -> void:
	_vacuum = vacuum


func _exit_tree() -> void:
	# Windows retains cursor textures until explicitly reset; its display server
	# otherwise drops them after RenderingServer has already been destroyed.
	for shape: int in range(Input.CURSOR_ARROW, Input.CURSOR_HELP + 1):
		Input.set_custom_mouse_cursor(null, shape)
	_vacuum = null


func _process(delta: float) -> void:
	_accent_update_remaining = maxf(0.0, _accent_update_remaining - delta)
	if _accent != _applied_accent and _accent_update_remaining <= 0.0:
		_apply_accent()
	var using_vacuum: bool = (
		is_instance_valid(_vacuum)
		and _vacuum.is_visible_in_tree()
		and not get_tree().paused
		and get_viewport().gui_get_hovered_control() == null
	)
	var mode: Input.MouseMode = (
		Input.MOUSE_MODE_HIDDEN if using_vacuum else Input.MOUSE_MODE_VISIBLE
	)
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode
