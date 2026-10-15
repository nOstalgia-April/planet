extends Node2D

@export var anchor_offset: Vector2 = Vector2(5.5, -30.0)
@export_range(0.1, 1.2, 0.01) var tool_width_ratio: float = 0.6
@export_range(0.1, 1.0, 0.05) var pixel_scale: float = 0.3
@export var meter_width: float = 96.0
@export var meter_height: float = 16.0
@export_range(0.05, 0.6, 0.01) var completion_hold: float = 0.24
@export var frame_texture: Texture2D
@export var fill_highlight: Texture2D
@export var empty_color: Color = Color("b5b3b4a6")

var displayed_stage: int = 3
var displayed_count: int = 7
var segment_count: int = 10
var time_ratio: float = 0.72
var captured_colors: PackedColorArray = PackedColorArray()
var _run: PrototypeRun
var _hold_remaining: float = 0.0
var _pulse: float = 0.0
var _interrupted: float = 0.0
var _elapsed: float = 0.0
var _standalone: bool = false
var _fill_style: StyleBoxFlat = StyleBoxFlat.new()

@onready var _time_track: Line2D = $TimeTrack
@onready var _time_fill: Line2D = $TimeFill


func _ready() -> void:
	assert(frame_texture != null and fill_highlight != null, "The supplied meter art is required.")
	_fill_style.anti_aliasing = true
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
		if displayed_count == 0:
			captured_colors.clear()
	time_ratio = clampf(_run.combo_remaining / _run.get_combo_window_seconds(), 0.0, 1.0)
	_update_timer()
	_update_anchor()
	queue_redraw()


func reset_feedback() -> void:
	captured_colors.clear()
	_hold_remaining = 0.0
	_pulse = 0.0
	_interrupted = 0.0


func fit_tool_width(visible_width: float) -> void:
	# Work in whole design pixels; the tool's transparent image margins do not count.
	meter_width = floorf(visible_width * tool_width_ratio / pixel_scale)
	meter_height = meter_width / 6.0
	queue_redraw()


func get_cell_rect(index: int) -> Rect2:
	var strip: Rect2 = get_fill_rect()
	var step_width: float = strip.size.x / segment_count
	return Rect2(
		strip.position + Vector2(step_width * index, 0.0), Vector2(step_width, strip.size.y)
	)


func get_fill_rect() -> Rect2:
	var art_scale: Vector2 = Vector2(meter_width / 96.0, meter_height / 16.0)
	return Rect2(
		get_meter_rect().position + Vector2(4.0, 3.0) * art_scale, Vector2(87.0, 10.0) * art_scale
	)


func get_meter_rect() -> Rect2:
	var meter_size: Vector2 = Vector2(meter_width, meter_height)
	return Rect2(-meter_size * 0.5, meter_size)


func _on_progressed(capture_color: Color) -> void:
	# This signal precedes the rules' stage reset, so the completed strip gets a visible beat.
	_hold_remaining = 0.0
	_interrupted = 0.0
	if _run.combo_count == 1:
		captured_colors.clear()
	captured_colors.append(capture_color)
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
		captured_colors.clear()
		var preview_colors: PackedColorArray = PackedColorArray(
			[Color("ffa6c6"), Color("a9bff6"), Color("ffa6c6"), Color("f3ca6a")]
		)
		for index: int in range(displayed_count):
			captured_colors.append(preview_colors[index % preview_colors.size()])
		time_ratio = 1.0 - fmod(_elapsed, 6.0) / 6.0
		_update_timer()
		queue_redraw()
	elif _run != null:
		refresh()


func _update_anchor() -> void:
	position = anchor_offset
	var screen_rect: Rect2 = get_global_transform_with_canvas() * get_meter_rect().grow(3.0)
	if screen_rect.position.y < 8.0:
		# When there is no space above the tool, put the strip below its mouth.
		position.y = absf(anchor_offset.y) * 0.5
		screen_rect = get_global_transform_with_canvas() * get_meter_rect().grow(3.0)
	var margin: Vector2 = screen_rect.size * 0.5 + Vector2.ONE * 8.0
	var center: Vector2 = screen_rect.get_center()
	var clamped: Vector2 = center.clamp(margin, get_viewport_rect().size - margin)
	var parent_inverse: Transform2D = (
		(get_parent() as Node2D).get_global_transform_with_canvas().affine_inverse()
	)
	position += parent_inverse * clamped - parent_inverse * center


func _update_timer() -> void:
	var bounds: Rect2 = get_meter_rect()
	var inset: float = meter_width * 0.08
	var left: Vector2 = Vector2(bounds.position.x + inset, bounds.end.y + 1.2)
	var right: Vector2 = Vector2(bounds.end.x - inset, left.y)
	_time_track.points = PackedVector2Array([left, right])
	var remaining_width: float = (right.x - left.x) * time_ratio
	_time_fill.points = PackedVector2Array([left, left + Vector2(remaining_width, 0.0)])
	_time_fill.visible = time_ratio > 0.0
	_time_fill.default_color = Color("f18a79") if time_ratio < 0.25 else Color("fff1bc")


func _draw() -> void:
	var strip: Rect2 = get_fill_rect()
	_draw_fill(strip, empty_color.lerp(Color("c68e91"), _interrupted * 0.6), true, true)
	for index: int in range(mini(displayed_count, captured_colors.size())):
		var cell: Rect2 = get_cell_rect(index)
		_draw_fill(cell, captured_colors[index], index == 0, index == segment_count - 1)
		var highlight: Rect2 = Rect2(
			cell.position + Vector2(0.0, strip.size.y * 0.12),
			Vector2(cell.size.x, strip.size.y * 0.18)
		)
		# Retain the supplied pink paint's light edge over the actual captured body color.
		var highlight_alpha: float = 0.3 + (_pulse * 0.35 if index == displayed_count - 1 else 0.0)
		draw_texture_rect(fill_highlight, highlight, false, Color(1.0, 1.0, 1.0, highlight_alpha))
	_draw_frame()
	var art_scale: Vector2 = Vector2(meter_width / 96.0, meter_height / 16.0)
	for index: int in range(1, segment_count):
		var tick_x: float = get_cell_rect(index).position.x
		draw_texture_rect_region(
			frame_texture,
			Rect2(
				Vector2(
					tick_x - 3.0 * art_scale.x, get_meter_rect().position.y + 8.0 * art_scale.y
				),
				Vector2(6.0, 5.0) * art_scale
			),
			Rect2(32.0, 8.0, 6.0, 5.0)
		)


func _draw_fill(rect: Rect2, color: Color, round_left: bool, round_right: bool) -> void:
	var radius: int = ceili(rect.size.y * 0.5)
	_fill_style.bg_color = color
	_fill_style.corner_radius_top_left = radius if round_left else 0
	_fill_style.corner_radius_bottom_left = radius if round_left else 0
	_fill_style.corner_radius_top_right = radius if round_right else 0
	_fill_style.corner_radius_bottom_right = radius if round_right else 0
	draw_style_box(_fill_style, rect)


func _draw_frame() -> void:
	var bounds: Rect2 = get_meter_rect()
	var art_scale: Vector2 = bounds.size / Vector2(96.0, 16.0)
	# Reassemble the original outline without its two baked ticks, then place the same
	# hand-drawn tick at the live stage's 3 / 5 / 7 / 10 capture boundaries.
	for source: Rect2 in [
		Rect2(0, 0, 96, 9), Rect2(0, 12, 96, 4), Rect2(0, 9, 10, 3), Rect2(84, 9, 12, 3)
	]:
		draw_texture_rect_region(
			frame_texture,
			Rect2(bounds.position + source.position * art_scale, source.size * art_scale),
			source
		)
