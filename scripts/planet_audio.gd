extends Node

# Planet view sounds. Earth_Rotate loops while a drag is actually turning the
# planet; holding the drag still lets it fade out (via its FMOD AHDSR) and
# reversing direction restarts it from the top. ZoomIn / ZoomOut play when the
# camera starts an animated switch between the near view and the overview.

const ROTATE_EVENT: String = "event:/Earth_Rotate"
const ZOOM_IN_EVENT: String = "event:/ZoomIn"
const ZOOM_OUT_EVENT: String = "event:/ZoomOut"

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
var _zoom_ready: bool = false
# Last camera target (1 = near view, 0 = overview); NAN until the first frame.
var _zoom_target: float = NAN


func _ready() -> void:
	_ready_to_play = GameAudio.has_events([ROTATE_EVENT])
	_zoom_ready = GameAudio.has_events([ZOOM_IN_EVENT, ZOOM_OUT_EVENT])


# Called every frame with the camera's target view and whether it is animating.
# Only animated switches play: instant ones (restart, scenes opening in the
# overview) just update the tracked target.
func update_zoom(target_zoom: float, transitioning: bool) -> void:
	var previous: float = _zoom_target
	_zoom_target = target_zoom
	if not _zoom_ready or is_nan(previous) or is_equal_approx(previous, target_zoom):
		return
	if transitioning:
		GameAudio.play(ZOOM_IN_EVENT if target_zoom > previous else ZOOM_OUT_EVENT)


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
