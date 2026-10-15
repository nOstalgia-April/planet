extends PrototypeSlime

const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
const CaptureCue = preload("res://scripts/effects/mole_capture_cue.gd")
const HOVER_POP_SECONDS: float = 0.2
static var _visible_texture_bounds: Dictionary[Texture2D, Rect2] = {}
enum Phase { LAUNCH, DIVE, TRAVEL, PAUSE, EMERGE, EXPOSED }

@export var ordinary_art: ItemArt
@export var valuable_art: ItemArt
@export var capture_cue: CaptureCue
@export_group("Hold capture")
@export_range(0.1, 3.0, 0.05) var capture_hold_seconds: float = 0.5
@export_range(0.0, 3.0, 0.5) var hover_pop_height: float = 3.0
@export_group("Drill movement")
@export_range(0.1, 1.0, 0.01) var range_fraction: float = 2.0 / 3.0
@export_range(10.0, 120.0, 1.0) var tunnel_speed: float = 55.0
@export var long_travel_seconds: Vector2 = Vector2(6.0, 10.0)
@export var short_travel_seconds: Vector2 = Vector2(1.0, 2.0)
@export var pause_seconds: Vector2 = Vector2(0.35, 0.7)
@export_range(1.0, 10.0, 0.1) var exposed_seconds: float = 3.5

var phase: Phase = Phase.LAUNCH
var phase_remaining: float = 0.0
var _turns_remaining: int = 0
var _travel_direction: float = 1.0
var _travel_target: Vector2
var _launch_progress: float = 0.0
var _capture_active: bool = false
var _capture_hovered: bool = false
var _hover_pop_remaining: float = 0.0
var _exposed_art_rect: Rect2
var art: ItemArt
var _art_sprite: Sprite2D


func _ready() -> void:
	assert(capture_cue != null, "Drill monster requires its hold capture cue.")
	for view: ItemArt in [ordinary_art, valuable_art]:
		_prepare_animations(view)
	_select_art()
	capture_cue.set_progress(0.0)
	capture_cue.set_holding(false)
	capture_cue.set_active(false)


func _prepare_animations(view: ItemArt) -> void:
	# Animation resources are shared by every actor and the art preview.
	# Looping belongs to this runtime instance, not the source animation scene.
	var library: AnimationLibrary = (
		view.animation_player.get_animation_library(&"").duplicate() as AnimationLibrary
	)
	for clip: StringName in library.get_animation_list():
		var animation: Animation = library.get_animation(clip).duplicate() as Animation
		animation.loop_mode = (
			Animation.LOOP_LINEAR if clip in [&"鼓包", &"夹夹"] else Animation.LOOP_NONE
		)
		library.remove_animation(clip)
		library.add_animation(clip, animation)
	view.animation_player.remove_animation_library(&"")
	view.animation_player.add_animation_library(&"", library)


func _select_art() -> void:
	var clip: StringName = &"鼓包"
	var clip_time: float = 0.0
	if art != null:
		clip = art.animation_player.assigned_animation
		clip_time = art.animation_player.current_animation_position
	for view: ItemArt in [ordinary_art, valuable_art]:
		view.hide()
		view.animation_player.stop()
	art = valuable_art if high_value else ordinary_art
	_art_sprite = art.get_node("画面/贴图") as Sprite2D
	art.show()
	art.play_clip(clip)
	art.animation_player.seek(clip_time, true)
	if phase == Phase.EXPOSED:
		_cache_exposed_art_rect()
		if _capture_active:
			art.set_suction(true)
			art.show_frame(&"吸入", 0)


func setup(
	owner_id: int, home: Vector2, planet_surface: PlanetSurface, screen_half_angle: float = 0.875
) -> void:
	super.setup(owner_id, home, planet_surface, screen_half_angle)
	assert(art != null, "Drill monster requires its animated art.")
	position = _home
	species = Species.DRILL
	body_size = 20.0
	_reset_capture_feedback()


func configure_species(_kind: Species, valuable: bool, _candy_reward: int) -> void:
	species = Species.DRILL
	high_value = valuable
	reward = 0
	_select_art()
	_sync_art()


func launch(direction: Vector2) -> void:
	_launch_start = _home
	_launch_end = surface.project_to_surface(_home * 0.8 + direction * 20.0)
	position = _home
	_launch_progress = 0.0
	_travel_direction = -1.0 if _rng.randf() < 0.5 else 1.0
	_enter_phase(Phase.LAUNCH, 1.0, &"跳出")


func can_capture() -> bool:
	return not consumed and phase == Phase.EXPOSED


func can_net_capture() -> bool:
	return false


func can_fuse() -> bool:
	return false


func is_anchored() -> bool:
	return false


func apply_attraction(_delta: float, _target: Vector2, _strength: float) -> void:
	pass


func apply_capture(delta: float, _capture_seconds: float, _target: Vector2) -> bool:
	if not can_capture() or not _capture_hovered:
		return false
	_set_suction_expression(true)
	capture_progress = minf(1.0, capture_progress + delta / maxf(capture_hold_seconds, 0.1))
	capture_cue.set_holding(true)
	capture_cue.set_progress(capture_progress)
	consumed = capture_progress >= 1.0
	if consumed:
		_capture_hovered = false
		capture_cue.set_active(false)
	return consumed


func release_capture(_delta: float) -> void:
	_set_suction_expression(false)
	capture_progress = 0.0
	capture_cue.set_progress(0.0)
	capture_cue.set_holding(false)


func set_capture_hovered(active: bool) -> void:
	var hovered: bool = active and can_capture()
	if hovered == _capture_hovered:
		return
	_capture_hovered = hovered
	capture_cue.set_active(hovered)
	if hovered:
		_hover_pop_remaining = HOVER_POP_SECONDS
	else:
		release_capture(0.0)
	_sync_art()


func get_capture_hit_rect() -> Rect2:
	# Deliberately exclude the hover lift and changing facial frames.
	return get_global_transform_with_canvas() * _get_base_art_transform() * _exposed_art_rect


func _process(delta: float) -> void:
	if consumed or surface == null:
		return
	_update_surface_rotation()
	_hover_pop_remaining = maxf(0.0, _hover_pop_remaining - delta)
	if phase != Phase.EXPOSED or not _capture_active:
		phase_remaining -= delta
	match phase:
		Phase.LAUNCH:
			_launch_progress = minf(1.0, _launch_progress + delta)
			position = _launch_start.lerp(_launch_end, _launch_progress)
		Phase.TRAVEL:
			_move_on_surface(_travel_target, tunnel_speed * delta)
			if position.distance_to(_travel_target) < 2.0:
				phase_remaining = 0.0
	if phase_remaining <= 0.0:
		_advance_phase()
	_sync_art()


func _advance_phase() -> void:
	match phase:
		Phase.LAUNCH, Phase.EXPOSED:
			_enter_phase(Phase.DIVE, 0.875, &"钻地")
			# The source includes an emergence before the dive; use its descending half.
			art.animation_player.seek(1.0, true)
		Phase.DIVE:
			_turns_remaining = _rng.randi_range(2, 3)
			_begin_travel(true)
		Phase.TRAVEL:
			_enter_phase(Phase.PAUSE, _rng.randf_range(pause_seconds.x, pause_seconds.y), &"鼓包")
		Phase.PAUSE:
			if _turns_remaining > 0:
				_turns_remaining -= 1
				_travel_direction *= -1.0
				_begin_travel(false)
			else:
				_enter_phase(Phase.EMERGE, 1.0, &"跳出")
		Phase.EMERGE:
			_enter_phase(Phase.EXPOSED, exposed_seconds, &"夹夹")


func _begin_travel(long_leg: bool) -> void:
	var times: Vector2 = long_travel_seconds if long_leg else short_travel_seconds
	var duration: float = _rng.randf_range(times.x, times.y)
	var offset: float = angle_difference(_home.angle(), position.angle())
	var half_arc: float = PI * range_fraction
	var distance: float = tunnel_speed * duration
	var next_offset: float = offset + _travel_direction * distance / maxf(position.length(), 1.0)
	if absf(next_offset) > half_arc:
		_travel_direction *= -1.0
		next_offset = offset + _travel_direction * distance / maxf(position.length(), 1.0)
	next_offset = clampf(next_offset, -half_arc, half_arc)
	# Keep each leg below pi so the surface mover never shortcuts across the forbidden arc.
	next_offset = offset + clampf(next_offset - offset, -2.5, 2.5)
	var angle: float = _home.angle() + next_offset
	var bounds: Vector2 = surface.get_activity_radius_bounds(angle)
	_travel_target = (
		Vector2.from_angle(angle) * lerpf(bounds.x, bounds.y, _rng.randf_range(0.3, 0.85))
	)
	_enter_phase(Phase.TRAVEL, duration, &"鼓包")


func _enter_phase(next: Phase, seconds: float, clip: StringName) -> void:
	_reset_capture_feedback()
	phase = next
	phase_remaining = seconds
	art.play_clip(clip)
	if phase == Phase.EXPOSED:
		_cache_exposed_art_rect()
	_sync_art()


func _reset_capture_feedback() -> void:
	release_capture(0.0)
	_capture_hovered = false
	_hover_pop_remaining = 0.0
	capture_cue.set_active(false)


func _cache_exposed_art_rect() -> void:
	var clip: StringName = art.animation_player.assigned_animation
	var clip_time: float = art.animation_player.current_animation_position
	art.show_frame(&"夹夹", 0)
	_exposed_art_rect = _get_art_rect()
	art.play_clip(clip)
	art.animation_player.seek(clip_time, true)


func _set_suction_expression(active: bool) -> void:
	if active == _capture_active:
		return
	_capture_active = active
	art.set_suction(active)
	if active:
		art.show_frame(&"吸入", 0)


func _get_base_art_transform() -> Transform2D:
	var multiplier: float = get_presentation_scale()
	return (
		SurfaceProjection.get_visual_compensation(self)
		* Transform2D(0.0, Vector2.ONE * multiplier, 0.0, Vector2(0.0, get_presentation_sink()))
	)


func _sync_art() -> void:
	var feedback_offset: Vector2 = Vector2.ZERO
	if _hover_pop_remaining > 0.0:
		var progress: float = 1.0 - _hover_pop_remaining / HOVER_POP_SECONDS
		feedback_offset.y -= sin(progress * PI) * clampf(hover_pop_height, 0.0, 3.0)
	art.transform = _get_base_art_transform() * Transform2D(0.0, feedback_offset)
	if phase == Phase.LAUNCH:
		art.position.y -= sin(_launch_progress * PI) * 35.0
	if _capture_hovered:
		_sync_capture_cue()


func _sync_capture_cue() -> void:
	var bounds: Rect2 = get_capture_hit_rect()
	var anchor: Vector2 = Vector2(bounds.get_center().x, bounds.position.y - 6.0)
	# The hint remains upright and readable as the planet rotates or changes projection.
	capture_cue.transform = (
		get_global_transform_with_canvas().affine_inverse() * Transform2D(0.0, anchor)
	)


func refresh_presentation() -> void:
	_sync_art()
	queue_redraw()


func _get_art_rect() -> Rect2:
	var texture: Texture2D = _art_sprite.texture
	if not _visible_texture_bounds.has(texture):
		_visible_texture_bounds[texture] = Rect2(texture.get_image().get_used_rect())
	return (
		_art_sprite.get_parent().transform
		* _art_sprite.transform
		* _visible_texture_bounds[texture]
	)


func _get_body_center_offset() -> Vector2:
	return art.transform * _get_art_rect().get_center()


func get_visual_rect() -> Rect2:
	return art.get_global_transform_with_canvas() * _get_art_rect()


func get_source_texture() -> Texture2D:
	return _art_sprite.texture


func _draw() -> void:
	pass
