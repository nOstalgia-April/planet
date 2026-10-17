extends PrototypeSlime

const SharedCache = preload("res://scripts/art_resource_cache.gd")

const ItemArt = preload("res://scripts/物品动画/动画物件.gd")
var _visible_texture_bounds: Dictionary[Texture2D, Rect2] = SharedCache.texture_bounds(
	&"planet_drill_monster_bounds"
)
enum Phase { LAUNCH, DIVE, TRAVEL, PAUSE, EMERGE, EXPOSED }

@export var ordinary_art: ItemArt
@export var valuable_art: ItemArt
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
var _exposed_art_rect: Rect2
var art: ItemArt
var _art_sprite: Sprite2D


func _ready() -> void:
	for view: ItemArt in [ordinary_art, valuable_art]:
		_prepare_animations(view)
	_select_art()


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


func apply_capture(delta: float, capture_seconds: float, target: Vector2) -> bool:
	if not can_capture():
		return false
	return super.apply_capture(delta, capture_seconds, target)


func release_capture(delta: float) -> void:
	super.release_capture(delta)
	capture_progress = 0.0


func get_capture_hit_rect() -> Rect2:
	# Keep bounds independent of changing facial frames.
	return get_global_transform_with_canvas() * _get_base_art_transform() * _exposed_art_rect


func set_simulation_speed(value: float) -> void:
	super.set_simulation_speed(value)
	for view: ItemArt in [ordinary_art, valuable_art]:
		view.animation_player.speed_scale = value


func _process(delta: float) -> void:
	delta *= simulation_speed
	if consumed or surface == null:
		return
	_update_surface_rotation()
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
			# Count the first long leg as one of the total 2–5 movements.
			_turns_remaining = _roll_travel_leg_count() - 1
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


func _roll_travel_leg_count() -> int:
	# Rounded normal distribution (center 3, sigma 1), truncated to 2–5.
	# Resample outliers instead of piling them up at the limits.
	var count: int = roundi(_rng.randfn(3.0, 1.0))
	while count < 2 or count > 5:
		count = roundi(_rng.randfn(3.0, 1.0))
	return count


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
	art.transform = _get_base_art_transform()
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
	if not _capture_active or consumed or capture_progress <= 0.02:
		return
	# The mole keeps its full-size art during suction, so its ring must not shrink.
	# Use the stable exposed bounds to keep it outside both facial animations.
	var ring_radius: float = _exposed_art_rect.size.length() * 0.5 + 4.0
	draw_set_transform_matrix(_get_base_art_transform())
	draw_arc(
		_exposed_art_rect.get_center(),
		ring_radius,
		-PI / 2.0,
		-PI / 2.0 + TAU * capture_progress,
		64,
		Color("809c69"),
		1.5 / get_presentation_scale(),
		true
	)


const DRILL_SAVE_FIELDS: PackedStringArray = [
	"phase",
	"phase_remaining",
	"_turns_remaining",
	"_travel_direction",
	"_travel_target",
	"_launch_progress",
]


func capture_save() -> Dictionary:
	var data: Dictionary = super.capture_save()
	data["drill"] = SaveFields.capture(self, DRILL_SAVE_FIELDS)
	data["clip"] = art.animation_player.assigned_animation
	data["clip_time"] = art.animation_player.current_animation_position
	return data


func restore_save(data: Dictionary) -> void:
	super.restore_save(data)
	SaveFields.restore(self, data.drill, DRILL_SAVE_FIELDS)
	_capture_active = false
	art.play_clip(data.clip)
	art.animation_player.seek(data.clip_time, true)
	if phase == Phase.EXPOSED:
		_cache_exposed_art_rect()
	_sync_art()
