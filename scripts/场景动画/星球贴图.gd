@tool
extends "res://scripts/场景动画/帧动画.gd"

@export var sprite: Sprite2D
@export var center_uv: Vector2 = Vector2(0.5, 0.5)
@export var radius_width_ratio: float = 0.4
@export var display_radius: float = 256.8


func _ready() -> void:
	if not Engine.is_editor_hint():
		super._ready()
	var texture_size: Vector2 = sprite.texture.get_size()
	var texture_scale: float = display_radius / (texture_size.x * radius_width_ratio)
	sprite.scale = Vector2.ONE * texture_scale
	sprite.position = -center_uv * texture_size * texture_scale
