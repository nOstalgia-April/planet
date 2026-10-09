extends Node2D

const SlimeView = preload("res://features/slime_suction_preview/pink_slime_view.gd")
const PipeView = preload("res://scripts/pipe_cursor.gd")

enum Playback { POINTER, ATTRACTION, CAPTURE }

@export_range(0.1, 3.0, 0.05) var capture_seconds: float = 0.6
@export_range(0.1, 1.0, 0.05) var slow_motion_scale: float = 0.25
@export_range(0.5, 10.0, 0.25) var preview_zoom: float = 4.5

var _playback: Playback = Playback.POINTER
var _progress: float = 0.0
var _strength: float = 0.0
var _pull_offset: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _completed: bool = false
var _reset_elapsed: float = 0.0
var _pointer: Vector2 = Vector2(32.0, -14.0)
var _home_position: Vector2 = Vector2.ZERO

@onready var _world: Node2D = $World
@onready var _slime: SlimeView = $World/PinkSlime
@onready var _pipe: PipeView = $World/Pipe
@onready var _attraction_button: Button = %AttractionButton
@onready var _capture_button: Button = %CaptureButton
@onready var _reset_button: Button = %ResetButton
@onready var _slow_motion: CheckButton = %SlowMotion


func _ready() -> void:
	get_window().title = "粉色史莱姆吸取预览"
	_home_position = Vector2(0.0, _slime.display_height * 0.45)
	_attraction_button.toggled.connect(_on_attraction_toggled)
	_capture_button.pressed.connect(play_capture)
	_reset_button.pressed.connect(reset_preview)
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	reset_preview()


func _update_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	_world.position = viewport_size * Vector2(0.5, 0.48)
	var fit_scale: float = minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
	_world.scale = Vector2.ONE * preview_zoom * fit_scale


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer = _world.to_local(get_global_mouse_position())
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_R:
			reset_preview()


func _process(delta: float) -> void:
	var holding: bool = (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		and get_viewport().gui_get_hovered_control() == null
	)
	var simulation_delta: float = (
		delta * (slow_motion_scale if _slow_motion.button_pressed else 1.0)
	)
	advance_preview(simulation_delta, _pointer, holding, delta)


func advance_preview(
	delta: float, pointer: Vector2, holding: bool, real_delta: float = 0.0
) -> void:
	_elapsed += delta
	if _completed:
		_reset_elapsed += real_delta
		if _reset_elapsed >= 0.8 and not holding:
			reset_preview()
		return
	var target: Vector2 = pointer
	var active: bool = holding
	if _playback == Playback.ATTRACTION:
		target = _slime.get_capture_point() + Vector2(36.0, -8.0)
		active = true
	elif _playback == Playback.CAPTURE:
		target = Vector2(9.0, -9.0)
		active = true
	var body_center: Vector2 = _slime.get_capture_point()
	var distance: float = body_center.distance_to(target)
	if active and distance <= _pipe.radius and _playback != Playback.ATTRACTION:
		_progress = minf(1.0, _progress + delta / capture_seconds)
		_strength = 0.0
		_pull_offset = Vector2.ZERO
		body_center = body_center.move_toward(target, delta * (24.0 + _progress * 46.0))
		_slime.position = body_center + Vector2(0.0, _slime.display_height * 0.45)
	else:
		_progress = maxf(0.0, _progress - delta * 0.75)
		_slime.position = _slime.position.lerp(_home_position, 1.0 - exp(-delta * 12.0))
		if active and distance <= _pipe.attraction_radius:
			var desired_strength: float = maxf(0.2, 1.0 - distance / _pipe.attraction_radius)
			var smoothing: float = 1.0 - exp(-delta * 18.0)
			var direction: Vector2 = (target - body_center).normalized()
			_strength = lerpf(_strength, desired_strength, smoothing)
			_pull_offset = _pull_offset.lerp(direction * desired_strength * 7.0, smoothing)
		else:
			var recovery: float = 1.0 - exp(-delta * 12.0)
			_strength = lerpf(_strength, 0.0, recovery)
			_pull_offset = _pull_offset.lerp(Vector2.ZERO, recovery)
	_slime.show_pose(_progress, _strength, _pull_offset, _elapsed)
	_pipe.set_tool_state(target, target, active)
	if _progress >= 1.0:
		_completed = true
		_slime.hide()


func play_capture() -> void:
	reset_preview()
	_playback = Playback.CAPTURE


func reset_preview() -> void:
	_playback = Playback.POINTER
	_progress = 0.0
	_strength = 0.0
	_pull_offset = Vector2.ZERO
	_elapsed = 0.0
	_completed = false
	_reset_elapsed = 0.0
	_attraction_button.set_pressed_no_signal(false)
	_slime.position = _home_position
	_slime.show()
	_slime.show_pose(0.0, 0.0, Vector2.ZERO, 0.0)
	_pipe.set_tool_state(_pointer, _pointer, false)


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/主菜单/主菜单.tscn")


func _on_attraction_toggled(enabled: bool) -> void:
	reset_preview()
	_attraction_button.set_pressed_no_signal(enabled)
	_playback = Playback.ATTRACTION if enabled else Playback.POINTER
