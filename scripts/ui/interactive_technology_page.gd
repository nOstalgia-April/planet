extends "res://scripts/ui/technology_page.gd"
const INTERACTIVE_GRAPH_SIZE: Vector2 = Vector2(1080.0, 660.0)
static var _last_zoom_factor: float = 1.0
var zoom_factor: float = 1.0
var _drag_id: String = ""
var _pointer_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _suppress_click: bool = false


func _ready() -> void:
	super._ready()
	$Margin/Content/Footer/Hint.text = ""
	visibility_changed.connect(_cancel_pointer)
	set_zoom(_last_zoom_factor)


func _build_graph() -> void:
	super._build_graph()
	for id: String in _nodes:
		_nodes[id].gui_input.connect(_node_input.bind(id))


func _node_prerequisites(id: String) -> Dictionary[String, int]:
	return _run.get_technology_prerequisites(id)


func _node_position(id: String) -> Vector2:
	match id:
		"base_value":
			return Vector2(530.0, 540.0)
		"pipe":
			return Vector2(280.0, 540.0)
		"cultivation":
			return Vector2(780.0, 540.0)
		"combo_unlock":
			return Vector2(160.0, 300.0)
		"net_unlock":
			return Vector2(400.0, 300.0)
		"combo_reward":
			return Vector2(80.0, 80.0)
		"combo_interval":
			return Vector2(240.0, 80.0)
		"net_capacity":
			return Vector2(400.0, 80.0)
		"valuable":
			return Vector2(620.0, 300.0)
		"giant":
			return Vector2(940.0, 300.0)
		"automation":
			return Vector2(780.0, 80.0)
	return Vector2.ZERO


func _fit_graph() -> void:
	var available: Vector2 = _canvas.size - Vector2(32.0, 24.0)
	var factor: float = minf(
		available.x / INTERACTIVE_GRAPH_SIZE.x, available.y / INTERACTIVE_GRAPH_SIZE.y
	)
	var target_scale: float = maxf(0.1, factor) * zoom_factor
	# With panning disabled, stop enlarging before any node or price leaves the canvas.
	var center: Vector2 = INTERACTIVE_GRAPH_SIZE * 0.5
	for node: NodeScript in _nodes.values():
		var bounds: Rect2 = node.get_rect().grow(8.0)
		var extent: Vector2 = (bounds.position - center).abs().max((bounds.end - center).abs())
		target_scale = minf(target_scale, available.x / (extent.x * 2.0))
		target_scale = minf(target_scale, available.y / (extent.y * 2.0))
	graph.scale = Vector2.ONE * target_scale
	graph.size = INTERACTIVE_GRAPH_SIZE
	graph.position = (_canvas.size - INTERACTIVE_GRAPH_SIZE * graph.scale) * 0.5


func set_zoom(value: float) -> void:
	zoom_factor = clampf(value, 0.65, 1.6)
	_last_zoom_factor = zoom_factor
	_fit_graph()


func reset_layout() -> void:
	_cancel_pointer()
	for id: String in _nodes:
		_nodes[id].position = _node_position(id) - NodeScript.ICON_CENTER
	set_zoom(1.0)
	graph.queue_redraw()


func _cancel_pointer() -> void:
	_drag_id = ""
	_dragging = false
	_suppress_click = false
	_hide_details()


func _activate_node(id: String) -> void:
	if not _suppress_click:
		super._activate_node(id)
	_suppress_click = false


func _node_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_suppress_click = false
			_drag_id = id
			_pointer_start = button.global_position
			_dragging = false


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			_suppress_click = _dragging
			if _dragging:
				select_node(_drag_id)
				_hide_details()
			_drag_id = ""
			_dragging = false
		if button.pressed and _canvas.get_global_rect().has_point(button.position):
			if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var step: float = 0.1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1
				set_zoom(zoom_factor + step)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if not _drag_id.is_empty():
			var displacement: Vector2 = motion.position - _pointer_start
			# Keep drag gestures from purchasing; node and canvas positions stay fixed.
			if displacement.length() > 8.0:
				_dragging = true
			if _dragging:
				_hide_details()
				get_viewport().set_input_as_handled()
