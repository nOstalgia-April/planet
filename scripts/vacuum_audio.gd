extends Node

# Drives the FMOD vacuum events from pipe capture state. Vacuum_Loop is started
# and stopped inside FMOD by Vacuum_On / Vacuum_Off, so it is never played here.

const VACUUM_ON_EVENT: String = "event:/Vacuum/Vacuum_On"
const VACUUM_OFF_EVENT: String = "event:/Vacuum/Vacuum_Off"
const SLIME_ENTER_EVENT: String = "event:/Slime_Enter"
const SLIME_EXIT_EVENT: String = "event:/Slime_Exit"
const IN_SLIME_PARAMETER: String = "InSlime"
# Loops while one monster is being sucked in; Loading_Progress follows its
# capture bar (0-1). Each monster gets its own instance.
const LOADING_EVENT: String = "event:/Vacuum/Vacuum_Loading"
const LOADING_PARAMETER: String = "Loading_Progress"
# Loops while a monster stuck in mucus is pulled free; MucusPeel_Progress
# follows its peel bar (0-1). PeelSnap plays once as it comes free.
const PEEL_EVENT: String = "event:/Vacuum/Mucus_Peel"
const PEEL_PARAMETER: String = "MucusPeel_Progress"
const PEEL_SNAP_EVENT: String = "event:/Vacuum/Mucus_PeelSnap"

# Chained captures re-acquire the next target within a frame or two; keeping the
# vacuum running through that gap avoids an Off/On pair per collected monster.
@export_range(0.0, 1.0, 0.05) var release_grace_seconds: float = 0.2

var _ready_to_play: bool = false
var _vacuum_on: bool = false
var _in_slime: bool = false
var _release_elapsed: float = 0.0
var _loading_ready: bool = false
var _loading: FmodEvent
var _loading_target_id: int = 0
var _peel_ready: bool = false
var _peel: FmodEvent
var _peel_target_id: int = 0


func _ready() -> void:
	_ready_to_play = GameAudio.has_events(
		[VACUUM_ON_EVENT, VACUUM_OFF_EVENT, SLIME_ENTER_EVENT, SLIME_EXIT_EVENT]
	)
	_loading_ready = GameAudio.has_events([LOADING_EVENT])
	_peel_ready = GameAudio.has_events([PEEL_EVENT, PEEL_SNAP_EVENT])


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


# target: the monster whose capture bar is filling, or null when none is.
func update_loading(target: Object, progress: float) -> void:
	if not _loading_ready:
		return
	if target == null:
		stop_loading()
		return
	if _loading != null and target.get_instance_id() != _loading_target_id:
		stop_loading()
	if _loading == null:
		_loading = GameAudio.start_loop(LOADING_EVENT)
		if _loading == null:
			return
		_loading_target_id = target.get_instance_id()
	_loading.set_parameter_by_name(LOADING_PARAMETER, clampf(progress, 0.0, 1.0))


# Stops through FMOD's own fade-out (AHDSR release, if any).
func stop_loading() -> void:
	if _loading != null:
		GameAudio.stop_loop(_loading)
	_loading = null
	_loading_target_id = 0


# target: the monster being pulled off the mucus, or null when none is.
func update_peel(target: Object, progress: float) -> void:
	if not _peel_ready:
		return
	if target == null:
		stop_peel()
		return
	if _peel != null and target.get_instance_id() != _peel_target_id:
		stop_peel()
	if _peel == null:
		_peel = GameAudio.start_loop(PEEL_EVENT)
		if _peel == null:
			return
		_peel_target_id = target.get_instance_id()
	_peel.set_parameter_by_name(PEEL_PARAMETER, clampf(progress, 0.0, 1.0))


# The monster came free of the mucus: end the peel loop and snap.
func peel_snapped() -> void:
	if not _peel_ready:
		return
	stop_peel()
	GameAudio.play(PEEL_SNAP_EVENT)


func stop_peel() -> void:
	if _peel != null:
		GameAudio.stop_loop(_peel)
	_peel = null
	_peel_target_id = 0


# Immediate shutdown for interruptions such as restart.
func stop_now() -> void:
	stop_loading()
	stop_peel()
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
