extends Node

# Planet view sounds. Earth_Rotate loops while a drag is actually turning the
# planet; holding the drag still lets it fade out (via its FMOD AHDSR) and
# reversing direction restarts it from the top. ZoomIn / ZoomOut play when the
# camera starts an animated switch between the near view and the overview.

const ROTATE_EVENT: String = "event:/AnimationSystem/Earth_Rotate"
const ZOOM_IN_EVENT: String = "event:/UI/ZoomIn"
const ZOOM_OUT_EVENT: String = "event:/UI/ZoomOut"
# Planet color restoration: Stage1 for the first species color this run,
# Stage2 for the later ones, Stage3 for the final turn to white.
const COLOR_RECOVER_FIRST_EVENT: String = "event:/AnimationSystem/ColorRecover_Stage1"
const COLOR_RECOVER_LATER_EVENT: String = "event:/AnimationSystem/ColorRecover_Stage2"
const COLOR_RECOVER_WHITE_EVENT: String = "event:/AnimationSystem/ColorRecover_Stage3"
# Background palette turning to a species' colors (pink, blue, green), indexed
# by NestState.Species.
const COLOR_CHANGE_EVENTS: PackedStringArray = [
	"event:/AnimationSystem/ColorChange_Slime",
	"event:/AnimationSystem/ColorChange_Mucus",
	"event:/AnimationSystem/ColorChange_Drill",
]
# Background rocks and trees popping up as the near view appears.
const TERRAIN_POP_EVENT: String = "event:/TreePopUp"
# The victory panel after every monster is cleared.
const CLEAR_MONSTER_EVENT: String = "event:/UI/Clear_Monster"

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
var _color_recover_ready: bool = false
var _color_change_ready: bool = false
var _clear_monster_ready: bool = false
var _terrain_pop_ready: bool = false
# Presentations move the camera themselves and play their own sounds.
var zoom_sounds_muted: bool = false
# Last camera target (1 = near view, 0 = overview); NAN until the first frame.
var _zoom_target: float = NAN


func _ready() -> void:
	_ready_to_play = GameAudio.has_events([ROTATE_EVENT])
	_zoom_ready = GameAudio.has_events([ZOOM_IN_EVENT, ZOOM_OUT_EVENT])
	_color_recover_ready = GameAudio.has_events(
		[COLOR_RECOVER_FIRST_EVENT, COLOR_RECOVER_LATER_EVENT, COLOR_RECOVER_WHITE_EVENT]
	)
	_color_change_ready = GameAudio.has_events(COLOR_CHANGE_EVENTS)
	_clear_monster_ready = GameAudio.has_events([CLEAR_MONSTER_EVENT])
	_terrain_pop_ready = GameAudio.has_events([TERRAIN_POP_EVENT])


# stage: 1 for the first species color restored this run, then 2 and 3.
func color_recovered(stage: int) -> void:
	if _color_recover_ready:
		GameAudio.play(COLOR_RECOVER_FIRST_EVENT if stage == 1 else COLOR_RECOVER_LATER_EVENT)


func planet_turned_white() -> void:
	if _color_recover_ready:
		GameAudio.play(COLOR_RECOVER_WHITE_EVENT)


func palette_changed_to(species: int) -> void:
	if _color_change_ready and species >= 0 and species < COLOR_CHANGE_EVENTS.size():
		GameAudio.play(COLOR_CHANGE_EVENTS[species])


# Called once for the rocks and once for the trees as they pop up.
func terrain_popped(_trees: bool) -> void:
	if _terrain_pop_ready:
		GameAudio.play(TERRAIN_POP_EVENT)


# A presentation moving the camera into the near view itself.
func zoomed_in() -> void:
	if _zoom_ready:
		GameAudio.play(ZOOM_IN_EVENT)


# Returns false when the event is unavailable, so the caller can fall back.
func monsters_cleared() -> bool:
	if not _clear_monster_ready:
		return false
	GameAudio.play(CLEAR_MONSTER_EVENT)
	return true


# Called every frame with the camera's target view and whether it is animating.
# Only animated switches play: instant ones (restart, scenes opening in the
# overview) just update the tracked target.
func update_zoom(target_zoom: float, transitioning: bool) -> void:
	var previous: float = _zoom_target
	_zoom_target = target_zoom
	if (
		not _zoom_ready
		or zoom_sounds_muted
		or is_nan(previous)
		or is_equal_approx(previous, target_zoom)
	):
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
