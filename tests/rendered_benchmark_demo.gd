extends "res://scripts/disk_demo.gd"

# Drive the real gameplay methods from viewport coordinates without moving the
# user's desktop cursor or depending on focus, window scaling or physical input.
var benchmark_pointer: Vector2 = Vector2(24.0, 260.0)
var observed_process_delta: float = 0.0


func _process(delta: float) -> void:
	observed_process_delta = delta
	_window_has_focus = true
	super._process(delta)


func _update_nest_hover(_viewport_position: Vector2) -> void:
	super._update_nest_hover(benchmark_pointer)


func _drive_tool(delta: float, _pointer: Vector2, _holding: bool) -> void:
	var world_pointer: Vector2 = (
		_world.get_global_transform_with_canvas().affine_inverse() * benchmark_pointer
	)
	super._drive_tool(delta, world_pointer, false)
