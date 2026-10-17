extends Node

signal presentation_started
signal emergence_progressed(nest_id: int, progress: float)
signal nest_revealed(nest_id: int, species: int)
signal presentation_finished
signal rotation_guide_changed(visible: bool)

const PlanetView = preload("res://scripts/planet_view_controller.gd")
const PopulationPalette = preload("res://scripts/population_palette.gd")
const MonsterBubble = preload("res://scripts/overview_monster_bubble.gd")

enum Phase { IDLE, WAITING, ANTICIPATE, TURN, LAND, ZOOM, HOLD, RISE, RECOVER }

@export var run: PrototypeRun
@export var view: PlanetView
@export var palette: PopulationPalette
@export var bubble: MonsterBubble
@export_group("Timing")
@export_range(0.0, 3.0, 0.05) var anticipation_seconds: float = 2.0
@export_range(0.0, 3.0, 0.05) var turn_seconds: float = 0.9
@export_range(0.0, 1.0, 0.02) var landing_seconds: float = 0.16
@export_range(0.0, 2.0, 0.05) var zoom_seconds: float = 0.45
@export_range(0.0, 3.0, 0.05) var bubble_hold_seconds: float = 1.0
@export_range(0.0, 2.0, 0.05) var emergence_seconds: float = 0.85
@export_range(0.0, 2.0, 0.05) var recovery_seconds: float = 0.55
@export_range(0.0, 30.0, 0.5) var accent_seconds: float = 10.0
@export_range(1.0, 30.0, 0.5) var rotation_guide_seconds: float = 8.0
@export_group("Presentation")
@export_range(0.05, 1.0, 0.05) var anticipation_time_scale: float = 0.18
@export_range(1.0, 1.6, 0.05) var closeup_magnification: float = 1.25
@export_range(0.5, 4.0, 0.1) var bubble_flash_hz: float = 2.0
@export_range(0.02, 0.08, 0.005) var bubble_radius_ratio: float = 0.045

var phase: Phase = Phase.IDLE
var discovered_species: Array[int] = []
var first_discovery_shown: bool = false
var _species: int = -1
var _position: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _bubble_clock: float = 0.0
var _side: float = 1.0
var _nest_id: int = -1
var _saved_time_scale: float = 1.0
var _owns_time_scale: bool = false
var _queued_species: int = -1
var _queued_position: Vector2 = Vector2.ZERO
var _first_guide_pending: bool = false
var _guide_remaining: float = 0.0


func _ready() -> void:
	assert(run != null and view != null and palette != null and bubble != null)
	bubble.hide()


func _exit_tree() -> void:
	_restore_time_scale()


func reset() -> void:
	cancel()
	discovered_species.clear()
	first_discovery_shown = false
	for nest: NestState in run.nests:
		if not discovered_species.has(nest.species):
			discovered_species.append(nest.species)


func cancel() -> void:
	_hide_rotation_guide()
	_first_guide_pending = false
	_restore_time_scale()
	if _nest_id > 0:
		emergence_progressed.emit(_nest_id, 1.0)
		run.finish_nest_discovery(_nest_id)
	if phase >= Phase.ANTICIPATE:
		view.clear_discovery_camera()
		view.presentation_locked = false
	bubble.hide()
	phase = Phase.IDLE
	_species = -1
	_nest_id = -1
	_elapsed = 0.0
	_queued_species = -1


func request_discovery(species: NestState.Species, position: Vector2) -> void:
	if first_discovery_shown and species in discovered_species:
		run.resolve_nest_spawn(position)
		return
	# PrototypeRun permits one unresolved request. A roll after creation waits
	# through RISE/RECOVER until the current camera sequence finishes.
	if phase in [Phase.RISE, Phase.RECOVER]:
		_queued_species = species
		_queued_position = position
		return
	assert(phase == Phase.IDLE)
	_species = species
	_position = position
	phase = Phase.WAITING
	_try_start()


func _try_start() -> void:
	if phase != Phase.WAITING or view.presentation_locked:
		return
	_hide_rotation_guide()
	view.presentation_locked = true
	view.end_drag()
	view.clear_discovery_camera()
	presentation_started.emit()
	_saved_time_scale = Engine.time_scale
	_owns_time_scale = true
	_side = signf(angle_difference(Vector2.UP.angle(), _position.angle() + view.world.rotation))
	if is_zero_approx(_side):
		_side = 1.0
	_bubble_clock = 0.0
	bubble.species = _species
	bubble.modulate = Color.WHITE
	bubble.show()
	_enter(Phase.ANTICIPATE)
	_update_bubble()


func _process(delta: float) -> void:
	if run.is_complete:
		if phase != Phase.IDLE or _guide_remaining > 0.0:
			cancel()
		return
	if _guide_remaining > 0.0:
		_guide_remaining = maxf(0.0, _guide_remaining - delta / maxf(Engine.time_scale, 0.001))
		if _guide_remaining <= 0.0 or view.is_dragging():
			_hide_rotation_guide()
	_try_start()
	if phase < Phase.ANTICIPATE:
		return
	# Presentation timing uses real seconds while the world slows down. SceneTree pause
	# still freezes this node and every phase normally.
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	_elapsed += real_delta
	_bubble_clock += real_delta
	match phase:
		Phase.ANTICIPATE:
			var progress: float = _progress(anticipation_seconds)
			Engine.time_scale = (
				_saved_time_scale
				* lerpf(1.0, anticipation_time_scale, smoothstep(0.0, 0.35, progress))
			)
			if progress >= 1.0:
				_restore_time_scale()
				view.turn_to_discovery(_position.angle(), turn_seconds)
				_enter(Phase.TURN)
		Phase.TURN:
			if not view.is_transitioning():
				_enter(Phase.LAND)
		Phase.LAND:
			if _progress(landing_seconds) >= 1.0:
				view.zoom_discovery(closeup_magnification, zoom_seconds)
				_enter(Phase.ZOOM)
		Phase.ZOOM:
			if not view.is_transitioning():
				_enter(Phase.HOLD)
		Phase.HOLD:
			if _progress(bubble_hold_seconds) >= 1.0:
				_reveal()
		Phase.RISE:
			var progress: float = _progress(emergence_seconds)
			emergence_progressed.emit(_nest_id, progress)
			if progress >= 1.0:
				view.zoom_discovery(1.0, recovery_seconds)
				_enter(Phase.RECOVER)
		Phase.RECOVER:
			if not view.is_transitioning():
				_finish()
	_update_bubble()


func _enter(next_phase: Phase) -> void:
	phase = next_phase
	_elapsed = 0.0


func _progress(seconds: float) -> float:
	return 1.0 if seconds <= 0.0 else clampf(_elapsed / seconds, 0.0, 1.0)


func _reveal() -> void:
	if not run.resolve_nest_spawn(_position, true, true):
		cancel()
		return
	_nest_id = run.nests.back().nest_id
	emergence_progressed.emit(_nest_id, 0.0)
	_first_guide_pending = not first_discovery_shown
	first_discovery_shown = true
	if not discovered_species.has(_species):
		discovered_species.append(_species)
	palette.emphasize_species(_species, accent_seconds)
	nest_revealed.emit(_nest_id, _species)
	_enter(Phase.RISE)


func _finish() -> void:
	var next_species: int = _queued_species
	var next_position: Vector2 = _queued_position
	var show_guide: bool = _first_guide_pending
	cancel()
	if show_guide:
		_guide_remaining = rotation_guide_seconds
		rotation_guide_changed.emit(true)
	presentation_finished.emit()
	if next_species >= 0:
		request_discovery(next_species as NestState.Species, next_position)


func _hide_rotation_guide() -> void:
	_guide_remaining = 0.0
	rotation_guide_changed.emit(false)


func _restore_time_scale() -> void:
	if _owns_time_scale:
		Engine.time_scale = _saved_time_scale
		_owns_time_scale = false


func _update_bubble() -> void:
	if phase < Phase.ANTICIPATE or phase == Phase.RECOVER:
		bubble.hide()
		return
	var size: Vector2 = get_viewport().get_visible_rect().size
	var radius: float = minf(size.x, size.y) * bubble_radius_ratio
	var inset: float = radius * 2.0
	var edge: Vector2 = Vector2(inset if _side < 0.0 else size.x - inset, size.y * 0.36)
	var anchor: Vector2 = view.world.get_global_transform_with_canvas() * _position
	var center: Vector2 = anchor - Vector2(0.0, radius * 2.7)
	center = center.clamp(Vector2(inset, inset), size - Vector2(inset, inset))
	if phase == Phase.ANTICIPATE:
		center = edge
		anchor = edge + Vector2(_side * radius * 3.0, 0.0)
	elif phase == Phase.TURN:
		center = edge.lerp(center, smoothstep(0.0, 1.0, _progress(turn_seconds)))
	var pulse: float = 0.5 - 0.5 * cos(_bubble_clock * TAU * bubble_flash_hz)
	bubble.density = lerpf(0.18, 1.0, pulse)
	bubble.hover_scale = 1.0 + pulse * 0.07
	bubble.modulate.a = 1.0
	if phase == Phase.RISE:
		bubble.modulate.a = 1.0 - smoothstep(0.0, 0.4, _progress(emergence_seconds))
	bubble.show_at(center, anchor, radius)


func capture_save() -> Dictionary:
	return {
		"shown": first_discovery_shown,
		"species": discovered_species.duplicate(),
		"pending_position": _queued_position if _queued_species >= 0 else _position,
	}


func restore_save(data: Dictionary) -> void:
	reset()
	first_discovery_shown = data.shown
	discovered_species.assign(data.species)
	for nest: NestState in run.nests:
		if nest.species not in discovered_species:
			discovered_species.append(nest.species)
	if run._pending_nest_species >= 0:
		request_discovery(run._pending_nest_species as NestState.Species, data.pending_position)
