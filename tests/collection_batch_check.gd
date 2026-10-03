extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const NET_ANCHOR: Vector2 = Vector2(0.0, -235.0)

var _failures: int = 0


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	_check_free_cursor(demo)
	await _check_immediate_removal(demo)
	await _check_release_positions(demo)
	_check_continuous_batch(demo)
	_check_restart_pending(demo)
	_check_orphan_collection(demo)
	_check_pipe_switch(demo)
	_check_net_frames(demo)
	_check_net_capacities(demo)
	_check_net_cross_source(demo)
	_check_net_cooldown(demo)
	_check_net_switch_and_pending(demo)
	_check_net_reset(demo)
	for child: Node in demo.get_node("Audio").get_children():
		(child as AudioStreamPlayer).stop()
	await create_timer(0.2).timeout
	current_scene = null
	demo.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: pipe batch release/refill, net click/FPS/capacity/nearest/CD, independent pending, switches and restart."
		)
	quit(0 if _failures == 0 else 1)


func _check_free_cursor(demo: DemoScript) -> void:
	demo.restart_run()
	var actor: PrototypeSlime = _prepare_one(demo)
	var inner_pointer: Vector2 = Vector2(50.0, -30.0)
	demo._drive_tool(0.1, inner_pointer, true)
	_check(
		demo._pipe.position.distance_to(inner_pointer) < 0.001 and not demo._pipe.active,
		"The pipe follows the inner cursor without reaching distant surface bodies."
	)
	actor.restore_to_surface(Vector2.UP * (demo._planet.radius + demo.capture_surface_outer_offset))
	actor.set_process(false)
	var remote: Vector2 = (
		actor.get_capture_point() + Vector2.UP * (demo.run.get_pipe_radius() + 10.0)
	)
	demo._drive_tool(demo.run.get_pipe_capture_seconds(), remote, true)
	_check(
		demo.run.pending_slime_count == 0 and is_zero_approx(actor.capture_progress),
		"A distant cursor cannot capture by projecting its angle back to the surface."
	)
	_check(
		demo._pipe.position.distance_to(remote) < 0.001, "The pipe follows the actual far cursor."
	)


func _check_immediate_removal(demo: DemoScript) -> void:
	demo.restart_run()
	var actor: PrototypeSlime = _prepare_one(demo)
	var source_id: int = actor.nest_id
	var population: int = demo.run.get_nest(source_id).alive_slimes
	demo._drive_tool(demo.run.get_pipe_capture_seconds(), actor.get_capture_point(), true)
	_check(
		(
			demo.run.pending_slime_count == 1
			and demo.run.pending_candy == demo.run.settings.slime_reward
			and demo.run.candy == 0
		),
		"Held pipe capture creates an unpaid batch."
	)
	_check(
		not demo._slimes.has(actor) and actor.is_queued_for_deletion(),
		"A completed pipe capture immediately removes and queues the actor for disposal."
	)
	_check(
		demo.run.get_nest(source_id).alive_slimes == population - 1,
		"Collection immediately releases its source population slot."
	)
	demo.run.advance(demo.run.settings.spawn_intervals[0])
	_check(
		(
			demo.run.get_nest(source_id).alive_slimes == population
			and _source_actor_count(demo, source_id) == population
		),
		"The released slot refills on the normal spawn interval."
	)
	await process_frame
	_check(not is_instance_valid(actor), "The removed actor is freed at the frame boundary.")
	_freeze_actors(demo)


func _check_release_positions(demo: DemoScript) -> void:
	var points: Array[Vector2] = [
		Vector2.RIGHT * 260.0, Vector2.RIGHT * 700.0, Vector2.ZERO, Vector2.ZERO
	]
	for index: int in range(points.size()):
		demo.restart_run()
		var actor: PrototypeSlime = _prepare_one(demo)
		demo._drive_tool(demo.run.get_pipe_capture_seconds(), actor.get_capture_point(), true)
		var pointer: Vector2 = points[index]
		if index == points.size() - 1:
			await process_frame
			await process_frame
			var shop: Control = demo.get_node("HUD/Interface/ToolCard") as Control
			var shop_screen: Vector2 = shop.get_global_rect().get_center()
			_check(
				demo._layout.is_over_ui(shop_screen),
				"Shop release uses the settled real UI region."
			)
			pointer = demo._world.get_global_transform_with_canvas().affine_inverse() * shop_screen
		demo._drive_tool(0.1, pointer, false)
		_check(
			(
				demo.run.candy == demo.run.settings.slime_reward
				and demo.run.pending_slime_count == 0
				and demo.run.pending_candy == 0
			),
			"Releasing near, far, inside or over the shop settles the same batch."
		)
		demo._drive_tool(0.1, pointer, false)
		demo._settle_collection()
		_check(
			demo.run.candy == demo.run.settings.slime_reward,
			"Repeated release and explicit settlement cannot pay twice."
		)


func _check_continuous_batch(demo: DemoScript) -> void:
	demo.restart_run()
	demo.run.advance(demo.run.settings.spawn_intervals[0] * 4.0)
	var actors: Array[PrototypeSlime] = []
	actors.assign(demo._slimes)
	_check(actors.size() >= 8, "The continuous batch uses eight real spawned actors.")
	for actor: PrototypeSlime in actors:
		_place_body(actor, Vector2.LEFT * 235.0)
		actor.set_process(false)
	for index: int in range(8):
		var actor: PrototypeSlime = actors[index]
		_place_body(actor, NET_ANCHOR)
		demo._drive_tool(demo.run.get_pipe_capture_seconds(), NET_ANCHOR, true)
		_check(
			(
				demo.run.pending_slime_count == index + 1
				and demo.run.candy == 0
				and not demo._slimes.has(actor)
			),
			"Held pipe input collects the next single body without a batch limit or payment."
		)
	demo._drive_tool(0.1, Vector2.ZERO, false)
	_check(
		demo.run.candy == 8 * demo.run.settings.slime_reward,
		"One release settles the complete eight-body pipe batch."
	)


func _check_restart_pending(demo: DemoScript) -> void:
	demo.restart_run()
	var actor: PrototypeSlime = _prepare_one(demo)
	demo._drive_tool(demo.run.get_pipe_capture_seconds(), actor.get_capture_point(), true)
	_check(demo.run.pending_slime_count == 1, "Restart begins with a real unpaid pipe collection.")
	demo.restart_run()
	_check(
		(
			demo.run.candy == 0
			and demo.run.pending_candy == 0
			and demo.run.pending_slime_count == 0
			and demo._slimes.is_empty()
		),
		"Restart discards the unpaid batch without restoring or paying removed actors."
	)


func _check_orphan_collection(demo: DemoScript) -> void:
	demo.restart_run()
	var actor: PrototypeSlime = _prepare_one(demo)
	for cost: int in demo.run.settings.nest_upgrade_costs:
		# Funding isolates source conversion; the playthrough checks earned purchases.
		demo.run.candy += cost
		_check(demo.run.upgrade_nest(1), "The source can be tamed before collecting its survivor.")
	_check(
		not actor._has_active_nest and actor.nest_id == 1,
		"A ground orphan keeps its original source identifier."
	)
	demo._drive_tool(demo.run.get_pipe_capture_seconds(), actor.get_capture_point(), true)
	_check(
		demo.run.pending_slime_count == 1 and demo.run.get_nest(1).alive_slimes == 0,
		"An orphan enters the batch and releases its former source slot."
	)
	demo._drive_tool(0.1, Vector2.ZERO, false)
	_check(
		demo.run.candy == demo.run.settings.slime_reward, "Releasing pays for the orphan normally."
	)


func _check_pipe_switch(demo: DemoScript) -> void:
	demo.restart_run()
	var actor: PrototypeSlime = _prepare_one(demo)
	demo._drive_tool(demo.run.get_pipe_capture_seconds(), actor.get_capture_point(), true)
	demo._select_tool(DemoScript.ToolMode.NET)
	_check(
		demo.run.candy == demo.run.settings.slime_reward and demo.run.pending_slime_count == 0,
		"Switching from the pipe settles its existing batch."
	)


func _check_net_frames(demo: DemoScript) -> void:
	var rates: Array[int] = [30, 60, 144]
	for index: int in range(rates.size()):
		var fps: int = rates[index]
		var anchor: Vector2 = _prepare_net_cluster(demo, index)
		var initial_population: int = _total_population(demo)
		_click_net(demo, anchor, fps)
		_check(
			(
				demo.run.candy == 3 * demo.run.settings.slime_reward
				and demo.run.pending_slime_count == 0
				and demo.run.pending_candy == 0
				and demo._slimes.is_empty()
				and demo._net_caught_count == 3
			),
			"One released click automatically catches and pays all three bodies at %d FPS." % fps
		)
		_check(
			(
				_total_population(demo) == initial_population - 3
				and is_equal_approx(demo.run.net_cooldown_remaining, 6.0)
			),
			"Net capture releases source slots; visual frame time does not advance model cooldown."
		)
		var wallet: int = demo.run.candy
		demo._drive_tool(0.1, Vector2.ZERO, false)
		demo._drive_tool(0.1, anchor, true)
		demo._drive_tool(0.1, anchor, false)
		_check(
			demo.run.candy == wallet, "Further release or cooldown clicks cannot repay a net batch."
		)
		print("Net %d FPS, pipe level %d: click paid for 3 bodies." % [fps, index])


func _check_net_capacities(demo: DemoScript) -> void:
	var capacities: Array[int] = [10, 20, 30, 40]
	for level: int in range(capacities.size()):
		demo.restart_run()
		for upgrade: int in range(level):
			_fund_net_upgrade(demo)
		# A level-two source supplies enough real actors to test every net capacity.
		for upgrade: int in range(2):
			demo.run.candy = demo.run.get_nest_upgrade_cost(1)
			_check(demo.run.upgrade_nest(1), "The capacity fixture uses a legal source upgrade.")
		demo.run.advance(demo.run.settings.spawn_intervals[2] * float(capacities[level] + 4))
		_isolate_actors(demo)
		var cluster: Array[PrototypeSlime] = []
		for actor: PrototypeSlime in demo._slimes:
			if actor.nest_id == 1 and cluster.size() < capacities[level] + 3:
				cluster.append(actor)
		_check(
			cluster.size() == capacities[level] + 3,
			"A single real source provides an oversized cluster."
		)
		_place_ranked_cluster(cluster)
		demo._select_tool(DemoScript.ToolMode.NET)
		var population: int = demo.run.get_nest(1).alive_slimes
		var total: int = demo._slimes.size()
		_click_net(demo, NET_ANCHOR, 60)
		_check(
			(
				demo.run.get_net_capacity() == capacities[level]
				and is_equal_approx(demo.run.get_net_radius(), 84.0)
				and is_equal_approx(demo.run.settings.net_cooldown_seconds, 6.0)
				and demo.run.candy == capacities[level] * demo.run.settings.slime_reward
				and demo.run.get_nest(1).alive_slimes == population - capacities[level]
				and demo._slimes.size() == total - capacities[level]
			),
			(
				"Net level %d pays for at most %d same-source bodies with fixed radius and cooldown."
				% [level, capacities[level]]
			)
		)
		_check_ranked_removal(demo, cluster, capacities[level])
		print(
			(
				"Net level %d: nearest %d of %d same-source bodies paid."
				% [level, capacities[level], cluster.size()]
			)
		)


func _check_net_cross_source(demo: DemoScript) -> void:
	demo.restart_run()
	demo.run.advance(demo.run.settings.spawn_intervals[0] * 10.0)
	_isolate_actors(demo)
	var cluster: Array[PrototypeSlime] = []
	for slot: int in range(5):
		for source_id: int in [1, 2, 3]:
			var source_index: int = 0
			for actor: PrototypeSlime in demo._slimes:
				if actor.nest_id == source_id:
					if source_index == slot:
						cluster.append(actor)
						break
					source_index += 1
	_check(cluster.size() == 15, "Three sources provide the cross-source cluster.")
	_place_ranked_cluster(cluster)
	demo._select_tool(DemoScript.ToolMode.NET)
	var populations: Array[int] = []
	for source_id: int in [1, 2, 3]:
		populations.append(demo.run.get_nest(source_id).alive_slimes)
	_click_net(demo, NET_ANCHOR, 60)
	_check_ranked_removal(demo, cluster, 10)
	for source_id: int in [1, 2, 3]:
		var expected_collected: int = 4 if source_id == 1 else 3
		_check(
			(
				demo.run.get_nest(source_id).alive_slimes
				== populations[source_id - 1] - expected_collected
			),
			"Cross-source capacity updates the stock of each actually selected nearest body."
		)
	_check(
		demo.run.candy == 10 * demo.run.settings.slime_reward and demo.run.pending_slime_count == 0,
		"One net capacity applies across all sources and pays once directly to the wallet."
	)


func _check_net_cooldown(demo: DemoScript) -> void:
	demo.restart_run()
	demo._select_tool(DemoScript.ToolMode.NET)
	demo._drive_tool(1.0 / 60.0, NET_ANCHOR, true)
	_check(
		demo._net_phase == DemoScript.NetPhase.CASTING and not demo.run.can_cast_net(),
		"An empty click starts a cast and immediately reserves its cooldown."
	)
	for frame: int in range(59):
		demo._drive_tool(1.0 / 60.0, NET_ANCHOR, true)
	_check(
		(
			demo._net_phase == DemoScript.NetPhase.IDLE
			and demo._net_caught_count == 0
			and demo.run.candy == 0
			and is_equal_approx(demo.run.net_cooldown_remaining, 6.0)
		),
		"An empty held click completes once, pays nothing and still consumes the full cooldown."
	)
	demo.run.advance(5.9)
	_isolate_actors(demo)
	demo._drive_tool(0.01, NET_ANCHOR, false)
	demo._drive_tool(0.01, NET_ANCHOR, true)
	_check(
		demo._net_phase == DemoScript.NetPhase.IDLE and not demo.run.can_cast_net(),
		"A repeated click cannot cast before the model cooldown expires."
	)
	demo.run.advance(0.11)
	_isolate_actors(demo)
	demo._drive_tool(0.01, NET_ANCHOR, true)
	_check(
		demo.run.can_cast_net() and demo._net_phase == DemoScript.NetPhase.IDLE,
		"Keeping input held after cooldown expiry does not automatically fire another cast."
	)
	demo._drive_tool(0.01, NET_ANCHOR, false)
	demo._drive_tool(0.01, NET_ANCHOR, true)
	_check(
		(
			demo._net_phase == DemoScript.NetPhase.CASTING
			and is_equal_approx(demo.run.net_cooldown_remaining, 6.0)
		),
		"A fresh click after cooldown expiry starts exactly one new cast."
	)


func _check_net_switch_and_pending(demo: DemoScript) -> void:
	demo.restart_run()
	for upgrade: int in range(3):
		_fund_pipe_upgrade(demo)
	demo.run.advance(demo.run.settings.spawn_intervals[0] * 2.0)
	_isolate_actors(demo)
	var net_actors: Array[PrototypeSlime] = []
	for index: int in range(3):
		net_actors.append(demo._slimes[index])
	_place_ranked_cluster(net_actors)
	var pipe_actor: PrototypeSlime = demo._slimes[3]
	var pipe_pointer: Vector2 = Vector2.LEFT * 235.0
	_place_body(pipe_actor, pipe_pointer)
	# Other actors stay far from both tools, so the pipe cannot collect a second body.
	for index: int in range(4, demo._slimes.size()):
		_place_body(demo._slimes[index], Vector2.DOWN * 235.0)
	demo._select_tool(DemoScript.ToolMode.NET)
	demo._drive_tool(1.0 / 60.0, NET_ANCHOR, true)
	demo._select_tool(DemoScript.ToolMode.PIPE)
	var delta: float = 1.0 / 60.0
	for frame: int in range(14):
		demo._drive_tool(delta, pipe_pointer, true)
	_check(
		(
			demo.run.pending_slime_count == 1
			and demo.run.candy == 0
			and demo._net_phase == DemoScript.NetPhase.CLOSING
		),
		"The pipe can build a pending batch while a switched-away net keeps closing."
	)
	for frame: int in range(35):
		demo._drive_tool(delta, pipe_pointer, true)
	_check(
		(
			demo.run.candy == 3 * demo.run.settings.slime_reward
			and demo.run.pending_slime_count == 1
			and demo.run.pending_candy == demo.run.settings.slime_reward
			and demo._net_caught_count == 3
			and not demo.run.can_cast_net()
		),
		"Net direct payment preserves the pipe pending batch while casting survives a tool switch."
	)
	demo._drive_tool(delta, pipe_pointer, false)
	_check(
		demo.run.candy == 4 * demo.run.settings.slime_reward and demo.run.pending_slime_count == 0,
		"A later pipe release settles only its own body after the net has paid."
	)
	demo._select_tool(DemoScript.ToolMode.NET)
	_check(
		is_equal_approx(demo.run.net_cooldown_remaining, 6.0),
		"Switching tools preserves the existing net cooldown."
	)


func _check_net_reset(demo: DemoScript) -> void:
	var anchor: Vector2 = _prepare_net_cluster(demo)
	demo._drive_tool(0.02, anchor, true)
	demo.restart_run()
	_check(
		(
			demo._net_phase == DemoScript.NetPhase.IDLE
			and demo.run.can_cast_net()
			and is_zero_approx(demo.run.net_cooldown_remaining)
			and demo.run.candy == 0
			and demo.run.pending_slime_count == 0
			and demo._slimes.is_empty()
		),
		"Restart clears an active cast, cooldown, pending collection and actors."
	)


func _prepare_one(demo: DemoScript) -> PrototypeSlime:
	demo._select_tool(DemoScript.ToolMode.PIPE)
	demo.run.advance(demo.run.settings.spawn_intervals[0])
	_isolate_actors(demo)
	var actor: PrototypeSlime = demo._slimes[0]
	_place_body(actor, NET_ANCHOR)
	return actor


func _prepare_net_cluster(demo: DemoScript, pipe_level: int = 0) -> Vector2:
	demo.restart_run()
	for upgrade: int in range(pipe_level):
		_fund_pipe_upgrade(demo)
	demo._select_tool(DemoScript.ToolMode.NET)
	demo.run.advance(demo.run.settings.spawn_intervals[0])
	_check(demo._slimes.size() == 3, "Each FPS case uses the three initial real actors.")
	_isolate_actors(demo)
	_place_ranked_cluster(demo._slimes)
	return NET_ANCHOR


func _click_net(demo: DemoScript, anchor: Vector2, fps: int) -> void:
	var delta: float = 1.0 / float(fps)
	demo._drive_tool(delta, anchor, true)
	for frame: int in range(fps - 1):
		# Released input and a moving cursor do not interrupt the anchored cast.
		demo._drive_tool(delta, anchor + Vector2.RIGHT * 150.0, false)


func _place_ranked_cluster(actors: Array[PrototypeSlime]) -> void:
	for index: int in range(actors.size()):
		_place_body(actors[index], NET_ANCHOR + Vector2.RIGHT * (float(index) * 1.5))


func _check_ranked_removal(demo: DemoScript, actors: Array[PrototypeSlime], capacity: int) -> void:
	for index: int in range(actors.size()):
		_check(
			demo._slimes.has(actors[index]) == (index >= capacity),
			"The net removes the nearest capacity-limited bodies and leaves every farther body."
		)


func _fund_pipe_upgrade(demo: DemoScript) -> void:
	demo.run.candy = demo.run.get_pipe_upgrade_cost()
	_check(demo.run.upgrade_pipe(), "The pipe-speed fixture uses a legal independent upgrade.")


func _fund_net_upgrade(demo: DemoScript) -> void:
	demo.run.candy = demo.run.get_net_upgrade_cost()
	_check(demo.run.upgrade_net(), "The capacity fixture uses a legal independent net upgrade.")


func _place_body(actor: PrototypeSlime, point: Vector2) -> void:
	actor.position = point - point.normalized() * actor.body_size * 0.65
	actor.rotation = actor.position.angle() + PI / 2.0


func _isolate_actors(demo: DemoScript) -> void:
	for actor: PrototypeSlime in demo._slimes:
		_place_body(actor, Vector2.LEFT * 235.0)
		actor.set_process(false)


func _freeze_actors(demo: DemoScript) -> void:
	for actor: PrototypeSlime in demo._slimes:
		actor.set_process(false)


func _source_actor_count(demo: DemoScript, source_id: int) -> int:
	var count: int = 0
	for actor: PrototypeSlime in demo._slimes:
		if actor.nest_id == source_id:
			count += 1
	return count


func _total_population(demo: DemoScript) -> int:
	var total: int = 0
	for nest: NestState in demo.run.nests:
		total += nest.alive_slimes
	return total


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
