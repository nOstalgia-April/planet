@tool
extends "res://scripts/场景动画/星球贴图.gd"

@export var overview_frames: Array[Texture2D] = []
@export var restored_frames: Array[Texture2D] = []
@export var color_layers: Array[Texture2D] = []
@export var overview_center_uv: Vector2 = Vector2(0.495104, 0.510278)
@export var overview_radius_width_ratio: float = 0.19375
@export_range(-180.0, 180.0, 0.1) var overview_heading_degrees: float = 90.0
@export_range(0.0, 1.0, 0.01) var blend_start_zoom: float = 0.28
@export_range(0.0, 1.0, 0.01) var blend_end_zoom: float = 0.02

var overview_mix: float = 0.0
var _overview_frame: int = -1
var _blend_material: ShaderMaterial
var color_progress: Vector3 = Vector3.ZERO
var restored_mix: float = 0.0


func _ready() -> void:
	super._ready()
	assert(not overview_frames.is_empty())
	assert(blend_start_zoom > blend_end_zoom)
	_blend_material = sprite.material as ShaderMaterial
	assert(_blend_material != null)
	assert(color_layers.size() == 3 and restored_frames.size() == 3)
	_blend_material.set_shader_parameter("pink_land", color_layers[0])
	_blend_material.set_shader_parameter("blue_land", color_layers[1])
	_blend_material.set_shader_parameter("green_land", color_layers[2])
	var near_size: Vector2 = sprite.texture.get_size()
	var overview_size: Vector2 = overview_frames[0].get_size()
	_blend_material.set_shader_parameter("near_center_uv", center_uv)
	_blend_material.set_shader_parameter(
		"near_radius_uv", Vector2(1.0, near_size.x / near_size.y) * radius_width_ratio
	)
	_blend_material.set_shader_parameter("overview_center_uv", overview_center_uv)
	_blend_material.set_shader_parameter(
		"overview_radius_uv",
		Vector2(1.0, overview_size.x / overview_size.y) * overview_radius_width_ratio
	)
	_blend_material.set_shader_parameter("overview_heading", deg_to_rad(overview_heading_degrees))
	set_zoom(1.0)
	animation_player.assigned_animation = clip
	if not Engine.is_editor_hint():
		play()
	_sync_overview_frame()


func _process(_delta: float) -> void:
	_sync_overview_frame()
	var center: Vector2 = get_global_transform_with_canvas().origin
	var radius: float = display_radius * get_global_transform_with_canvas().x.length() * 1.18
	_blend_material.set_shader_parameter(
		"reveal_screen_y",
		Vector2(center.y - radius, center.y + radius) / get_viewport_rect().size.y
	)


func set_color_progress(species: int, progress: float) -> void:
	color_progress[species] = clampf(progress, 0.0, 1.0)
	_blend_material.set_shader_parameter("land_progress", color_progress)


func set_restored_mix(value: float) -> void:
	restored_mix = clampf(value, 0.0, 1.0)
	_blend_material.set_shader_parameter("restored_mix", restored_mix)


func reset_colors() -> void:
	for species: int in range(3):
		set_color_progress(species, 0.0)
	set_restored_mix(0.0)


func set_zoom(zoom: float) -> void:
	# Use camera position, not elapsed time: reversing or resizing cannot pop the artwork.
	overview_mix = 1.0 - smoothstep(blend_end_zoom, blend_start_zoom, zoom)
	_blend_material.set_shader_parameter("overview_mix", overview_mix)


func _sync_overview_frame() -> void:
	# Both sequences share the existing clock; the three-frame overview loops twice
	# during the six-frame near clip. A view change never starts another clock.
	var frame: int = (
		int(floor(animation_player.current_animation_position * frames_per_second + 0.00001))
		% overview_frames.size()
	)
	if frame == _overview_frame:
		return
	_overview_frame = frame
	_blend_material.set_shader_parameter("overview_texture", overview_frames[frame])
	_blend_material.set_shader_parameter("restored_texture", restored_frames[frame])
