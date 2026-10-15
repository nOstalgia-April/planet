extends Control

const MainMenu = preload("res://scenes/主菜单/主菜单.gd")
const OPENING_SOUND: String = "event:/Mx/OpeningAnimation"
# FMOD needs ~0.2 s to start a sound; never hold the first frame longer than this.
const SOUND_START_TIMEOUT: float = 0.5
# Loading the frames can stall the game for half a second while the sound keeps
# playing; beyond this drift the animation jumps to the sound's position.
const MAX_DRIFT_SECONDS: float = 0.05

@export var main_menu: PackedScene
@export var animation_player: AnimationPlayer

# The opening sound outlives this scene, so its tail carries into the main menu.
var _sound: FmodEvent
var _waiting_for_sound: float = 0.0
# Sound timeline (seconds) at the moment the animation started moving; -1 while
# the first frame is still held.
var _sound_offset: float = -1.0
var _preparing_game: bool = false


func _ready() -> void:
	assert(main_menu != null)
	assert(animation_player != null)
	RenderingServer.set_default_clear_color(Color.BLACK)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	animation_player.animation_finished.connect(_on_animation_finished)
	animation_player.play(&"开头")
	animation_player.advance(0.0)
	# Hold the first frame until the sound is actually playing, so they stay in sync.
	_sound = GameAudio.start_event(OPENING_SOUND)
	if _sound != null:
		animation_player.speed_scale = 0.0
	set_process(_sound != null)
	# Prepare gameplay while the opening is on screen. The menu retrieves this
	# same request, so Start does not begin all resource IO from scratch.
	_preparing_game = MainMenu.prepare_scene() == OK


func _exit_tree() -> void:
	if _preparing_game:
		MainMenu.release_scene(get_tree(), MainMenu.DEFAULT_START_SCENE)


# Holds the first frame until the sound starts, then keeps the animation on the
# sound's clock.
func _process(delta: float) -> void:
	if not _sound.is_valid():
		set_process(false)
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
		set_process(false)
	elif absf(animation_player.current_animation_position - target) > MAX_DRIFT_SECONDS:
		animation_player.seek(target, true)


func _on_animation_finished(_animation_name: StringName) -> void:
	_enter_main_menu.call_deferred()


func _enter_main_menu() -> void:
	var result: Error = get_tree().change_scene_to_packed(main_menu)
	if result != OK:
		push_error("无法进入主菜单：%d" % result)
