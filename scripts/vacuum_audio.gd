extends Node

# Drives the FMOD vacuum events from pipe capture state. Vacuum_Loop is started
# and stopped inside FMOD by Vacuum_On / Vacuum_Off, so it is never played here.

const VACUUM_ON_EVENT: String = "event:/Vacuum_On"
const VACUUM_OFF_EVENT: String = "event:/Vacuum_Off"
const SLIME_ENTER_EVENT: String = "event:/Slime_Enter"
const SLIME_EXIT_EVENT: String = "event:/Slime_Exit"
const IN_SLIME_PARAMETER: String = "InSlime"

# Chained captures re-acquire the next target within a frame or two; keeping the
# vacuum running through that gap avoids an Off/On pair per collected monster.
@export_range(0.0, 1.0, 0.05) var release_grace_seconds: float = 0.2

var _ready_to_play: bool = false
var _vacuum_on: bool = false
var _in_slime: bool = false
var _release_elapsed: float = 0.0


func _ready() -> void:
	_ready_to_play = GameAudio.has_events(
		[VACUUM_ON_EVENT, VACUUM_OFF_EVENT, SLIME_ENTER_EVENT, SLIME_EXIT_EVENT]
	)


# Called every tool tick. engaged: the pipe currently holds a target.
# nozzle_in_mucus: the pipe mouth is inside ground mucus left by mucus monsters.
func update(delta: float, engaged: bool, nozzle_in_mucus: bool) -> void:
	if engaged:
		_release_elapsed = 0.0
		if not _vacuum_on:
			_vacuum_on = true
			_play(VACUUM_ON_EVENT)
	elif _vacuum_on:
		_release_elapsed += delta
		if _release_elapsed >= release_grace_seconds:
			stop_now()
			return
	if not _vacuum_on:
		return
	if nozzle_in_mucus and not _in_slime:
		_in_slime = true
		_play(SLIME_ENTER_EVENT)
	elif not nozzle_in_mucus and _in_slime:
		_in_slime = false
		_play(SLIME_EXIT_EVENT)


# Banks outlive the scene, so leaving it must stop Vacuum_Loop explicitly.
func _exit_tree() -> void:
	stop_now()


# Immediate shutdown for interruptions such as restart.
func stop_now() -> void:
	clear_slime()
	_release_elapsed = 0.0
	if _vacuum_on:
		_vacuum_on = false
		_play(VACUUM_OFF_EVENT)


# Leave the mucus state silently when the vacuum stops, so no Pop plays.
func clear_slime() -> void:
	if not _in_slime:
		return
	_in_slime = false
	if _ready_to_play:
		GameAudio.set_global(IN_SLIME_PARAMETER, 0.0)


func _play(event_path: String) -> void:
	if _ready_to_play:
		GameAudio.play(event_path)
