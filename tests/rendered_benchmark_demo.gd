extends "res://features/场景预览/游玩预览.gd"

# Drive the real gameplay methods from viewport coordinates without moving the
# user's desktop cursor or depending on focus, window scaling or physical input.
var benchmark_pointer: Vector2 = Vector2(24.0, 260.0)
var benchmark_cpu: Dictionary[String, int] = {}
var benchmark_frames: int = 0
var observed_process_delta: float = 0.0


func _process(delta: float) -> void:
	observed_process_delta = delta
	_window_has_focus = true
	var start: int = Time.get_ticks_usec()
	super._process(delta)
	_record_cpu("demo_total", start)
	benchmark_frames += 1


func _update_nest_hover(_viewport_position: Vector2) -> void:
	super._update_nest_hover(benchmark_pointer)


func _drive_tool(delta: float, _pointer: Vector2, _holding: bool) -> void:
	var world_pointer: Vector2 = (
		_world.get_global_transform_with_canvas().affine_inverse() * benchmark_pointer
	)
	super._drive_tool(delta, world_pointer, false)


func _advance_ground_mucus(delta: float) -> void:
	var start: int = Time.get_ticks_usec()
	super._advance_ground_mucus(delta)
	_record_cpu("_advance_ground_mucus", start)


func _advance_giant_fusion(delta: float) -> void:
	var start: int = Time.get_ticks_usec()
	super._advance_giant_fusion(delta)
	_record_cpu("_advance_giant_fusion", start)


func _advance_monster_chatter(delta: float) -> void:
	var start: int = Time.get_ticks_usec()
	super._advance_monster_chatter(delta)
	_record_cpu("_advance_monster_chatter", start)


func _record_cpu(section: String, start: int) -> void:
	benchmark_cpu[section] = benchmark_cpu.get(section, 0) + Time.get_ticks_usec() - start


func benchmark_cpu_averages() -> Dictionary[String, float]:
	var result: Dictionary[String, float] = {}
	for section: String in benchmark_cpu:
		result[section] = float(benchmark_cpu[section]) / maxf(benchmark_frames, 1) / 1000.0
	return result
