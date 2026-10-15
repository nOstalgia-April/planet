extends Node2D

@export var anchor_offset: Vector2 = Vector2(5.5, -30.0)
@export_range(0.1, 1.2, 0.01) var tool_width_ratio: float = 0.2666667
@export_range(0.1, 1.0, 0.05) var pixel_scale: float = 0.3
@export var meter_width: float = 28.0
@export var meter_height: float = 8.0
@export var frame_padding: float = 1.0
@export_range(0.05, 0.6, 0.01) var completion_hold: float = 0.24
@export var stage_gradients: Array[GradientTexture2D] = []
@export var frame_style: StyleBoxFlat

var displayed_stage: int = 3
var displayed_count: int = 7
var segment_count: int = 10
var time_ratio: float = 0.72
var _run: PrototypeRun
var _hold_remaining: float = 0.0
var _pulse: float = 0.0
var _interrupted: float = 0.0
var _elapsed: float = 0.0
var _standalone: bool = false

@onready var _time_track: Line2D = $TimeTrack
@onready var _time_fill: Line2D = $TimeFill


func _ready() -> void:
	assert(stage_gradients.size() == 4, "Each combo stage needs its continuous gradient.")
	_standalone = get_tree().current_scene == self
	if _standalone:
		position = get_viewport_rect().size * 0.5
		scale = Vector2.ONE * 5.0
	else:
		scale = Vector2.ONE * pixel_scale
		hide()


func configure(run: PrototypeRun) -> void:
	_run = run
	_run.combo_progressed.connect(_on_progressed)
	_run.combo_interrupted.connect(_on_interrupted)
	refresh()


func refresh() -> void:
	visible = _run.combo_level > 0
	if not visible:
		reset_feedback()
	if _hold_remaining <= 0.0:
		displayed_stage = _run.combo_stage
		displayed_count = _run.combo_count
		segment_count = _run.get_combo_target()
	time_ratio = clampf(_run.combo_remaining / _run.get_combo_window_seconds(), 0.0, 1.0)
	_update_timer()
	_update_anchor()
	queue_redraw()


func reset_feedback() -> void:
	_hold_remaining = 0.0
	_pulse = 0.0
	_interrupted = 0.0


func fit_tool_width(visible_width: float) -> void:
	# Work in whole design pixels; the tool's transparent image margins do not count.
	meter_width = floorf(visible_width * tool_width_ratio / pixel_scale)
	queue_redraw()


func get_cell_rect(index: int) -> Rect2:
	var strip: Rect2 = get_fill_rect()
	var step_width: float = strip.size.x / segment_count
	return Rect2(
		strip.position + Vector2(step_width * index, 0.0), Vector2(step_width, strip.size.y)
	)


func get_fill_rect() -> Rect2:
	return Rect2(
		Vector2(-meter_width * 0.5 + frame_padding, -meter_height * 0.5 + frame_padding),
		Vector2(meter_width - frame_padding * 2.0, meter_height - frame_padding * 2.0 - 2.0)
	)


func get_meter_rect() -> Rect2:
	var meter_size: Vector2 = Vector2(meter_width, meter_height)
	return Rect2(-meter_size * 0.5, meter_size)


func _on_progressed() -> void:
	# This signal precedes the rules' stage reset, so the completed strip gets a visible beat.
	_hold_remaining = 0.0
	_interrupted = 0.0
	refresh()
	_pulse = 1.0
	if displayed_count >= segment_count:
		_hold_remaining = completion_hold


func _on_interrupted() -> void:
	reset_feedback()
	_interrupted = 1.0
	refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	_hold_remaining = maxf(0.0, _hold_remaining - delta)
	_pulse = maxf(0.0, _pulse - delta * 5.0)
	_interrupted = maxf(0.0, _interrupted - delta * 3.0)
	if _standalone:
		displayed_count = mini(int(fmod(_elapsed, 6.0) / 0.45), segment_count)
		time_ratio = 1.0 - fmod(_elapsed, 6.0) / 6.0
		_update_timer()
		queue_redraw()
	elif _run != null:
		refresh()


func _update_anchor() -> void:
	position = anchor_offset
	var screen_rect: Rect2 = get_global_transform_with_canvas() * get_meter_rect().grow(1.5)
	var margin: Vector2 = screen_rect.size * 0.5 + Vector2.ONE * 8.0
	var center: Vector2 = screen_rect.get_center()
	var clamped: Vector2 = center.clamp(margin, get_viewport_rect().size - margin)
	var parent_inverse: Transform2D = (
		(get_parent() as Node2D).get_global_transform_with_canvas().affine_inverse()
	)
	position += parent_inverse * clamped - parent_inverse * center


func _update_timer() -> void:
	var bounds: Rect2 = get_meter_rect()
	var left: Vector2 = Vector2(bounds.position.x + frame_padding, bounds.end.y - 1.5)
	var right: Vector2 = Vector2(bounds.end.x - frame_padding, left.y)
	_time_track.points = PackedVector2Array([left, right])
	var remaining_width: float = floorf((right.x - left.x) * time_ratio)
	_time_fill.points = PackedVector2Array([left, left + Vector2(remaining_width, 0.0)])
	_time_fill.visible = time_ratio > 0.0
	_time_fill.default_color = Color("f18a79") if time_ratio < 0.25 else Color("fff1bc")


func _draw() -> void:
	draw_style_box(frame_style, get_meter_rect())
	var strip: Rect2 = get_fill_rect()
	draw_rect(strip, Color("665966").lerp(Color("a5787b"), _interrupted * 0.6))
	if displayed_count > 0:
		var progress: float = clampf(float(displayed_count) / segment_count, 0.0, 1.0)
		var filled: Rect2 = Rect2(strip.position, Vector2(strip.size.x * progress, strip.size.y))
		var gradient: GradientTexture2D = stage_gradients[displayed_stage]
		# Reveal the existing gradient; never stretch its colors over each new progress step.
		draw_texture_rect_region(
			gradient,
			filled,
			Rect2(Vector2.ZERO, Vector2(gradient.width * progress, gradient.height))
		)
		draw_line(
			Vector2(filled.end.x, filled.position.y),
			filled.end,
			Color(1, 1, 0.92, _pulse * 0.6),
			0.5,
			true
		)
	for index: int in range(1, segment_count):
		var tick_x: float = get_cell_rect(index).position.x
		draw_line(
			Vector2(tick_x, strip.end.y - 1.0),
			Vector2(tick_x, strip.end.y),
			Color(0.22, 0.17, 0.24, 0.5),
			0.4,
			true
		)
