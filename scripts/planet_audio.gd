extends Node

# Earth_Rotate loops while a drag is actually turning the planet. Holding the
# drag still lets it fade out (via its FMOD AHDSR); reversing direction restarts
# the event from the top.

const ROTATE_EVENT: String = "event:/Earth_Rotate"

# Mouse motion does not arrive every frame, so the planet counts as still only
# after this long without turning.
@export_range(0.02, 0.5, 0.01) var still_seconds: float = 0.12
# Rotation (radians, about 7 px of drag in the near view) needed in the new
# direction before a reversal counts, so hand jitter does not retrigger the sound.
@export_range(0.0, 0.1, 0.001) var reverse_threshold: float = 0.006

var _ready_to_play: bool = false
var _rotate: FmodEvent
var _last_rotation: float = 0.0
var _direction: int = 0
var _still_elapsed: float = 0.0
var _reverse_amount: float = 0.0


func _ready() -> void:
	_ready_to_play = GameAudio.has_events([ROTATE_EVENT])


# Called every frame with the drag state and the planet's current rotation.
func update_rotation(delta: float, dragging: bool, rotation: float) -> void:
	var step: float = wrapf(rotation - _last_rotation, -PI, PI)
	_last_rotation = rotation
	if not _ready_to_play:
		return
	if not dragging:
		_stop()
		return
	if is_zero_approx(step):
		_still_elapsed += delta
		if _still_elapsed >= still_seconds:
			_stop()
		return
	_still_elapsed = 0.0
	var direction: int = 1 if step > 0.0 else -1
	if _rotate == null:
		_start(direction)
	elif direction == _direction:
		_reverse_amount = 0.0
	else:
		_reverse_amount += absf(step)
		if _reverse_amount >= reverse_threshold:
			_stop()
			_start(direction)


# Banks outlive the scene, so leaving it must stop the loop explicitly.
func _exit_tree() -> void:
	_stop()


func _start(direction: int) -> void:
	_rotate = GameAudio.start_loop(ROTATE_EVENT)
	_direction = direction
	_reverse_amount = 0.0


func _stop() -> void:
	GameAudio.stop_loop(_rotate)
	_rotate = null
	_direction = 0
	_still_elapsed = 0.0
	_reverse_amount = 0.0
