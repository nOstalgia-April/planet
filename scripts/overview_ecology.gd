class_name OverviewEcology
extends Node2D

const PLANET_SCENE: PackedScene = preload("res://scenes/world/planet_surface.tscn")
const CLUSTER_COLUMNS: int = 3
const CLUSTER_COUNT: int = CLUSTER_COLUMNS * CLUSTER_COLUMNS
const SURFACE_SECTORS: int = 16

@export var interface: DiskDemoLayout
@export var slime_color: Color = Color("f43187")
@export var mucus_color: Color = Color("397cf5")
@export var neutral_color: Color = Color("625e69")
@export_range(1.0, 12.0, 0.5) var transition_speed: float = 4.5
@export_range(10.0, 22.0, 1.0) var minimum_bubble_radius: float = 15.0
@export_range(1.0, 6.0, 0.1) var bubble_growth: float = 3.0
@export_range(12.0, 60.0, 1.0) var bubble_clearance: float = 32.0
@export_range(4.0, 24.0, 1.0) var surface_band_width: float = 12.0
@export var preview_populations: Vector2i = Vector2i(48, 14)

var population_counts: Vector2i = Vector2i.ZERO
var bubble_radii: Vector2 = Vector2.ZERO
var backdrop_color: Color = Color("625e69")
var cluster_regions: Vector2i = Vector2i(-1, -1)
var cluster_anchors: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var bubble_centers: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])

var _surface: PlanetSurface
var _world: Node2D
var _viewport_size: Vector2 = Vector2(1280.0, 800.0)
var _planet_center: Vector2 = Vector2(640.0, 400.0)
var _planet_radius: float = 265.0
var _visual_scale: float = 1.0
var _target_radii: Vector2 = Vector2.ZERO
var _target_color: Color = Color("625e69")
var _target_activity: float = 0.0
var _activity: float = 0.0
var _is_overview: bool = false
var _preview: bool = false
var _surface_counts: Array[Vector2i] = []
var _surface_bands: Array[PackedVector2Array] = []

@onready var _backdrop_layer: CanvasLayer = $Backdrop
@onready var _backdrop: ColorRect = $Backdrop/Color


func _ready() -> void:
	set_process(false)
	if get_tree().current_scene == self:
		_start_preview.call_deferred()


func configure(surface: PlanetSurface, world: Node2D) -> void:
	assert(surface != null and world != null, "Overview ecology requires the planet and world.")
	_surface = surface
	_world = world
	backdrop_color = neutral_color
	_target_color = neutral_color


func update_nest_clusters(nests: Array[NestState]) -> void:
	assert(_surface != null, "Configure overview ecology before providing nest clusters.")
	var counts: PackedInt32Array = PackedInt32Array()
	var positions: PackedVector2Array = PackedVector2Array()
	counts.resize(CLUSTER_COUNT * 2)
	positions.resize(CLUSTER_COUNT * 2)
	_surface_counts.resize(SURFACE_SECTORS)
	_surface_counts.fill(Vector2i.ZERO)
	for nest: NestState in nests:
		var region: int = _region_for_position(nest.position)
		var index: int = int(nest.species) * CLUSTER_COUNT + region
		counts[index] += 1
		positions[index] += nest.position
		var sector: int = _surface_sector_for_position(nest.position)
		var sector_count: Vector2i = _surface_counts[sector]
		sector_count[nest.species] += 1
		_surface_counts[sector] = sector_count
	_surface_bands.clear()
	for sector: int in range(SURFACE_SECTORS):
		for species: int in range(2):
			_surface_bands.append(_surface_band_polygon(sector, species))
	for species: int in range(2):
		var region: int = cluster_regions[species]
		var offset: int = species * CLUSTER_COUNT
		var largest_count: int = counts[offset + region] if region >= 0 else 0
		for candidate: int in range(CLUSTER_COUNT):
			if counts[offset + candidate] > largest_count:
				region = candidate
				largest_count = counts[offset + candidate]
		cluster_regions[species] = region if largest_count > 0 else -1
		cluster_anchors[species] = Vector2.ZERO
		if largest_count > 0:
			var direction: Vector2 = positions[offset + region].normalized()
			if direction.is_zero_approx():
				direction = Vector2.UP.rotated(float(species) * PI * 0.5)
			cluster_anchors[species] = direction * _surface.get_outer_radius(direction.angle())
	_sync_geometry()
	queue_redraw()


func _region_for_position(point: Vector2) -> int:
	var normalized: Vector2 = (
		(point / (_surface.radius * PlanetSurface.SURFACE_RADIUS_RATIO) + Vector2.ONE) * 0.5
	)
	var column: int = clampi(int(floor(normalized.x * CLUSTER_COLUMNS)), 0, CLUSTER_COLUMNS - 1)
	var row: int = clampi(int(floor(normalized.y * CLUSTER_COLUMNS)), 0, CLUSTER_COLUMNS - 1)
	return row * CLUSTER_COLUMNS + column


func _surface_sector_for_position(point: Vector2) -> int:
	return (
		int(floor(fposmod(point.angle() + PI * 0.5, TAU) * float(SURFACE_SECTORS) / TAU))
		% SURFACE_SECTORS
	)


func _surface_band_polygon(sector: int, species: int) -> PackedVector2Array:
	var counts: Vector2i = _surface_counts[sector]
	var total: int = counts.x + counts.y
	if counts[species] == 0:
		return PackedVector2Array()
	var sector_span: float = TAU / float(SURFACE_SECTORS)
	var usable_span: float = sector_span - 0.025
	var start: float = -PI * 0.5 + float(sector) * sector_span + 0.0125
	if species == 1:
		start += usable_span * float(counts.x) / float(total)
	var end: float = start + usable_span * float(counts[species]) / float(total)
	var polygon: PackedVector2Array = PackedVector2Array()
	for index: int in range(13):
		var angle: float = lerpf(start, end, float(index) / 12.0)
		polygon.append(Vector2.from_angle(angle) * (_surface.get_outer_radius(angle) - 1.5))
	for index: int in range(12, -1, -1):
		var angle: float = lerpf(start, end, float(index) / 12.0)
		polygon.append(
			(
				Vector2.from_angle(angle)
				* (_surface.get_outer_radius(angle) - 1.5 - surface_band_width)
			)
		)
	return polygon


func update_ecology(
	slime_count: int, mucus_count: int, is_overview: bool, viewport_size: Vector2
) -> void:
	assert(_surface != null and _world != null, "Configure overview ecology before updating it.")
	assert(viewport_size.x > 0.0 and viewport_size.y > 0.0)
	population_counts = Vector2i(maxi(0, slime_count), maxi(0, mucus_count))
	_is_overview = is_overview
	visible = is_overview
	_backdrop_layer.visible = is_overview
	set_process(is_overview)
	_viewport_size = viewport_size
	_visual_scale = minf(viewport_size.x / 1280.0, viewport_size.y / 800.0)
	_sync_geometry()
	_target_radii = Vector2(
		_radius_for_count(population_counts.x), _radius_for_count(population_counts.y)
	)
	var total: int = population_counts.x + population_counts.y
	_target_color = neutral_color
	_target_activity = 0.0
	if total > 0:
		var balance: float = float(population_counts.x - population_counts.y) / float(total)
		var dominant: Color = slime_color if balance > 0.0 else mucus_color
		_target_color = neutral_color.lerp(dominant, pow(absf(balance), 0.55))
		_target_activity = 1.0 - exp(-float(total) / 28.0)
	if not is_overview:
		bubble_radii = _target_radii
		backdrop_color = _target_color
		_activity = _target_activity
	queue_redraw()


func _process(delta: float) -> void:
	if _preview:
		_sync_preview_view()
	var blend: float = 1.0 - exp(-delta * transition_speed)
	bubble_radii = bubble_radii.lerp(_target_radii, blend)
	backdrop_color = backdrop_color.lerp(_target_color, blend)
	_activity = lerpf(_activity, _target_activity, blend)
	_sync_geometry()
	_backdrop.color = backdrop_color.darkened(0.84)
	queue_redraw()


func _radius_for_count(count: int) -> float:
	if count <= 0:
		return 0.0
	return minf(72.0, minimum_bubble_radius + bubble_growth * sqrt(float(count))) * _visual_scale


func _sync_geometry() -> void:
	var world_transform: Transform2D = _world.get_global_transform_with_canvas()
	var surface_transform: Transform2D = _surface.get_global_transform_with_canvas()
	_planet_center = world_transform.origin
	_planet_radius = (
		_surface.radius
		* (PlanetSurface.SURFACE_RADIUS_RATIO + _surface.edge_relief_ratio)
		* maxf(surface_transform.x.length(), surface_transform.y.length())
	)
	_backdrop.size = _viewport_size
	var obstacles: Array[Rect2] = []
	if interface != null:
		obstacles = interface.get_overview_obstacles()
	for species: int in range(2):
		var radius: float = bubble_radii[species]
		var anchor: Vector2 = world_transform * cluster_anchors[species]
		var direction: Vector2 = (anchor - _planet_center).normalized()
		if direction.is_zero_approx():
			direction = Vector2.from_angle(-PI * 0.75 + float(species) * PI * 0.5)
		var preferred: Vector2 = (
			_planet_center
			+ direction * (_planet_radius + radius + bubble_clearance * _visual_scale)
		)
		bubble_centers[species] = _place_bubble(preferred, radius, obstacles)
		if population_counts[species] > 0:
			obstacles.append(_bubble_rect(bubble_centers[species], radius))


func _bubble_rect(center: Vector2, radius: float) -> Rect2:
	return Rect2(
		center - Vector2.ONE * radius, Vector2(radius * 2.0, radius * 2.0 + 22.0 * _visual_scale)
	)


func _place_bubble(preferred: Vector2, radius: float, obstacles: Array[Rect2]) -> Vector2:
	var margin: float = 12.0 * _visual_scale
	var label_height: float = 22.0 * _visual_scale
	var lower: Vector2 = Vector2.ONE * (radius + margin)
	var upper: Vector2 = _viewport_size - Vector2(radius + margin, radius + margin + label_height)
	var initial: Vector2 = preferred.clamp(lower, upper)
	var candidates: PackedVector2Array = PackedVector2Array([initial])
	var angle: float = (preferred - _planet_center).angle()
	var orbit: float = _planet_radius + radius + bubble_clearance * _visual_scale
	for ring: int in range(2):
		for step: int in range(48):
			var direction: Vector2 = Vector2.from_angle(angle + float(step) * TAU / 48.0)
			candidates.append(
				_planet_center + direction * (orbit + float(ring) * 32.0 * _visual_scale)
			)
	for obstacle: Rect2 in obstacles:
		candidates.append(Vector2(initial.x, obstacle.position.y - radius - label_height - margin))
		candidates.append(Vector2(initial.x, obstacle.end.y + radius + margin))
		candidates.append(Vector2(obstacle.position.x - radius - margin, initial.y))
		candidates.append(Vector2(obstacle.end.x + radius + margin, initial.y))
	var best: Vector2 = initial
	var best_distance: float = INF
	for candidate: Vector2 in candidates:
		candidate = candidate.clamp(lower, upper)
		if not _bubble_is_outside_surface(candidate, radius):
			continue
		var footprint: Rect2 = _bubble_rect(candidate, radius).grow(margin * 0.5)
		var obstructed: bool = false
		for obstacle: Rect2 in obstacles:
			if footprint.intersects(obstacle):
				obstructed = true
				break
		var distance: float = candidate.distance_squared_to(preferred)
		if not obstructed and distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _bubble_is_outside_surface(center: Vector2, radius: float) -> bool:
	var footprint: Rect2 = _bubble_rect(center, radius)
	var nearest: Vector2 = _planet_center.clamp(footprint.position, footprint.end)
	return nearest.distance_to(_planet_center) >= _planet_radius + 4.0 * _visual_scale


func _draw() -> void:
	if not _is_overview:
		return
	var projection: Transform2D = _surface.get_global_transform_with_canvas()
	for index: int in range(_surface_bands.size()):
		var band: PackedVector2Array = _surface_bands[index]
		if not band.is_empty():
			var tint: Color = slime_color if index % 2 == 0 else mucus_color
			draw_colored_polygon(projection * band, Color(tint.lightened(0.15), 0.84))
	if population_counts.x > 0:
		_draw_species_bubble(0, population_counts.x, bubble_radii.x)
	if population_counts.y > 0:
		_draw_species_bubble(1, population_counts.y, bubble_radii.y)


func _draw_species_bubble(species: int, count: int, radius: float) -> void:
	if radius <= 0.5:
		return
	var center: Vector2 = bubble_centers[species]
	var tint: Color = slime_color if species == 0 else mucus_color
	draw_circle(center, radius, tint.darkened(0.12))
	draw_arc(center, radius, 0.0, TAU, 48, tint.lightened(0.45), 1.6 * _visual_scale, true)
	_draw_monster_face(center, radius * 0.76, species)
	var text: String = str(count)
	var font_size: int = maxi(12, int(round(14.0 * _visual_scale)))
	var text_width: float = (
		ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	)
	var baseline: Vector2 = center + Vector2(-text_width * 0.5, radius + 18.0 * _visual_scale)
	draw_string_outline(
		ThemeDB.fallback_font,
		baseline,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		3,
		Color("17191f")
	)
	draw_string(
		ThemeDB.fallback_font,
		baseline,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color("f3e8d0")
	)


func _draw_monster_face(center: Vector2, radius: float, species: int) -> void:
	var fill: Color = Color("ffd0e4") if species == 0 else Color("d4e5ff")
	var ink: Color = Color("903957") if species == 0 else Color("385aab")
	var body: PackedVector2Array = PackedVector2Array()
	for index: int in range(32):
		var angle: float = TAU * float(index) / 32.0
		var scallop: float = 1.0 + sin(angle * (5.0 if species == 0 else 7.0)) * 0.065
		var point: Vector2 = Vector2(cos(angle), sin(angle) * 0.77) * radius * scallop
		body.append(center + point)
	draw_colored_polygon(body, fill)
	body.append(body[0])
	draw_polyline(body, ink, 1.4 * _visual_scale, true)
	for side: float in [-1.0, 1.0]:
		var eye: Vector2 = center + Vector2(side * radius * 0.32, -radius * 0.08)
		draw_circle(eye, radius * 0.095, ink)
		draw_circle(eye + Vector2(radius * 0.025, -radius * 0.025), radius * 0.028, Color("fff9e8"))
	draw_arc(
		center + Vector2(0.0, radius * 0.07),
		radius * 0.17,
		0.18,
		PI - 0.18,
		13,
		ink,
		1.3 * _visual_scale,
		true
	)


func _start_preview() -> void:
	_preview = true
	var preview_world: Node2D = Node2D.new()
	preview_world.z_index = -1
	add_child(preview_world)
	var preview_surface: PlanetSurface = PLANET_SCENE.instantiate() as PlanetSurface
	preview_world.add_child(preview_surface)
	configure(preview_surface, preview_world)
	var preview_nests: Array[NestState] = []
	for species: int in range(2):
		var nest: NestState = NestState.new()
		nest.species = species as NestState.Species
		nest.position = Vector2(-100.0, -80.0) if species == 0 else Vector2(90.0, 40.0)
		preview_nests.append(nest)
	update_nest_clusters(preview_nests)
	_sync_preview_view()


func _sync_preview_view() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	_world.position = viewport_size * 0.5
	_world.scale = (
		Vector2.ONE
		* minf(viewport_size.x, viewport_size.y)
		* 0.31
		/ (_surface.radius * PlanetSurface.SURFACE_RADIUS_RATIO)
	)
	update_ecology(preview_populations.x, preview_populations.y, true, viewport_size)
