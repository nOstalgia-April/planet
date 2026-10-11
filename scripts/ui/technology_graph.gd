extends Control

const NodeScript = preload("res://scripts/ui/technology_node.gd")

var nodes: Dictionary[String, NodeScript] = {}
var links: Array[Vector2i] = []
var node_keys: PackedStringArray = PackedStringArray()


func _draw() -> void:
	for link: Vector2i in links:
		var source: NodeScript = nodes[node_keys[link.x]]
		var destination: NodeScript = nodes[node_keys[link.y]]
		var start: Vector2 = source.position + NodeScript.ICON_CENTER
		var end: Vector2 = destination.position + NodeScript.ICON_CENTER
		var direction: Vector2 = (end - start).normalized()
		start += direction * 48.0
		end -= direction * 48.0
		var color: Color = Color("e785b5")
		color.a = 0.35 if destination.state == NodeScript.State.LOCKED else 0.75
		var normal: Vector2 = direction.orthogonal()
		var distance: float = start.distance_to(end)
		var segments: int = maxi(2, ceili(distance / 3.0))
		for segment: int in range(segments):
			if segment % 5 >= 2:
				continue
			var a: float = float(segment) / float(segments)
			var b: float = float(segment + 1) / float(segments)
			var p: Vector2 = start.lerp(end, a) + normal * sin(a * TAU * 1.5) * sin(a * PI) * 12.0
			var q: Vector2 = start.lerp(end, b) + normal * sin(b * TAU * 1.5) * sin(b * PI) * 12.0
			draw_line(p, q, color, 1.7, true)
