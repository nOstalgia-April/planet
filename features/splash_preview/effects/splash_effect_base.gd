class_name SplashEffectBase
extends Node2D

@export_range(0.2, 4.0, 0.05) var duration: float = 1.6
@export_range(24.0, 480.0, 1.0) var display_size: float = 180.0
@export var tint: Color = Color("fb005a")
@export_range(0.0, 2.0, 0.05) var intensity: float = 1.0
@export var preview_autoplay: bool = false

var _elapsed: float = 0.0
var _body_material: ShaderMaterial

@onready var _body: Sprite2D = $Body


func _ready() -> void:
	assert(_body.texture != null, "Splash effect requires its transparent drawing canvas.")
	_body_material = _body.material.duplicate() as ShaderMaterial
	_body.material = _body_material
	_elapsed = duration
	_apply_pose(1.0)
	set_process(false)
	if preview_autoplay:
		play()


func _process(delta: float) -> void:
	_elapsed = minf(_elapsed + delta, duration)
	_apply_pose(_elapsed / duration)
	if _elapsed >= duration:
		set_process(false)


func set_tint(color: Color) -> void:
	tint = color
	if is_node_ready():
		_apply_pose(_elapsed / duration)


func set_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 2.0)
	if is_node_ready():
		_apply_pose(_elapsed / duration)


func play() -> void:
	_elapsed = 0.0
	_apply_pose(0.0)
	set_process(true)


func seek(seconds: float) -> void:
	_elapsed = clampf(seconds, 0.0, duration)
	set_process(false)
	_apply_pose(_elapsed / duration)


func _apply_pose(progress: float) -> void:
	# The 66 px source region contains a 45 px silhouette; size measures that silhouette.
	var canvas_size: float = display_size * 66.0 / 45.0
	_body.scale = Vector2.ONE * canvas_size / float(_body.texture.get_width())
	_body_material.set_shader_parameter("progress", progress)
	_body_material.set_shader_parameter("intensity", intensity)
	_body_material.set_shader_parameter("tint", tint)
