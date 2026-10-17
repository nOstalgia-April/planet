extends Node2D

signal transport_finished
signal transport_cancelled

const SurfaceProjection = preload("res://scripts/surface_projection.gd")
const VacuumSkin = preload("res://scripts/vacuum_skin.gd")
const ComboBurst = preload("res://scripts/combo_burst.gd")
const ComboMeter = preload("res://scripts/ui/combo_meter.gd")
const ComboBurstScene: PackedScene = preload("res://scenes/effects/combo_burst.tscn")
const REFERENCE_RADIUS: float = 24.0

enum TransportState { IDLE, SINGLE, CONTINUOUS }

@export_range(1.0, 40.0, 0.1) var radius: float = 9.6
@export_range(0.2, 1.0, 0.05) var feedback_scale: float = 0.55
@export_range(1.0, 2.0, 0.05) var particle_spread: float = 1.5
@export_range(0.05, 1.0, 0.001) var art_scale: float = 0.144
@export var mouth_pixel: Vector2 = Vector2(103.0, 190.0)
@export var ink: Color = Color("454944")
@export var accent: Color = Color("4c837c")
@export var active: bool = false

var transport_state: TransportState = TransportState.IDLE
var _time: float = 0.0
var _mouth_local: Vector2 = Vector2.ZERO
var _capture_engaged: bool = false
var _pending_transport: bool = false
var _last_capture_skin: VacuumSkin.SkinKind = VacuumSkin.SkinKind.DEFAULT
var _combo_active: bool = false
var _combo_hold: float = 0.0
var _combo_burst_played: bool = false
var _combo_restoring: bool = false
var _combo_reward: Vector2i = Vector2i.ZERO
var _combo_bursts: Array[Vector2i] = []

@onready var _art_root: Node2D = $ArtRoot
@onready var _art: VacuumSkin = $ArtRoot/吸尘器
@onready var combo_meter: ComboMeter = $ArtRoot/ComboMeter


func _ready() -> void:
	_art.position = (Vector2(141.5, 143.0) - mouth_pixel) * art_scale
	_art.scale = Vector2.ONE * art_scale
	var tool_image: Image = _art.default_frames[0].get_image()
	if tool_image.is_compressed():
		tool_image.decompress()
	combo_meter.fit_tool_width(float(tool_image.get_used_rect().size.x) * art_scale)
	_art.finished.connect(_on_transport_finished)
	visibility_changed.connect(_sync_animation)
	_update_visual_compensation()
	reset_transport()


func set_tool_state(tool_position: Vector2, mouth_position: Vector2, is_active: bool) -> void:
	position = tool_position
	if not tool_position.is_zero_approx():
		rotation = tool_position.angle() + PI
	_mouth_local = (mouth_position - tool_position).rotated(-rotation)
	active = is_active
	_update_visual_compensation()
	queue_redraw()


# Holding a target sustains an already confirmed transport; it never starts one.
func set_capture_engaged(engaged: bool) -> void:
	_capture_engaged = engaged
	if transport_state != TransportState.IDLE:
		transport_state = TransportState.CONTINUOUS if engaged else TransportState.SINGLE


# Called only after a monster has actually been collected.
func play_capture() -> void:
	_art.notify_capture()
	if transport_state == TransportState.IDLE:
		transport_state = (TransportState.CONTINUOUS if _capture_engaged else TransportState.SINGLE)
		_art.play()
	else:
		# Coalesce fast captures into another full cycle without rewinding this one.
		_pending_transport = true


func show_capture_skin(species: PrototypeSlime.Species) -> void:
	match species:
		PrototypeSlime.Species.SLIME:
			_last_capture_skin = VacuumSkin.SkinKind.PINK
		PrototypeSlime.Species.MUCUS:
			_last_capture_skin = VacuumSkin.SkinKind.BLUE
		PrototypeSlime.Species.DRILL:
			_last_capture_skin = VacuumSkin.SkinKind.TEAL
	set_combo_active(_combo_active)


func set_combo_active(value: bool) -> void:
	_combo_active = value
	_art.request_skin(VacuumSkin.SkinKind.RAINBOW if _combo_active else _last_capture_skin)


func play_combo_burst(stage: int, bonus: int) -> void:
	_combo_bursts.append(Vector2i(stage, bonus))
	if not _combo_active and not _combo_restoring:
		_begin_combo_burst()


func _begin_combo_burst() -> void:
	_combo_reward = _combo_bursts.pop_front()
	_combo_hold = 0.30 + _combo_reward.x * 0.06
	_combo_burst_played = false
	set_combo_active(true)


func _advance_combo_burst(delta: float) -> void:
	if _combo_restoring:
		if _art.transition != VacuumSkin.Transition.STABLE:
			return
		_combo_restoring = false
		if not _combo_bursts.is_empty():
			_begin_combo_burst()
	if not _combo_active:
		return
	if (
		_art.current_skin != VacuumSkin.SkinKind.RAINBOW
		or _art.transition != VacuumSkin.Transition.STABLE
	):
		return
	if not _combo_burst_played:
		var burst: ComboBurst = ComboBurstScene.instantiate() as ComboBurst
		$Bursts.add_child(burst)
		burst.top_level = true
		burst.global_transform = Transform2D.IDENTITY
		burst.global_position = _art.get_global_transform_with_canvas().origin
		burst.play(_combo_reward.x, _combo_reward.y)
		_combo_burst_played = true
	_combo_hold = maxf(0.0, _combo_hold - delta)
	if _combo_hold == 0.0:
		set_combo_active(false)
		_combo_restoring = true


func reset_skin() -> void:
	combo_meter.reset_feedback()
	_last_capture_skin = VacuumSkin.SkinKind.DEFAULT
	_combo_active = false
	_combo_hold = 0.0
	_combo_burst_played = false
	_combo_restoring = false
	_combo_bursts.clear()
	for effect: Node in $Bursts.get_children():
		effect.queue_free()
	_art.reset_skin()


func reset_transport(cancelled: bool = true) -> void:
	var was_running: bool = transport_state != TransportState.IDLE
	transport_state = TransportState.IDLE
	_capture_engaged = false
	_pending_transport = false
	_art.seek_frame(0)
	if cancelled and was_running:
		transport_cancelled.emit()


func _process(delta: float) -> void:
	_time += delta
	_advance_combo_burst(delta)
	_update_visual_compensation()
	if visible and active:
		queue_redraw()


func _sync_animation() -> void:
	if not is_visible_in_tree():
		reset_transport()


func _on_transport_finished() -> void:
	if _capture_engaged or _pending_transport:
		_pending_transport = false
		transport_state = (TransportState.CONTINUOUS if _capture_engaged else TransportState.SINGLE)
		_art.play()
	else:
		reset_transport(false)
		transport_finished.emit()


func _update_visual_compensation() -> void:
	var compensation: Transform2D = SurfaceProjection.get_visual_compensation(self)
	# Keep the illustrated tool upright while its suction mouth follows the world pointer.
	var screen_transform: Transform2D = get_global_transform_with_canvas() * compensation
	compensation *= Transform2D(-screen_transform.get_rotation(), Vector2.ZERO)
	compensation.origin = _mouth_local
	_art_root.transform = compensation


func _draw() -> void:
	if active:
		var detail_scale: float = radius / REFERENCE_RADIUS
		var feedback_radius: float = radius * feedback_scale
		draw_circle(_mouth_local, feedback_radius, Color(accent, 0.10))
		draw_arc(
			_mouth_local,
			feedback_radius,
			0.0,
			TAU,
			48,
			Color(accent, 0.65),
			1.3 * detail_scale,
			true
		)
		for particle_index: int in range(6):
			var angle: float = float(particle_index) * TAU / 6.0 + _time * 0.35
			var progress: float = fmod(_time * 1.4 + float(particle_index) / 6.0, 1.0)
			var distance: float = lerpf(
				feedback_radius * particle_spread, 3.0 * detail_scale, progress
			)
			var direction: Vector2 = Vector2.from_angle(angle)
			var particle_point: Vector2 = _mouth_local + direction * distance
			draw_line(
				particle_point,
				particle_point + direction * 2.0 * detail_scale,
				Color(accent, 0.35 + progress * 0.3),
				detail_scale,
				true
			)
