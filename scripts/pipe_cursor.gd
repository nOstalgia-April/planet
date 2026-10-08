extends Node2D

const SurfaceProjection = preload("res://scripts/surface_projection.gd")
const FrameArt = preload("res://scripts/场景动画/帧动画.gd")

@export_range(8.0, 40.0, 1.0) var radius: float = 24.0
@export_range(0.2, 1.0, 0.05) var feedback_scale: float = 0.55
@export_range(1.0, 2.0, 0.05) var particle_spread: float = 1.5
@export_range(0.1, 1.0, 0.01) var art_scale: float = 0.36
@export var mouth_pixel: Vector2 = Vector2(103.0, 190.0)
@export var ink: Color = Color("454944")
@export var accent: Color = Color("4c837c")
@export var active: bool = false

var _time: float = 0.0
var _mouth_local: Vector2 = Vector2.ZERO

@onready var _art_root: Node2D = $ArtRoot
@onready var _art: FrameArt = $ArtRoot/吸尘器


func _ready() -> void:
	_art.position = (Vector2(141.5, 143.0) - mouth_pixel) * art_scale
	_art.scale = Vector2.ONE * art_scale
	visibility_changed.connect(_sync_animation)
	_update_visual_compensation()
	_sync_animation()


func set_tool_state(tool_position: Vector2, mouth_position: Vector2, is_active: bool) -> void:
	position = tool_position
	if not tool_position.is_zero_approx():
		rotation = tool_position.angle() + PI
	_mouth_local = (mouth_position - tool_position).rotated(-rotation)
	if active != is_active:
		active = is_active
		_sync_animation()
	_update_visual_compensation()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_update_visual_compensation()
	if visible and active:
		queue_redraw()


func _sync_animation() -> void:
	if active and is_visible_in_tree():
		if not _art.animation_player.is_playing():
			_art.play()
	else:
		_art.seek_frame(0)


func _update_visual_compensation() -> void:
	var compensation: Transform2D = SurfaceProjection.get_visual_compensation(self)
	# Keep the illustrated tool upright while its suction mouth follows the world pointer.
	var screen_transform: Transform2D = get_global_transform_with_canvas() * compensation
	compensation *= Transform2D(-screen_transform.get_rotation(), Vector2.ZERO)
	compensation.origin = _mouth_local
	_art_root.transform = compensation


func _draw() -> void:
	if active:
		var feedback_radius: float = radius * feedback_scale
		draw_circle(_mouth_local, feedback_radius, Color(accent, 0.10))
		draw_arc(_mouth_local, feedback_radius, 0.0, TAU, 48, Color(accent, 0.65), 1.3, true)
		for particle_index: int in range(6):
			var angle: float = float(particle_index) * TAU / 6.0 + _time * 0.35
			var progress: float = fmod(_time * 1.4 + float(particle_index) / 6.0, 1.0)
			var distance: float = lerpf(feedback_radius * particle_spread, 3.0, progress)
			var direction: Vector2 = Vector2.from_angle(angle)
			var particle_point: Vector2 = _mouth_local + direction * distance
			draw_line(
				particle_point,
				particle_point + direction * 2.0,
				Color(accent, 0.35 + progress * 0.3),
				1.0,
				true
			)
