@tool
extends "res://scripts/场景动画/星球贴图.gd"

const FlowField = preload("res://scripts/paint_flow_field.gd")

@export var territory_color: Color = Color("ff709e"):
	set(value):
		territory_color = value
		_sync_material()
@export var mucus_color: Color = Color("5b61ff"):
	set(value):
		mucus_color = value
		_sync_material()
@export_range(0.0, 1.0, 0.01) var tint_strength: float = 1.0:
	set(value):
		tint_strength = value
		_sync_material()
@export_range(0.0, 1.0, 0.01) var claim_progress: float = 1.0:
	set(value):
		claim_progress = value
		_sync_material()
@export_range(0.0, 1.0, 0.01) var mucus_progress: float = 1.0:
	set(value):
		mucus_progress = value
		_sync_material()
@export var mucus_on_top: bool = true:
	set(value):
		mucus_on_top = value
		_sync_material()
@export var drip_progress: Vector2 = Vector2.ZERO:
	set(value):
		drip_progress = value
		_sync_material()
@export_range(0.45, 1.5, 0.05) var pink_size: float = 0.82:
	set(value):
		pink_size = value
		_queue_flow()
@export_range(0.45, 1.5, 0.05) var blue_size: float = 0.94:
	set(value):
		blue_size = value
		_queue_flow()
@export var pink_source: Vector2 = Vector2(-0.18, 0.02):
	set(value):
		pink_source = value
		_queue_flow()
@export var blue_source: Vector2 = Vector2(0.22, 0.03):
	set(value):
		blue_source = value
		_queue_flow()
@export var shape_seed: int = 12:
	set(value):
		shape_seed = value
		_queue_flow()

var flow_image: Image
var pink_drips: PackedVector4Array
var blue_drips: PackedVector4Array
var _flow_texture: ImageTexture
var _terrain: Image
var _rebuild_pending: bool = false


func _ready() -> void:
	super._ready()
	_terrain = sprite.texture.get_image()
	# The planet can use VRAM compression, but CPU flow sampling needs pixels.
	if _terrain.is_compressed():
		var error: Error = _terrain.decompress()
		if error != OK:
			push_error("无法解压地壳采样贴图：" + error_string(error))
			_terrain = null
			return
	_terrain.resize(512, roundi(512.0 * float(_terrain.get_height()) / float(_terrain.get_width())))
	rebuild_flow()


func _queue_flow() -> void:
	if not is_node_ready() or _rebuild_pending or _terrain == null:
		return
	_rebuild_pending = true
	rebuild_flow.call_deferred()


func rebuild_flow() -> void:
	_rebuild_pending = false
	if _terrain == null:
		push_error("地壳采样贴图未准备成功，无法重建染色流场。")
		return
	var builder: FlowField = FlowField.new()
	flow_image = builder.build(
		shape_seed,
		pink_source,
		blue_source,
		pink_size,
		blue_size,
		_terrain,
		center_uv,
		radius_width_ratio
	)
	_flow_texture = ImageTexture.create_from_image(flow_image)
	pink_drips = builder.pink_drips
	blue_drips = builder.blue_drips
	var shader_material: ShaderMaterial = sprite.material as ShaderMaterial
	shader_material.set_shader_parameter("flow_map", _flow_texture)
	shader_material.set_shader_parameter("pink_drips", pink_drips)
	shader_material.set_shader_parameter("blue_drips", blue_drips)
	shader_material.set_shader_parameter(
		"flow_bounds",
		Vector4(
			FlowField.BOUNDS.position.x,
			FlowField.BOUNDS.position.y,
			FlowField.BOUNDS.size.x,
			FlowField.BOUNDS.size.y
		)
	)
	_sync_material()


func _sync_material() -> void:
	if not is_node_ready():
		return
	var shader_material: ShaderMaterial = sprite.material as ShaderMaterial
	assert(shader_material != null, "地壳染色场景需要配置材质。")
	shader_material.set_shader_parameter("center_uv", center_uv)
	shader_material.set_shader_parameter("radius_width_ratio", radius_width_ratio)
	shader_material.set_shader_parameter("territory_color", territory_color)
	shader_material.set_shader_parameter("mucus_color", mucus_color)
	shader_material.set_shader_parameter("tint_strength", tint_strength)
	shader_material.set_shader_parameter("claim_progress", claim_progress)
	shader_material.set_shader_parameter("mucus_progress", mucus_progress)
	shader_material.set_shader_parameter("shape_seed", float(shape_seed))
	shader_material.set_shader_parameter("mucus_on_top", mucus_on_top)
	shader_material.set_shader_parameter("drip_progress", drip_progress)
