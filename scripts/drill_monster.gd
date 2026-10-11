extends PrototypeSlime

const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
static var _visible_texture_bounds: Dictionary[Texture2D, Rect2] = {}
enum Phase { LAUNCH, DIVE, TRAVEL, PAUSE, EMERGE, EXPOSED }

@export var art: ItemArt
@export_group("Drill movement")
@export_range(0.1, 1.0, 0.01) var range_fraction: float = 2.0 / 3.0
@export_range(10.0, 120.0, 1.0) var tunnel_speed: float = 55.0
@export var long_travel_seconds: Vector2 = Vector2(6.0, 10.0)
@export var short_travel_seconds: Vector2 = Vector2(1.0, 2.0)
@export var pause_seconds: Vector2 = Vector2(0.35, 0.7)
@export_range(1.0, 10.0, 0.1) var exposed_seconds: float = 3.5
@export_range(0.1, 1.0, 0.01) var art_scale: float = 0.36

var phase: Phase = Phase.LAUNCH
var phase_remaining: float = 0.0
var _turns_remaining: int = 0
var _travel_direction: float = 1.0
var _travel_target: Vector2
var _launch_progress: float = 0.0

@onready var _art_sprite: Sprite2D = art.get_node("画面/贴图") as Sprite2D


func _ready() -> void:
	# Animation resources are shared by every actor and the art preview.
	# Looping belongs to this runtime instance, not the source animation scene.
	var library: AnimationLibrary = (
		art.animation_player.get_animation_library(&"").duplicate() as AnimationLibrary
	)
	for clip: StringName in library.get_animation_list():
		var animation: Animation = library.get_animation(clip).duplicate() as Animation
		animation.loop_mode = (
			Animation.LOOP_LINEAR if clip in [&"鼓包", &"夹夹"] else Animation.LOOP_NONE
		)
		library.remove_animation(clip)
		library.add_animation(clip, animation)
	art.animation_player.remove_animation_library(&"")
	art.animation_player.add_animation_library(&"", library)


func setup(
	owner_id: int, home: Vector2, planet_surface: PlanetSurface, screen_half_angle: float = 0.875
) -> void:
	super.setup(owner_id, home, planet_surface, screen_half_angle)
	assert(art != null, "Drill monster requires its animated art.")
	position = _home
	species = Species.DRILL
	body_size = 20.0


func configure_species(_kind: Species, _valuable: bool, _candy_reward: int) -> void:
	species = Species.DRILL
	high_value = false
	reward = 0


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


func apply_attraction(delta: float, target: Vector2, strength: float) -> void:
	if can_capture():
		super.apply_attraction(delta, target, strength)


func apply_capture(delta: float, capture_seconds: float, target: Vector2) -> bool:
	if not can_capture():
		return false
	var completed: bool = super.apply_capture(delta, capture_seconds, target)
	_sync_art()
	return completed


func _process(delta: float) -> void:
	if consumed or surface == null:
		return
	_update_surface_rotation()
	# Once suction starts, allow it to finish; releasing resumes the peek timer.
	_capture_hold = maxf(0.0, _capture_hold - delta)
	if _capture_hold > 0.0:
		_sync_art()
		return
	_set_suction_expression(false)
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
			capture_progress = 0.0
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
	phase = next
	phase_remaining = seconds
	art.play_clip(clip)
	_sync_art()


func _set_suction_expression(active: bool) -> void:
	art.set_suction(active)


func _sync_art() -> void:
	var multiplier: float = art_scale * get_presentation_scale()
	var shrink: float = lerpf(1.0, 0.1, capture_progress)
	art.transform = SurfaceProjection.get_visual_compensation(self).scaled_local(
		Vector2.ONE * multiplier * shrink
	)
	art.position += SurfaceProjection.get_visual_compensation(self).basis_xform(
		Vector2(0.0, get_presentation_sink())
	)
	if phase == Phase.LAUNCH:
		art.position.y -= sin(_launch_progress * PI) * 35.0


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
