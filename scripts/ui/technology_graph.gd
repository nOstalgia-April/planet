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
		start += direction * 29.0
		end -= direction * 29.0
		var color: Color = Color("394b54")
		var width: float = 2.0
		if source.level > 0:
			color = destination.accent.darkened(0.45)
		if destination.state == NodeScript.State.AVAILABLE:
			color = Color("9e8e56")
		if destination.selected or source.selected:
			color = color.lightened(0.22)
			width = 3.0
		draw_line(start, end, Color("091319"), width + 3.0, true)
		draw_line(start, end, color, width, true)
