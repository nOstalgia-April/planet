class_name OverviewEcology
extends Node2D

const PLANET_SCENE: PackedScene = preload("res://scenes/world/planet_surface.tscn")
const BUBBLE_SCENE: PackedScene = preload("res://scenes/world/overview_monster_bubble.tscn")
const Bubble = preload("res://scripts/overview_monster_bubble.gd")
const Layout = preload("res://scripts/overview_bubble_layout.gd")

@export var slime_color: Color = Color("f43187")
@export var mucus_color: Color = Color("397cf5")
@export var neutral_color: Color = Color("625e69")
@export_range(1.0, 12.0, 0.5) var transition_speed: float = 7.0
@export_group("Distribution")
@export_range(0.05, 0.15, 0.001) var minimum_radius_ratio: float = Layout.REFERENCE_MINIMUM_RATIO
@export_range(0.16, 0.3, 0.001) var maximum_radius_ratio: float = Layout.REFERENCE_MAXIMUM_RATIO
@export_range(2, 200, 1) var population_at_maximum: int = 48
@export_range(15.0, 45.0, 1.0) var maximum_cluster_degrees: float = 30.0
@export_group("Placement")
@export_range(0.0, 1.0, 0.05) var maximum_nudge_radii: float = 0.8
@export_range(0.0, 12.0, 0.5) var bubble_clearance: float = 2.0
@export_group("Hover Motion")
@export_range(10.0, 100.0, 1.0) var return_spring: float = 32.0
@export_range(2.0, 20.0, 0.5) var water_drag: float = 6.0
@export_range(20.0, 240.0, 5.0) var push_strength: float = 130.0
@export_range(0.0, 0.8, 0.05) var hover_clearance_radii: float = 0.35
@export_range(0.0, 1.5, 0.05) var extra_motion_radii: float = 0.8
@export_group("Preview")
@export var preview_populations: Vector2i = Vector2i(48, 14)

# Totals support the existing ecology/backdrop consumers. These do not size a
# marker: bubble_radii/centers expose the largest LOCAL cluster per species.
var population_counts: Vector2i = Vector2i.ZERO
var bubble_radii: Vector2 = Vector2.ZERO
var bubble_centers: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var backdrop_color: Color = Color("625e69")
var clusters: Array[Layout.Cluster] = []
var bubbles: Array[Bubble] = []

var _layout: Layout = Layout.new()
var _retiring: Array[Bubble] = []
var _surface: PlanetSurface
var _world: Node2D
var _viewport_size: Vector2 = Vector2(1280.0, 800.0)
var _planet_center: Vector2 = Vector2(640.0, 400.0)
var _planet_radius: float = 265.0
var _visual_scale: float = 1.0
var _target_color: Color = Color("625e69")
var _is_overview: bool = false
var _preview: bool = false
var _view_opacity: float = 1.0
var _layout_dirty: bool = true
var _layout_origins: PackedVector2Array = PackedVector2Array()
var _layout_radii: PackedFloat32Array = PackedFloat32Array()
var _hovered_bubble: Bubble

@onready var _backdrop_layer: CanvasLayer = $Backdrop
@onready var _backdrop: ColorRect = $Backdrop/Color
@onready var _bubble_root: Node2D = $Bubbles


func _ready() -> void:
	set_process(false)
	if get_tree().current_scene == self:
		_start_preview.call_deferred()


func configure(surface: PlanetSurface, world: Node2D) -> void:
	assert(surface != null and world != null, "Overview requires the planet and world.")
	_surface = surface
	_world = world
	backdrop_color = neutral_color
	_target_color = neutral_color


func update_ecology(
	positions: PackedVector2Array,
	kinds: PackedInt32Array,
	is_overview: bool,
	viewport_size: Vector2,
	populations: PackedInt32Array = PackedInt32Array()
) -> void:
	assert(_surface != null and _world != null)
	assert(viewport_size.x > 0.0 and viewport_size.y > 0.0)
	assert(positions.size() == kinds.size())
	assert(populations.is_empty() or populations.size() == positions.size())
	population_counts = Vector2i.ZERO
	for index: int in range(kinds.size()):
		var kind: int = kinds[index]
		assert(kind >= 0 and kind < 2, "Supply the existing live monster species.")
		population_counts[kind] += populations[index] if not populations.is_empty() else 1
	_viewport_size = viewport_size
	_visual_scale = minf(viewport_size.x / 1280.0, viewport_size.y / 800.0)
	_is_overview = is_overview
	if not is_overview:
		_clear_markers()
		set_view_opacity(_view_opacity)
		return
	_layout.minimum_ratio = minimum_radius_ratio
	_layout.maximum_ratio = maximum_radius_ratio
	_layout.population_at_maximum = population_at_maximum
	_layout.maximum_cluster_span = deg_to_rad(maximum_cluster_degrees)
	var next: Array[Layout.Cluster] = _layout.build(positions, kinds, clusters, populations)
	_assign_bubbles(next)
	clusters = next
	_layout_dirty = true
	_target_color = neutral_color
	var total: int = population_counts.x + population_counts.y
	if total > 0:
		var balance: float = float(population_counts.x - population_counts.y) / float(total)
		var dominant: Color = slime_color if balance > 0.0 else mucus_color
		_target_color = neutral_color.lerp(dominant, pow(absf(balance), 0.55))
	set_view_opacity(_view_opacity)
	_sync_geometry(0.0)


func _clear_markers() -> void:
	_set_hovered_bubble(null)
	for bubble: Bubble in bubbles:
		bubble.queue_free()
	for bubble: Bubble in _retiring:
		bubble.queue_free()
	bubbles.clear()
	_retiring.clear()
	clusters.clear()
	bubble_radii = Vector2.ZERO
	bubble_centers.fill(Vector2.ZERO)
	_layout_dirty = true


func _assign_bubbles(next: Array[Layout.Cluster]) -> void:
	var available: Array[Bubble] = bubbles.duplicate()
	bubbles.clear()
	for cluster: Layout.Cluster in next:
		var best: Bubble
		var best_distance: float = deg_to_rad(maximum_cluster_degrees)
		for candidate: Bubble in available:
			if candidate.species != cluster.species:
				continue
			var distance: float = absf(angle_difference(candidate.angle, cluster.angle))
			if distance < best_distance:
				best = candidate
				best_distance = distance
		if best == null:
			best = BUBBLE_SCENE.instantiate() as Bubble
			best.species = cluster.species
			best.angle = cluster.angle
			best.radius_ratio = cluster.radius_ratio
			_bubble_root.add_child(best)
		else:
			available.erase(best)
		best.cluster = cluster
		bubbles.append(best)
	for old: Bubble in available:
		if old == _hovered_bubble:
			_set_hovered_bubble(null)
		_retiring.append(old)


func set_view_opacity(value: float) -> void:
	_view_opacity = value
	visible = _is_overview and value > 0.0
	modulate.a = value
	_backdrop_layer.visible = visible
	_backdrop.modulate.a = value
	set_process(visible)
	if not visible or value < 0.99:
		_set_hovered_bubble(null)


func update_hover(viewport_position: Vector2, enabled: bool) -> void:
	_set_hovered_bubble(get_bubble_at(viewport_position) if enabled else null)


func _set_hovered_bubble(bubble: Bubble) -> void:
	if bubble == _hovered_bubble:
		return
	if _hovered_bubble != null:
		_hovered_bubble.z_index = 0
	_hovered_bubble = bubble
	if bubble != null:
		bubble.z_index = 2
	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if bubble != null else Input.CURSOR_ARROW
	)


func _exit_tree() -> void:
	if _hovered_bubble != null:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func get_bubble_at(viewport_position: Vector2) -> Bubble:
	if not _is_overview or not is_visible_in_tree() or _view_opacity <= 0.01:
		return null
	# Keep a small release margin so a moving edge cannot alternate hover every frame.
	if (
		_hovered_bubble != null
		and _hovered_bubble.contains_viewport_point(
			viewport_position, _hovered_bubble.radius * 0.05
		)
	):
		return _hovered_bubble
	var selected: Bubble = null
	for bubble: Bubble in bubbles:
		if not bubble.is_visible_in_tree() or bubble.opacity <= 0.01:
			continue
		if not bubble.contains_viewport_point(viewport_position):
			continue
		# Match the draw order when live bubbles overlap; fading retired bubbles
		# are deliberately absent from this list and cannot navigate to stale data.
		if selected == null or bubble.get_index() > selected.get_index():
			selected = bubble
	return selected


func _process(delta: float) -> void:
	if _preview:
		_sync_preview_view()
		update_hover(get_viewport().get_mouse_position(), get_window().has_focus())
	var blend: float = 1.0 - exp(-delta * transition_speed)
	backdrop_color = backdrop_color.lerp(_target_color, blend)
	_backdrop.color = backdrop_color.darkened(0.84)
	_sync_geometry(blend, delta)
	for old: Bubble in _retiring.duplicate():
		old.opacity = lerpf(old.opacity, 0.0, blend)
		old.modulate.a = old.opacity
		_update_preferred(old)
		var step: float = clampf(delta, 0.0, 1.0 / 30.0)
		old.advance_hover(step, false)
		old.motion_velocity *= exp(-water_drag * step)
		old.motion_offset += old.motion_velocity * step
		old.show_at(_offset_position(old, old.motion_offset), old.anchor, old.radius)
		if old.opacity < 0.01 or not _is_overview:
			_retiring.erase(old)
			old.queue_free()


func _sync_geometry(blend: float, delta: float = 0.0) -> void:
	var transform: Transform2D = _surface.get_global_transform_with_canvas()
	_planet_center = transform.origin
	_planet_radius = _surface.radius * PlanetSurface.SURFACE_RADIUS_RATIO * transform.x.length()
	_backdrop.size = _viewport_size
	_layout_dirty = _layout_dirty or _layout_origins.size() != bubbles.size()
	var movement_limit: float = 2.0 * _visual_scale
	var index: int = 0
	for bubble: Bubble in bubbles:
		bubble.angle = lerp_angle(bubble.angle, bubble.cluster.angle, blend)
		bubble.radius_ratio = lerpf(bubble.radius_ratio, bubble.cluster.radius_ratio, blend)
		bubble.opacity = lerpf(bubble.opacity, 1.0, blend)
		bubble.modulate.a = bubble.opacity
		_update_preferred(bubble)
		bubble.position = _offset_position(bubble, bubble.offset)
		if not _layout_dirty:
			_layout_dirty = (
				bubble.preferred.distance_to(_layout_origins[index]) > movement_limit
				or absf(bubble.radius - _layout_radii[index]) > 0.5 * _visual_scale
			)
		index += 1
	# Bounded local search, never an orbit-wide hunt for an empty slot. Alternating
	# sweeps let both species share the small displacement instead of evicting one.
	if _layout_dirty:
		for sweep: int in range(3):
			for step: int in range(bubbles.size()):
				var placed_index: int = step if sweep % 2 == 0 else bubbles.size() - step - 1
				_place_bubble(bubbles[placed_index])
		_layout_origins.clear()
		_layout_radii.clear()
		for bubble: Bubble in bubbles:
			_layout_origins.append(bubble.preferred)
			_layout_radii.append(bubble.radius)
		_layout_dirty = false
	for bubble: Bubble in bubbles:
		if not bubble.motion_initialized:
			bubble.motion_offset = bubble.offset
			bubble.motion_initialized = true
	_advance_motion(delta)
	bubble_radii = Vector2.ZERO
	bubble_centers.fill(Vector2.ZERO)
	for bubble: Bubble in bubbles:
		bubble.show_at(_offset_position(bubble, bubble.motion_offset), bubble.anchor, bubble.radius)
		if bubble.radius > bubble_radii[bubble.species]:
			bubble_radii[bubble.species] = bubble.radius
			bubble_centers[bubble.species] = bubble.position


func _advance_motion(delta: float) -> void:
	# Small bounded substeps keep the springs stable after a slow frame or resize.
	# Motion is relative to the geographical anchor, so spinning never leaves a marker behind.
	var remaining: float = clampf(delta, 0.0, 0.1)
	while remaining > 0.000001:
		var step: float = minf(remaining, 1.0 / 120.0)
		remaining -= step
		var interaction_pressure: float = 0.0
		for bubble: Bubble in bubbles:
			bubble.advance_hover(step, bubble == _hovered_bubble)
			bubble.position = _offset_position(bubble, bubble.motion_offset)
			interaction_pressure = maxf(
				interaction_pressure,
				(bubble.hover_scale - 1.0) / (bubble.hover_magnification - 1.0)
			)
		var forces: PackedVector2Array = PackedVector2Array()
		for bubble: Bubble in bubbles:
			var force: Vector2 = (bubble.offset - bubble.motion_offset) * return_spring
			for other: Bubble in bubbles:
				if other == bubble or interaction_pressure <= 0.001:
					continue
				var difference: Vector2 = bubble.position - other.position
				var distance: float = difference.length()
				var reach: float = (
					bubble.radius * bubble.hover_scale
					+ other.radius * other.hover_scale
					+ 2.0 * _visual_scale
				)
				var hover_pressure: float = maxf(
					(bubble.hover_scale - 1.0) / (bubble.hover_magnification - 1.0),
					(other.hover_scale - 1.0) / (other.hover_magnification - 1.0)
				)
				if (
					hover_pressure <= 0.001
					and bubble.motion_offset.distance_squared_to(bubble.offset) < 0.0001
					and other.motion_offset.distance_squared_to(other.offset) < 0.0001
				):
					continue
				reach += (
					minf(bubble.radius, other.radius)
					* hover_clearance_radii
					* maxf(0.0, hover_pressure)
				)
				if distance >= reach:
					continue
				var direction: Vector2 = (
					difference / distance
					if distance > 0.01
					else Vector2.UP.rotated(float(bubble.get_index()) * 2.4)
				)
				var mobility: float = 0.12 if bubble == _hovered_bubble else 1.0
				# Pressure can propagate through neighbors while interacting, then
				# decays to zero so idle markers return to the exact density layout.
				var push: Vector2 = (
					direction
					* (reach - distance)
					* push_strength
					* mobility
					* minf(1.0, interaction_pressure)
				)
				force += _local_motion(bubble, push)
			forces.append(force)
		for index: int in range(bubbles.size()):
			var bubble: Bubble = bubbles[index]
			bubble.motion_velocity += forces[index] * step
			bubble.motion_velocity *= exp(-water_drag * step)
			bubble.motion_velocity = bubble.motion_velocity.limit_length(4.0)
			bubble.motion_offset += bubble.motion_velocity * step
			if (
				bubble.motion_offset.distance_to(bubble.offset) < 0.001
				and bubble.motion_velocity.length() < 0.001
			):
				bubble.motion_offset = bubble.offset
				bubble.motion_velocity = Vector2.ZERO
			var limit: float = maximum_nudge_radii + extra_motion_radii
			if bubble.motion_offset.length() > limit:
				var outward: Vector2 = bubble.motion_offset.normalized()
				bubble.motion_offset = outward * limit
				bubble.motion_velocity -= outward * maxf(0.0, bubble.motion_velocity.dot(outward))
	# A last boundary constraint keeps the enlarged circle clickable at window edges.
	for bubble: Bubble in bubbles:
		var inset: float = bubble.radius * bubble.hover_scale + 4.0 * _visual_scale
		var point: Vector2 = _offset_position(bubble, bubble.motion_offset)
		var correction: Vector2 = (
			point.clamp(Vector2.ONE * inset, _viewport_size - Vector2.ONE * inset) - point
		)
		if not correction.is_zero_approx():
			bubble.motion_offset += _local_motion(bubble, correction)
			var inward: Vector2 = _local_motion(bubble, correction).normalized()
			bubble.motion_velocity -= inward * minf(0.0, bubble.motion_velocity.dot(inward))


func _local_motion(bubble: Bubble, screen_vector: Vector2) -> Vector2:
	var outward: Vector2 = (bubble.anchor - _planet_center).normalized()
	return (
		Vector2(screen_vector.dot(outward), screen_vector.dot(outward.orthogonal())) / bubble.radius
	)


func _update_preferred(bubble: Bubble) -> void:
	var direction: Vector2 = Vector2.from_angle(bubble.angle)
	bubble.anchor = (
		_world.get_global_transform_with_canvas()
		* (direction * _surface.get_outer_radius(bubble.angle))
	)
	var outward: Vector2 = (bubble.anchor - _planet_center).normalized()
	bubble.radius = bubble.radius_ratio * _planet_radius
	bubble.preferred = (
		bubble.anchor
		+ outward * (bubble.radius * Layout.POINTER_REACH + bubble_clearance * _visual_scale)
	)


func _offset_position(bubble: Bubble, offset: Vector2) -> Vector2:
	var outward: Vector2 = (bubble.anchor - _planet_center).normalized()
	return bubble.preferred + (outward * offset.x + outward.orthogonal() * offset.y) * bubble.radius


func _place_bubble(bubble: Bubble) -> void:
	var choices: PackedVector2Array = PackedVector2Array(
		[Vector2.ZERO, bubble.offset.limit_length(maximum_nudge_radii)]
	)
	for ring: float in [0.5, 1.0]:
		for step: int in range(12):
			choices.append(
				Vector2.from_angle(float(step) * TAU / 12.0) * maximum_nudge_radii * ring
			)
	var best: Vector2 = bubble.offset
	var best_score: float = INF
	for offset: Vector2 in choices:
		var point: Vector2 = _offset_position(bubble, offset)
		var score: float = _placement_score(bubble, point, offset)
		if score < best_score:
			best_score = score
			best = offset
	bubble.offset = best
	bubble.position = _offset_position(bubble, best)


func _placement_score(bubble: Bubble, point: Vector2, offset: Vector2) -> float:
	var radius: float = bubble.radius
	var score: float = offset.length_squared() + offset.distance_squared_to(bubble.offset) * 0.2
	var inset: float = radius + 4.0 * _visual_scale
	var screen: Rect2 = Rect2(Vector2.ONE * inset, _viewport_size - Vector2.ONE * inset * 2.0)
	var clipped: float = point.distance_to(point.clamp(screen.position, screen.end)) / radius
	score += clipped * clipped * 10000.0
	for other: Bubble in bubbles:
		if other == bubble:
			continue
		var total_radius: float = radius + other.radius
		var distance: float = point.distance_to(other.position)
		var body_overlap: float = maxf(0.0, 1.0 - distance / total_radius)
		var face_overlap: float = maxf(0.0, 0.82 - distance / total_radius)
		score += body_overlap * body_overlap * 80.0 + face_overlap * face_overlap * 1000.0
	var inward: float = (
		maxf(
			0.0,
			bubble.anchor.distance_to(_planet_center) + radius - point.distance_to(_planet_center)
		)
		/ radius
	)
	score += inward * inward * 3.0
	return score


func _bubble_rect(center: Vector2, radius: float) -> Rect2:
	return Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)


func _start_preview() -> void:
	_preview = true
	var preview_world: Node2D = Node2D.new()
	preview_world.z_index = -1
	add_child(preview_world)
	var preview_surface: PlanetSurface = PLANET_SCENE.instantiate() as PlanetSurface
	preview_world.add_child(preview_surface)
	configure(preview_surface, preview_world)
	_sync_preview_view()
	var positions: PackedVector2Array = PackedVector2Array()
	var kinds: PackedInt32Array = PackedInt32Array()
	for species: int in range(2):
		for index: int in range(preview_populations[species]):
			var angle: float = 0.35 if species == 0 else 0.65
			positions.append(Vector2.from_angle(angle + float(index % 5) * 0.025) * _surface.radius)
			kinds.append(species)
	update_ecology(positions, kinds, true, get_viewport_rect().size)


func _sync_preview_view() -> void:
	_viewport_size = get_viewport_rect().size
	_visual_scale = minf(_viewport_size.x / 1280.0, _viewport_size.y / 800.0)
	_world.position = _viewport_size * 0.5
	_world.scale = (
		Vector2.ONE
		* _viewport_size.y
		* 0.34
		/ (_surface.radius * PlanetSurface.SURFACE_RADIUS_RATIO)
	)
