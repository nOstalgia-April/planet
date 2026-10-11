@tool
class_name PlanetSurface
extends Node2D

signal radius_changed

const SURFACE_RADIUS_RATIO: float = 1.07
const CONTOUR_STEPS: int = 320
const EDGE_HEIGHTS: Array[float] = [
	-0.2,
	0.6,
	0.15,
	-0.35,
	0.7,
	0.1,
	-0.6,
	-0.2,
	0.5,
	0.75,
	-0.3,
	0.0,
	0.7,
	0.3,
	-0.55,
	-0.2,
	0.65,
	0.1,
	-0.5,
	0.4,
]

@export_range(120.0, 600.0, 1.0) var radius: float = 240.0:
	set(value):
		radius = value
		_contour.clear()
		_inner_contour.clear()
		radius_changed.emit()
@export_range(0.0, 0.030, 0.001) var edge_relief_ratio: float = 0.020:
	set(value):
		edge_relief_ratio = value
		_contour.clear()
@export_range(0.0, 12.0, 0.5) var nest_edge_inset: float = 0.0
@export_range(0.0, 12.0, 0.5) var activity_edge_inset: float = 2.0
@export_range(0.2, 0.95, 0.01) var inner_radius_ratio: float = 0.60:
	set(value):
		inner_radius_ratio = value
		_inner_contour.clear()

var _near_view: bool = false
var _contour: PackedVector2Array = PackedVector2Array()
var _inner_contour: PackedVector2Array = PackedVector2Array()


func set_near_view(value: bool) -> bool:
	if _near_view == value:
		return false
	_near_view = value
	return true


func contains_crust_viewport_point(viewport_position: Vector2) -> bool:
	var local_point: Vector2 = (
		get_global_transform_with_canvas().affine_inverse() * viewport_position
	)
	return contains_surface_point(local_point)


func contains_surface_point(point: Vector2, inset: float = 0.0) -> bool:
	var limit: float = maxf(0.0, get_outer_radius(point.angle()) - inset)
	var inner: float = maxf(0.0, get_inner_radius(point.angle()) + inset)
	var distance_squared: float = point.length_squared()
	return distance_squared >= inner * inner - 0.0001 and distance_squared <= limit * limit + 0.0001


func project_to_surface(point: Vector2, inset: float = -1.0) -> Vector2:
	var margin: float = activity_edge_inset if inset < 0.0 else inset
	var limit: float = maxf(0.0, get_outer_radius(point.angle()) - margin)
	var inner: float = get_inner_radius(point.angle()) + margin
	var distance: float = point.length()
	if distance >= inner and distance <= limit:
		return point
	var direction: Vector2 = point / distance if distance > 0.0001 else Vector2.UP
	return direction * clampf(distance, inner, limit)


func get_outer_radius(angle: float) -> float:
	var shelf_phase: float = fposmod(angle + PI / 2.0, TAU) * float(EDGE_HEIGHTS.size()) / TAU
	var shelf_index: int = int(floor(shelf_phase))
	var shelf: float = lerpf(
		EDGE_HEIGHTS[shelf_index],
		EDGE_HEIGHTS[(shelf_index + 1) % EDGE_HEIGHTS.size()],
		smoothstep(0.30, 0.65, shelf_phase - float(shelf_index))
	)
	var relief: float = (
		sin(angle * 3.0 + 0.4) * 0.30 + shelf * 0.58 + sin(angle * 29.0 - 0.6) * 0.12
	)
	return radius * (SURFACE_RADIUS_RATIO + edge_relief_ratio * relief)


func get_inner_radius(_angle: float) -> float:
	return radius * inner_radius_ratio


func get_nest_position(angle: float) -> Vector2:
	return Vector2.from_angle(angle) * (get_outer_radius(angle) - nest_edge_inset)


func get_nest_rotation(angle: float) -> float:
	var sample_step: float = TAU / float(CONTOUR_STEPS)
	var tangent: Vector2 = (
		get_nest_position(angle + sample_step) - get_nest_position(angle - sample_step)
	)
	return tangent.angle()


func get_activity_radius_bounds(angle: float) -> Vector2:
	return Vector2(
		get_inner_radius(angle) + activity_edge_inset, get_outer_radius(angle) - activity_edge_inset
	)


func get_surface_polygon() -> PackedVector2Array:
	if not _contour.is_empty():
		return _contour
	for point_index: int in range(CONTOUR_STEPS):
		var angle: float = float(point_index) * TAU / float(CONTOUR_STEPS)
		_contour.append(Vector2.from_angle(angle) * get_outer_radius(angle))
	return _contour


func get_inner_polygon() -> PackedVector2Array:
	if not _inner_contour.is_empty():
		return _inner_contour
	for index: int in range(128):
		_inner_contour.append(
			Vector2.from_angle(float(index) * TAU / 128.0) * get_inner_radius(0.0)
		)
	return _inner_contour
