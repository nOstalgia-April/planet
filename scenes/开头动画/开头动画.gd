extends Control

const MainMenu = preload("res://scenes/主菜单/主菜单.gd")
const OPENING_SOUND: String = "event:/Mx/OpeningAnimation"
const GAMEPLAY_MUSIC: String = "event:/Mx/Mx_GamePlay"
# The game opens on the far view, so its music starts in the far-view mix.
const DISTANT_VIEW_PARAMETER: String = "IsDistantView"
# FMOD needs ~0.2 s to start a sound; never hold the first frame longer than this.
const SOUND_START_TIMEOUT: float = 0.5
# Keep the opening sound's fade protected during the handoff to the live planet.
const MUSIC_AFTER_SOUND_LEAD: float = 2.5
# Loading the frames can stall the game for half a second while the sound keeps
# playing; beyond this drift the animation jumps to the sound's position.
const MAX_DRIFT_SECONDS: float = 0.05

@export var animation_player: AnimationPlayer

# The opening sound's tail continues while the briefing appears.
var _sound: FmodEvent
var _syncing_sound: bool = false
var _waiting_for_sound: float = 0.0
# Sound timeline (seconds) at the moment the animation started moving; -1 while
# the first frame is still held.
var _sound_offset: float = -1.0
var _preparing_game: bool = false
var _prepared_scene: PackedScene
var _animation_finished: bool = false
var _entering_game: bool = false


func _ready() -> void:
	assert(animation_player != null)
	RenderingServer.set_default_clear_color(Color.BLACK)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	GameAudio.stop_music()
	animation_player.animation_finished.connect(_on_animation_finished)
	animation_player.play(&"开头")
	animation_player.advance(0.0)
	# Hold the first frame until the sound is actually playing, so they stay in sync.
	_sound = GameAudio.start_event(OPENING_SOUND)
	if _sound != null:
		animation_player.speed_scale = 0.0
	_syncing_sound = _sound != null
	# The menu prepares the opening; gameplay loads while the animation plays.
	_preparing_game = MainMenu.prepare_scene() == OK
	if not _preparing_game:
		_loading_failed()


func _exit_tree() -> void:
	if _preparing_game:
		MainMenu.release_scene(get_tree(), MainMenu.DEFAULT_START_SCENE)


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _preparing_game:
		_poll_game()
	if _syncing_sound:
		_sync_sound(delta)


# Holds the first frame until the sound starts, then keeps the animation on the
# sound's clock.
func _sync_sound(delta: float) -> void:
	if not _sound.is_valid():
		_syncing_sound = false
		animation_player.speed_scale = 1.0
		return
	var sound_seconds: float = _sound.get_timeline_position() / 1000.0
	if _sound_offset < 0.0:
		# A loading hitch must not use up the whole wait in one frame.
		_waiting_for_sound += minf(delta, 0.1)
		if _waiting_for_sound < SOUND_START_TIMEOUT and is_zero_approx(sound_seconds):
			return
		_sound_offset = sound_seconds
		animation_player.speed_scale = 1.0
		return
	var target: float = sound_seconds - _sound_offset
	var length: float = animation_player.current_animation_length
	if target >= length - MAX_DRIFT_SECONDS:
		_syncing_sound = false
	elif absf(animation_player.current_animation_position - target) > MAX_DRIFT_SECONDS:
		animation_player.seek(target, true)


func _poll_game() -> void:
	var path: String = MainMenu.DEFAULT_START_SCENE
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_preparing_game = false
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_prepared_scene = ResourceLoader.load_threaded_get(path) as PackedScene
		_try_enter_game()
	else:
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			ResourceLoader.load_threaded_get(path)
		_loading_failed()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != &"开头":
		return
	_animation_finished = true
	_try_enter_game()


func _try_enter_game() -> void:
	if not _animation_finished or _prepared_scene == null or _entering_game:
		return
	_entering_game = true
	_enter_game.call_deferred()


# The start sound already played on the menu's click. Gameplay requests its
# music on entry beneath the briefing; any remaining opening tail finishes first.
func _enter_game() -> void:
	GameAudio.hold_music_for(_sound, OPENING_SOUND, MUSIC_AFTER_SOUND_LEAD)
	GameAudio.set_music_parameter(GAMEPLAY_MUSIC, DISTANT_VIEW_PARAMETER, 1.0)
	var result: Error = get_tree().change_scene_to_packed(_prepared_scene)
	if result != OK:
		_loading_failed()


func _loading_failed() -> void:
	set_process(false)
	push_error("无法准备游戏场景：" + MainMenu.DEFAULT_START_SCENE)
	get_tree().change_scene_to_file.call_deferred("res://scenes/主菜单/主菜单.tscn")
