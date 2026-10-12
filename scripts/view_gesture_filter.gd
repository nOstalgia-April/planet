extends RefCounted

# Godot gestures have no begin/end phase; a quiet interval separates strokes.
const IDLE_MSEC: int = 320
const PAN_THRESHOLD: float = 40.0
const PINCH_THRESHOLD: float = 0.113329  # log(1.12)

var _last_msec: int = -1
var _amount: float = 0.0
var _kind: StringName = &""
var _latched: bool = false


func reset() -> void:
	_last_msec = -1
	_amount = 0.0
	_kind = &""
	_latched = false


func suppress() -> void:
	_last_msec = Time.get_ticks_msec()
	_amount = 0.0
	_latched = true


func feed(event: InputEventGesture, allowed: bool) -> float:
	var now: int = Time.get_ticks_msec()
	if _last_msec < 0 or now - _last_msec > IDLE_MSEC:
		reset()
	_last_msec = now
	if not allowed:
		_latched = true
	if _latched:
		return 0.0
	var amount: float = 0.0
	var threshold: float = PAN_THRESHOLD
	var kind: StringName = &"pan"
	if event is InputEventMagnifyGesture:
		var magnify: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		if magnify.factor <= 0.0 or not is_finite(magnify.factor):
			return 0.0
		amount = log(magnify.factor)
		threshold = PINCH_THRESHOLD
		kind = &"pinch"
	elif event is InputEventPanGesture:
		var pan: InputEventPanGesture = event as InputEventPanGesture
		if not pan.delta.is_finite():
			return 0.0
		if absf(pan.delta.x) >= absf(pan.delta.y):
			_amount = 0.0
			return 0.0
		amount = -pan.delta.y
	else:
		return 0.0
	if kind != _kind or amount * _amount < 0.0:
		_amount = 0.0
	_kind = kind
	_amount += amount
	if absf(_amount) < threshold:
		return 0.0
	_latched = true
	return signf(_amount)
