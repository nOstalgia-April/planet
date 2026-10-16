extends Node2D

const Core = preload("res://scripts/planet_core_animation.gd")
const CORE_SCENE: PackedScene = preload("res://scenes/场景动画/星球核心.tscn")
const VARIANT_SHADER: Shader = preload(
	"res://features/core_texture_preview/core_texture_variants.gdshader"
)
const BRUSH_TEXTURE: Texture2D = preload("res://assets/场景动画/星球核心/core_brush_reference.jpg")
const PAPER_TEXTURE: Texture2D = preload("res://assets/场景动画/星球复色/亮色背景/未命名作品-1.png")
const OUTPUT_SIZE: Vector2i = Vector2i(1680, 600)
const MAGNIFICATION: float = 2.7
const FRAMES_PER_SECOND: float = 30.0

@export var autoplay: bool = true
@export var first_frame: int = 30
@export var last_frame: int = 149

var current_frame: int = -1
var cores: Array[Core] = []
var _materials: Array[ShaderMaterial] = []
var _surface: SubViewport
var _elapsed_seconds: float = 0.0


func _ready() -> void:
	assert(first_frame >= 0 and last_frame >= first_frame)
	get_window().mode = Window.MODE_WINDOWED
	get_window().content_scale_size = OUTPUT_SIZE
	get_window().size = OUTPUT_SIZE
	_surface = SubViewport.new()
	_surface.size = OUTPUT_SIZE
	_surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_surface)
	var background: ColorRect = ColorRect.new()
	background.size = Vector2(OUTPUT_SIZE)
	background.color = Color("e8e4e0")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(background)
	for variant: int in range(3):
		_create_variant(variant)
	var display: Sprite2D = Sprite2D.new()
	display.centered = false
	display.texture = _surface.get_texture()
	add_child(display)
	set_process(autoplay)
	seek_frame(first_frame)


func _create_variant(variant: int) -> void:
	var core: Core = CORE_SCENE.instantiate() as Core
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = VARIANT_SHADER
	material.set_shader_parameter("variant_mode", variant)
	material.set_shader_parameter("core_brush_texture", BRUSH_TEXTURE)
	material.set_shader_parameter("core_paper_texture", PAPER_TEXTURE)
	material.set_shader_parameter("outer_deformation", 0.5)
	material.set_shader_parameter("population_palette_enabled", false)
	var sprite: Sprite2D = core.get_node("画面") as Sprite2D
	sprite.material = material
	core.synchronize_music = false
	_surface.add_child(core)
	core.set_process(false)
	core.scale = Vector2.ONE * MAGNIFICATION
	var center: Vector2 = Vector2((float(variant) + 0.5) * 560.0, 300.0)
	core.position = center - (Vector2(178.0, 164.5) - core.clip.pivot) * MAGNIFICATION
	cores.append(core)
	_materials.append(material)


func _process(delta: float) -> void:
	_elapsed_seconds += delta
	var duration_frames: int = last_frame - first_frame + 1
	var frame: int = (
		first_frame + int(floor(_elapsed_seconds * FRAMES_PER_SECOND)) % duration_frames
	)
	seek_frame(frame)


## Keep the last complete view while a page loads; all three columns render together.
func seek_frame(frame: int) -> bool:
	_surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var ready: bool = true
	for core: Core in cores:
		core._poll_pages()
		core.seek_seconds((float(frame) + 0.01) / FRAMES_PER_SECOND)
		if core.current_frame != frame:
			ready = false
	if not ready:
		return false
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("motion_seconds", float(frame) / FRAMES_PER_SECOND)
	current_frame = frame
	_surface.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true


func capture_image() -> Image:
	return _surface.get_texture().get_image()
