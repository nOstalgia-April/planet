@tool
extends Node2D

const Layout = preload("res://scripts/overview_bubble_layout.gd")
const BACKGROUNDS: Array[Texture2D] = [
	preload("res://assets/monster_bubbles/slime_bubble.png"),
	preload("res://assets/monster_bubbles/mucus_bubble.png"),
	preload("res://assets/monster_bubbles/green_bubble.png")
]
const PORTRAITS: Array[Texture2D] = [
	preload("res://assets/monster_bubbles/slime_portrait.png"),
	preload("res://assets/monster_bubbles/mucus_portrait.png"),
	preload("res://assets/monster_bubbles/green_portrait.png")
]
const PORTRAIT_BOUNDS: Array[Rect2] = [
	Rect2(19, 31, 146, 109), Rect2(15, 22, 161, 123), Rect2(13, 17, 149, 130)
]

@export_enum("Slime", "Mucus", "Green") var species: int = 0
@export_range(16.0, 120.0) var preview_radius: float = 60.0
@export_range(0.5, 0.9, 0.01) var portrait_diameter_ratio: float = 0.76
@export_group("Hover")
@export_range(1.05, 1.6, 0.01) var hover_magnification: float = 1.28
@export_range(40.0, 300.0, 5.0) var hover_spring: float = 170.0
@export_range(5.0, 30.0, 0.5) var hover_damping: float = 17.0

var cluster: Layout.Cluster
var angle: float = 0.0
var radius_ratio: float = 0.0
var radius: float = 0.0
var opacity: float = 0.0
var anchor: Vector2 = Vector2.ZERO
var preferred: Vector2 = Vector2.ZERO
var offset: Vector2 = Vector2.ZERO
var display_radius: float = 0.0
var hover_scale: float = 1.0
var hover_velocity: float = 0.0
var motion_offset: Vector2 = Vector2.ZERO
var motion_velocity: Vector2 = Vector2.ZERO
var motion_initialized: bool = false

@onready var _background: Sprite2D = $Background
@onready var _portrait: Sprite2D = $Portrait


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	if Engine.is_editor_hint() or get_tree().current_scene == self:
		var center: Vector2 = (
			Vector2.ZERO if Engine.is_editor_hint() else get_viewport_rect().size * 0.5
		)
		show_at(
			center, center + Vector2.DOWN * preview_radius * Layout.POINTER_REACH, preview_radius
		)


func _process(_delta: float) -> void:
	show_at(Vector2.ZERO, Vector2.DOWN * preview_radius * Layout.POINTER_REACH, preview_radius)


func advance_hover(delta: float, hovered: bool) -> void:
	var target: float = hover_magnification if hovered else 1.0
	if absf(target - hover_scale) < 0.0001 and absf(hover_velocity) < 0.001:
		hover_scale = target
		hover_velocity = 0.0
		return
	hover_velocity += (target - hover_scale) * hover_spring * delta
	hover_velocity *= exp(-hover_damping * delta)
	hover_scale += hover_velocity * delta


func contains_viewport_point(point: Vector2, margin: float = 0.0) -> bool:
	var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * point
	var hit_radius: float = display_radius + margin
	return local_point.length_squared() <= hit_radius * hit_radius


func show_at(center: Vector2, surface_anchor: Vector2, body_radius: float) -> void:
	position = center
	anchor = surface_anchor
	radius = body_radius
	display_radius = radius * hover_scale
	_background.texture = BACKGROUNDS[species]
	_background.centered = false
	# Source circle center is (121,115), radius 97; the green cutout is shifted.
	var circle_center: Vector2 = Vector2(109, 116) if species == 2 else Vector2(121, 115)
	_background.offset = -circle_center
	_background.scale = Vector2.ONE * display_radius / 97.0
	_background.rotation = (anchor - position).angle() - PI * 0.5
	_portrait.texture = PORTRAITS[species]
	_portrait.centered = false
	var bounds: Rect2 = PORTRAIT_BOUNDS[species]
	_portrait.offset = -bounds.get_center()
	_portrait.scale = Vector2.ONE * display_radius * 2.0 * portrait_diameter_ratio / bounds.size.x
	_portrait.rotation = 0.0
