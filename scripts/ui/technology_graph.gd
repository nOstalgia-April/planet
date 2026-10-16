extends Control

const NodeScript = preload("res://scripts/ui/technology_node.gd")
const LINE_WIDTH: float = 1.5
const DASH_LENGTH: float = 4.0
const DASH_GAP: float = 5.0
const TOP_CLEARANCE: float = 74.0
const PRICE_CLEARANCE: float = 4.0

var line_color: Color = Color("f0a0c5")
var nodes: Dictionary[String, NodeScript] = {}
var links: Array[Vector2i] = []
var node_keys: PackedStringArray = PackedStringArray()


func _draw() -> void:
	for index: int in range(links.size()):
		var link: Vector2i = links[index]
		var source: NodeScript = nodes[node_keys[link.x]]
		var destination: NodeScript = nodes[node_keys[link.y]]
		var start: Vector2 = source.position + NodeScript.ICON_CENTER - Vector2(0, TOP_CLEARANCE)
		var end: Vector2 = (
			destination.position
			+ Vector2(NodeScript.ICON_CENTER.x, destination.size.y + PRICE_CLEARANCE)
		)
		if (
			destination.state == NodeScript.State.LOCKED
			and destination.technology_id != "automation"
		):
			end = destination.position + NodeScript.ICON_CENTER + Vector2(0.0, 46.0)
		var points: PackedVector2Array = _curve_points(start, end, float(index) * 1.7)
		var color: Color = line_color
		color.a = 0.22 if destination.state == NodeScript.State.LOCKED else 0.38
		if destination.state == NodeScript.State.AVAILABLE:
			color.a = 0.65
		if destination.selected or source.selected:
			color.a = 0.85
		_draw_dashes(points, color)


func _curve_points(start: Vector2, end: Vector2, phase: float) -> PackedVector2Array:
	var distance: float = start.distance_to(end)
	var bend: float = absf(end.y - start.y) * 0.55
	var control_a: Vector2 = start - Vector2(0, bend)
	var control_b: Vector2 = end + Vector2(0, bend)
	var normal: Vector2 = (end - start).normalized().orthogonal()
	var amplitude: float = minf(12.0, distance * 0.035)
	var segments: int = maxi(12, ceili(distance / 2.0))
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(segments + 1):
		var progress: float = float(index) / float(segments)
		var point: Vector2 = start.bezier_interpolate(control_a, control_b, end, progress)
		# A restrained, deterministic wobble follows the supplied hand-drawn reference.
		point += normal * sin(progress * TAU * 1.5 + phase) * sin(progress * PI) * amplitude
		points.append(point)
	return points


func _draw_dashes(points: PackedVector2Array, color: Color) -> void:
	var path_distance: float = 0.0
	for index: int in range(points.size() - 1):
		var start: Vector2 = points[index]
		var end: Vector2 = points[index + 1]
		var length: float = start.distance_to(end)
		var offset: float = 0.0
		while offset < length:
			var phase: float = fposmod(path_distance + offset, DASH_LENGTH + DASH_GAP)
			var drawing: bool = phase < DASH_LENGTH
			var remaining: float = (DASH_LENGTH if drawing else DASH_LENGTH + DASH_GAP) - phase
			var step: float = minf(length - offset, maxf(remaining, 0.001))
			if drawing:
				draw_line(
					start.lerp(end, offset / length),
					start.lerp(end, (offset + step) / length),
					color,
					LINE_WIDTH,
					true
				)
			offset += step
		path_distance += length
