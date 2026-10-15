extends Node2D

@export_range(0.0, 0.4, 0.01) var overlap_shade: float = 0.22
@export_range(1.0, 20.0, 0.5) var shade_response: float = 10.0

var _focus: PrototypeSlime
var _bodies: Array[Body] = []
var _visible_bodies: Array[Body] = []


class Body:
	extends RefCounted

	var actor: PrototypeSlime
	var bounds: Rect2
	var depth: float
	var inverse_area: float

	func _init(value: PrototypeSlime) -> void:
		actor = value

	func refresh() -> void:
		bounds = actor.get_visual_rect()
		inverse_area = 1.0 / maxf(bounds.get_area(), 1.0)
		# Ground contact, not the animated sprite's bottom (especially the mole).
		depth = actor.get_global_transform_with_canvas().origin.y


func _ready() -> void:
	# Run after camera, movement and capture have settled for this frame.
	process_priority = 100
	child_entered_tree.connect(_on_actor_entered)
	child_exiting_tree.connect(_on_actor_exiting)
	for actor: Node in get_children():
		_on_actor_entered(actor)


func set_focus(actor: PrototypeSlime) -> void:
	_focus = actor
	if _focus != null:
		_focus.modulate = Color.WHITE


func _on_actor_entered(actor: Node) -> void:
	_bodies.append(Body.new(actor as PrototypeSlime))


func _on_actor_exiting(actor: Node) -> void:
	if actor == _focus:
		_focus = null
	for index: int in range(_bodies.size()):
		if _bodies[index].actor == actor:
			_visible_bodies.erase(_bodies[index])
			_bodies.remove_at(index)
			break


func _process(delta: float) -> void:
	if not is_visible_in_tree() or modulate.a <= 0.001:
		return
	_visible_bodies.clear()
	var viewport: Rect2 = get_viewport_rect()
	for body: Body in _bodies:
		var actor: PrototypeSlime = body.actor
		if not actor.visible or actor.is_queued_for_deletion():
			continue
		body.refresh()
		if viewport.intersects(body.bounds):
			_visible_bodies.append(body)
	_visible_bodies.sort_custom(_behind)
	var smoothing: float = 1.0 - exp(-shade_response * delta)
	var first_index: int = get_child_count() - _visible_bodies.size()
	for index: int in range(_visible_bodies.size()):
		var body: Body = _visible_bodies[index]
		if body.actor.get_index() != first_index + index:
			move_child(body.actor, first_index + index)
		var coverage: float = 0.0
		# Only visible neighbors contribute; isolated monsters retain their source color.
		for front_index: int in range(index + 1, _visible_bodies.size()):
			var front_bounds: Rect2 = _visible_bodies[front_index].bounds
			if not body.bounds.intersects(front_bounds):
				continue
			var overlap: Rect2 = body.bounds.intersection(front_bounds)
			coverage = maxf(coverage, overlap.get_area() * body.inverse_area)
			# The shade curve is already saturated; farther neighbors cannot change it.
			if coverage >= 0.55:
				break
		var brightness: float = 1.0 - overlap_shade * smoothstep(0.03, 0.55, coverage)
		var tint: Color = Color(brightness, brightness, brightness, 1.0)
		body.actor.modulate = body.actor.modulate.lerp(tint, smoothing)


func _behind(first: Body, second: Body) -> bool:
	if first.actor == _focus or second.actor == _focus:
		return second.actor == _focus and first.actor != _focus
	if first.depth != second.depth:
		return first.depth < second.depth
	# Stable ties: never depend on the last frame's sibling order.
	return first.actor.get_instance_id() < second.actor.get_instance_id()
