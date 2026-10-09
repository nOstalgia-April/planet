class_name CaptureNet
extends Node2D

const SurfaceProjection = preload("res://scripts/surface_projection.gd")
const FrameArt = preload("res://scripts/场景动画/帧动画.gd")
const REFERENCE_RADIUS: float = 84.0

enum Presentation { PREVIEW, CAST, OPEN, CARRIED, RESULT, COOLDOWN }

@export_range(0.05, 0.6, 0.01) var cast_seconds: float = 0.18
@export_range(0.1, 1.5, 0.01) var close_seconds: float = 0.35
@export_range(8.0, 160.0, 0.1) var preview_radius: float = 33.6
@export_range(0.1, 0.6, 0.01) var result_flash_seconds: float = 0.30
@export var ink: Color = Color("454944")
@export var accent: Color = Color("7b9c83")

var _presentation: Presentation = Presentation.PREVIEW
var _radius: float = 33.6
var _progress: float = 0.0
var _cooldown_progress: float = 0.0
var _result_age: float = 0.0
var _result_count: int = 0

@onready var _rim: Line2D = $Rim
@onready var _art_root: Node2D = $ArtRoot
@onready var _art: FrameArt = $ArtRoot/捕网
@onready var _label_compensation: Node2D = $LabelCompensation
@onready var _collected_label: Label = %CollectedLabel
@onready var _result_ring: Line2D = $ResultRing
@onready var _result_label: Label = %ResultCount
@onready var _cooldown_label: Label = %CooldownLabel


func _ready() -> void:
	show_preview(position, preview_radius)


func _process(delta: float) -> void:
	_update_visual_compensation()
	if _presentation == Presentation.RESULT:
		_result_age += delta
		_update_result_ring()
	queue_redraw()


func _update_visual_compensation() -> void:
	var compensation: Transform2D = SurfaceProjection.get_visual_compensation(self)
	var screen_transform: Transform2D = get_global_transform_with_canvas() * compensation
	# The net lies on the ground, so it shares the projected capture footprint.
	_art_root.transform = Transform2D.IDENTITY
	_label_compensation.transform = (
		compensation
		* Transform2D(
			-screen_transform.get_rotation(),
			Vector2.ONE * _radius / REFERENCE_RADIUS,
			0.0,
			Vector2.ZERO
		)
	)


func show_preview(pointer: Vector2, radius: float) -> void:
	_present(Presentation.PREVIEW, pointer, radius, 0.0)


func show_cast(cast_position: Vector2, radius: float, progress: float) -> void:
	_present(Presentation.CAST, cast_position, radius, progress)


func show_open(anchor: Vector2, radius: float, close_progress: float) -> void:
	_present(Presentation.OPEN, anchor, radius, close_progress)


func show_carried(pointer: Vector2, collected_count: int) -> void:
	_present(Presentation.CARRIED, pointer, _radius, 1.0)
	_collected_label.text = str(collected_count)
	_collected_label.visible = collected_count > 0


func show_result(anchor: Vector2, caught_count: int) -> void:
	if _presentation != Presentation.RESULT or position != anchor or _result_count != caught_count:
		_result_age = 0.0
	_result_count = caught_count
	_present(Presentation.RESULT, anchor, _radius, 1.0)
	_result_label.text = str(maxi(0, caught_count))
	_result_label.visible = true
	_update_result_ring()


func show_cooldown(pointer: Vector2, radius: float, remaining: float, total: float) -> void:
	_present(Presentation.COOLDOWN, pointer, radius, 0.0)
	_cooldown_progress = clampf(1.0 - remaining / maxf(total, 0.01), 0.0, 1.0)
	_cooldown_label.text = "%.1f" % maxf(0.0, remaining)
	_cooldown_label.visible = true
	queue_redraw()


func _present(mode: Presentation, pointer: Vector2, radius: float, progress: float) -> void:
	position = pointer
	_presentation = mode
	_radius = radius
	_update_visual_compensation()
	_progress = clampf(progress, 0.0, 1.0)
	visible = true
	_collected_label.visible = false
	_result_ring.visible = mode == Presentation.RESULT
	_result_label.visible = false
	_cooldown_label.visible = false
	_rim.visible = mode in [Presentation.PREVIEW, Presentation.COOLDOWN]
	_sync_art()
	var display_radius: float = _display_radius()
	var rim_points: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(65):
		rim_points.append(Vector2.from_angle(TAU * float(point_index) / 64.0) * display_radius)
	_rim.points = rim_points
	_rim.width = 2.2 * _radius / REFERENCE_RADIUS
	_result_ring.width = 3.0 * _radius / REFERENCE_RADIUS
	_rim.default_color = Color(
		ink, 0.25 if mode in [Presentation.PREVIEW, Presentation.COOLDOWN] else 0.85
	)

	queue_redraw()


func _display_radius() -> float:
	var detail_scale: float = _radius / REFERENCE_RADIUS
	match _presentation:
		Presentation.PREVIEW, Presentation.COOLDOWN:
			return _radius
		Presentation.CAST:
			return lerpf(9.0 * detail_scale, _radius, ease(_progress, 0.55))
		Presentation.OPEN:
			return lerpf(_radius, 12.0 * detail_scale, _progress)
		_:
			return 12.0 * detail_scale


func _sync_art() -> void:
	_art_root.visible = _presentation != Presentation.RESULT
	var frame: int = 4
	var size_ratio: float = 1.0
	var opacity: float = 1.0
	match _presentation:
		Presentation.PREVIEW:
			opacity = 0.55
		Presentation.COOLDOWN:
			opacity = 0.20
		Presentation.CAST:
			frame = mini(2, floori(_progress * 3.0))
		Presentation.OPEN:
			frame = 3 if _progress < 0.35 else 4
			size_ratio = lerpf(1.0, 0.14, ease(_progress, 2.0))
		Presentation.CARRIED:
			size_ratio = 0.25
	# Phase-driven frames stay synchronized with the existing cast/collection clock.
	_art.seek_frame(frame)
	var factor: float = 2.0 * _radius / 380.0 * size_ratio
	_art.scale = Vector2.ONE * factor
	_art.position = Vector2(3.0, 3.5) * factor
	_art.modulate.a = opacity


func _draw() -> void:
	if _presentation == Presentation.RESULT:
		_draw_result_sparks()
		return
	if _presentation == Presentation.COOLDOWN:
		var detail_scale: float = _radius / REFERENCE_RADIUS
		draw_set_transform_matrix(SurfaceProjection.get_visual_compensation(self))
		draw_arc(
			Vector2.ZERO,
			13.0 * detail_scale,
			0.0,
			TAU,
			48,
			Color(ink, 0.2),
			2.5 * detail_scale,
			true
		)
		draw_arc(
			Vector2.ZERO,
			13.0 * detail_scale,
			-PI / 2.0,
			-PI / 2.0 + TAU * _cooldown_progress,
			48,
			Color(ink, 0.65),
			2.5 * detail_scale,
			true
		)


func _update_result_ring() -> void:
	var progress: float = clampf(_result_age / result_flash_seconds, 0.0, 1.0)
	var flash_radius: float = lerpf(_radius * 0.35, _radius, ease(progress, 0.55))
	var ring_points: PackedVector2Array = PackedVector2Array()
	for point_index: int in range(65):
		ring_points.append(Vector2.from_angle(TAU * float(point_index) / 64.0) * flash_radius)
	_result_ring.points = ring_points
	_result_ring.modulate.a = 1.0 - progress * 0.8
	_result_label.position = Vector2(-30.0, -16.0 - progress * 8.0)


func _draw_result_sparks() -> void:
	var progress: float = clampf(_result_age / result_flash_seconds, 0.0, 1.0)
	var detail_scale: float = _radius / REFERENCE_RADIUS
	var distance: float = lerpf(_radius * 0.45, _radius * 1.15, progress)
	for spark_index: int in range(8):
		var direction: Vector2 = Vector2.from_angle(TAU * float(spark_index) / 8.0)
		draw_line(
			direction * distance,
			direction * (distance + 9.0 * detail_scale),
			Color(accent, 1.0 - progress),
			2.4 * detail_scale,
			true
		)
