extends Node

const Demo = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const Trail = preload("res://scripts/mucus_field.gd")
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var demo: Demo = DemoScene.instantiate() as Demo
	add_child(demo)
	demo.set_process(false)
	demo._view.set_process(false)
	demo.run.settings = demo.run.settings.duplicate() as PrototypeSettings
	demo.mucus_pool_capacity = 3
	var actors: Array[PrototypeSlime] = []
	for index: int in range(90):
		var actor: PrototypeSlime = demo.slime_scene.instantiate() as PrototypeSlime
		demo._slime_root.add_child(actor)
		actor.setup(1, Vector2(0.0, -220.0), demo._planet)
		actor.configure_species(PrototypeSlime.Species.MUCUS, false, 1)
		actor.set_process(false)
		demo._slimes.append(actor)
		actors.append(actor)
	# Multiple quadrants, negative cell coordinates, moving trails, and fading.
	for step: int in range(24):
		for index: int in range(actors.size()):
			var angle: float = float(index) * TAU / actors.size() + float(step) * 0.012
			var bounds: Vector2 = demo._planet.get_activity_radius_bounds(angle)
			actors[index].position = (
				Vector2.from_angle(angle)
				* lerpf(bounds.x, bounds.y, 0.25 + float(index % 3) * 0.25)
			)
			if step >= 16:
				actors[index].detached_remaining = 100.0
		demo._advance_ground_mucus(0.4 if step >= 16 else 0.06)
		for actor: PrototypeSlime in actors:
			_check(
				actor.on_mucus == demo._is_on_ground_mucus(actor.position),
				"spatial query matches exhaustive painted contact"
			)
	var available_slots: int = demo.mucus_pool_capacity - demo._mucus_pool.size()
	var retired: Array[Trail] = demo._mucus_trails.duplicate()
	for trail: Trail in retired:
		demo._retire_mucus_trail(trail)
	_check(demo._mucus_pool.size() == 3, "idle pool respects capacity")
	_check(
		demo._mucus_trails.is_empty() and demo._active_mucus_trails.is_empty(),
		"retirement removes gameplay ownership"
	)
	await get_tree().process_frame
	for index: int in range(retired.size()):
		_check(
			is_instance_valid(retired[index]) == (index < available_slots),
			"overflow frees nodes, pool keeps only capacity"
		)
	for trail: Trail in demo._mucus_pool:
		_check(
			not trail.visible and trail.process_mode == Node.PROCESS_MODE_DISABLED,
			"idle trail is invisible and disabled"
		)
		_check(
			trail.surface == null and trail.source_actor_id == 0 and trail.source_nest_id == -1,
			"idle trail releases owners"
		)
		_check(
			trail._hit_vertices.is_empty() and trail._edge.polygon.is_empty(),
			"idle trail clears contact and rendered geometry"
		)
	var reused_id: int = demo._mucus_pool.back().get_instance_id()
	var actor: PrototypeSlime = actors[0]
	actor.position = Vector2(200.0, 0.0)
	for cycle: int in range(100):
		var trail: Trail = demo._start_mucus_trail(actor)
		_check(trail.get_instance_id() == reused_id, "repeated reuse avoids new scene instances")
		_check(
			(
				trail.source_actor_id == actor.get_instance_id()
				and trail.source_nest_id == actor.nest_id
			),
			"reuse assigns current owners"
		)
		_check(
			(
				trail.visible
				and trail.process_mode == Node.PROCESS_MODE_INHERIT
				and trail._render_detail
			),
			"reuse restores presentation mode"
		)
		_check(
			trail.anchors.size() == 1 and trail._hit_triangles.is_empty(),
			"new source has no old trail"
		)
		trail.advance(0.1, false)
		trail.append_ground_point(Vector2(204.0, 4.0))
		_check(not trail._hit_triangles.is_empty(), "reused trail produces fresh geometry")
		demo._retire_mucus_trail(trail)
	var pooled: Array[Trail] = demo._mucus_pool.duplicate()
	demo.restart_run()
	await get_tree().process_frame
	_check(demo._mucus_pool.is_empty(), "restart clears pool")
	for trail: Trail in pooled:
		_check(not is_instance_valid(trail), "restart frees retained nodes")
	demo.queue_free()
	await get_tree().process_frame
	if _failures == 0:
		print(
			"PASS: spatial contacts, bounded pool, overflow, 100 reuse cycles, clean state, restart and teardown."
		)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
