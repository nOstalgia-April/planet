extends SceneTree

const Layout = preload("res://scripts/overview_bubble_layout.gd")
const Bubble = preload("res://scripts/overview_monster_bubble.gd")
const DemoScript = preload("res://scripts/disk_demo.gd")
const DemoScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")

var _failures: Array[String] = []
var _positions: PackedVector2Array = PackedVector2Array()
var _kinds: PackedInt32Array = PackedInt32Array()


func _initialize() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	_check_distribution()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._layout.set_process(false)
	demo._view.set_process(false)
	await _settle()
	demo._view.zoom_steps(-1.0, false)
	demo._overview.set_process(false)
	for dimensions: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = dimensions
		await _settle()
		demo._apply_layout()
		demo._overview.set_process(false)
		_check(
			(demo.get_node("HUD") as CanvasLayer).layer > 0, "the HUD is above world-space bubbles"
		)
		_check(
			(demo.get_node("预览导航") as CanvasLayer).layer > 0,
			"preview navigation is above world-space bubbles"
		)
		_clear_samples()
		_patch(-1.2, 48, 0)
		_patch(0.55, 1, 1)
		_patch(2.45, 15, 0)
		_present(demo)
		_check(
			demo._overview.clusters.size() == 3,
			"distant same-species populations have separate bubbles"
		)
		_check(
			demo._overview.population_counts == Vector2i(63, 1),
			"each living sample contributes once"
		)
		_check_geometry(demo)
		await _capture("overview_bubbles_reference_%dx%d.png" % [dimensions.x, dimensions.y])
		var first: Bubble = demo._overview.bubbles[0]
		var before: Vector2 = first.anchor
		var before_position: Vector2 = first.position
		demo._world.rotation += 0.2
		demo._overview._process(0.0)
		_check(
			(
				first.anchor.distance_to(before) > 1.0
				and first.position.distance_to(before_position) > 1.0
			),
			"rotation moves geographical anchors and bubbles immediately"
		)
		_check_geometry(demo)
		_clear_samples()
		_patch(-1.35, 24, 0)
		_patch(-1.16, 24, 0)
		_patch(-1.25, 24, 1)
		_patch(PI * 0.5, 48, 0)
		_present(demo)
		_check(
			demo._overview.clusters.size() == 3,
			"crowded pink patches merge; mixed species and distant patches remain separate"
		)
		for step: int in range(24):
			demo._world.rotation = float(step) * TAU / 24.0
			demo._overview._process(1.0)
			_check_geometry(demo)
			demo._overview._process(0.0)
			var stable: PackedVector2Array = PackedVector2Array()
			for bubble: Bubble in demo._overview.bubbles:
				stable.append(bubble.position)
			demo._overview._process(0.0)
			for index: int in range(stable.size()):
				_check(
					stable[index].distance_to(demo._overview.bubbles[index].position) < 0.1,
					"unchanged layout does not oscillate"
				)
		demo._world.rotation = 0.0
		demo._overview._process(1.0)
		await _capture("overview_bubbles_crowded_%dx%d.png" % [dimensions.x, dimensions.y])
		# Same species at every compass point must not merge by a transitive chain.
		_clear_samples()
		for sector: int in range(24):
			_patch(float(sector) * TAU / 24.0 + 0.025, 6, sector % 2)
		_present(demo)
		_check_geometry(demo)
		await _capture("overview_bubbles_ring_%dx%d.png" % [dimensions.x, dimensions.y])
		_clear_samples()
		_patch(PI * 0.5, 48, 0)
		_present(demo)
		var bottom: Bubble = demo._overview.bubbles[0]
		var beneath_ui: Vector2 = bottom.position
		_check(
			demo._overview._bubble_rect(bottom.position, bottom.radius).intersects(
				demo._layout._tool_dock.get_global_rect()
			),
			"a bottom marker is allowed behind the tool dock"
		)
		var hud: CanvasLayer = demo.get_node("HUD") as CanvasLayer
		hud.hide()
		demo._overview._layout_dirty = true
		demo._overview._process(0.0)
		_check(
			bottom.position.is_equal_approx(beneath_ui),
			"hiding UI cannot move a geographical bubble"
		)
		hud.show()
		await _capture("overview_bubbles_under_ui_%dx%d.png" % [dimensions.x, dimensions.y])
	_clear_samples()
	_present(demo)
	_check(
		demo._overview.bubbles.is_empty() and demo._overview._retiring.is_empty(),
		"empty population fades out and frees its bubbles"
	)
	_check(demo._overview.population_counts == Vector2i.ZERO, "zero population resets live totals")
	demo._view.zoom_steps(1.0, false)
	_check(
		not demo._overview.visible and not demo._overview._backdrop_layer.visible,
		"near view hides the distribution overlay"
	)
	for node: Node in demo.get_node("Audio").get_children():
		if node is AudioStreamPlayer:
			node.stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print(
			"PASS: local density, reference sizes, bounded merge/split, seam, mixed species, rotation, UI layer order, two resolutions and empty/near cleanup"
		)
	quit(0 if _failures.is_empty() else 1)


func _check_distribution() -> void:
	var layout: Layout = Layout.new()
	_check(
		is_equal_approx(layout.radius_for_count(1), 52.0 / 556.0),
		"minimum matches the reference circular body"
	)
	_check(
		is_equal_approx(layout.radius_for_count(48), 119.0 / 556.0),
		"maximum matches the reference circular body"
	)
	var prior: float = 0.0
	for count: int in range(200):
		var radius: float = layout.radius_for_count(count)
		_check(
			radius >= prior and radius <= layout.maximum_ratio + 0.000001,
			"size is monotonic and bounded"
		)
		prior = radius
	_clear_samples()
	_patch(-1.3, 12, 0)
	_patch(-1.12, 12, 0)
	var merged: Array[Layout.Cluster] = layout.build(_positions, _kinds, [])
	_check(
		merged.size() == 1 and merged[0].count == 24,
		"nearby like-species overlap is absorbed before repulsion"
	)
	_check(
		merged[0].radius_ratio > layout.radius_for_count(12),
		"merging increases the local circle rather than moving it away"
	)
	_check(
		absf(angle_difference(merged[0].angle, -1.21)) < 0.01,
		"merged anchor uses the living population's centroid"
	)
	_patch(1.0, 100, 0)
	var separated: Array[Layout.Cluster] = layout.build(_positions, _kinds, merged)
	_check(separated.size() == 2, "a distant population cannot enlarge the original local marker")
	for group: Layout.Cluster in separated:
		if group.angle < 0.0 or group.angle > PI:
			_check(
				is_equal_approx(group.radius_ratio, merged[0].radius_ratio),
				"remote growth leaves local density size unchanged"
			)
	_clear_samples()
	_patch(TAU - 0.04, 10, 0)
	_patch(0.04, 10, 0)
	var seam: Array[Layout.Cluster] = layout.build(_positions, _kinds, [])
	_check(
		seam.size() == 1 and seam[0].count == 20, "the 0/360 degree seam does not split one cluster"
	)
	_patch(0.0, 20, 1)
	_check(
		layout.build(_positions, _kinds, seam).size() == 2,
		"different identities never merge into a false color"
	)
	_clear_samples()
	for sector: int in range(48):
		_patch((float(sector) + 0.5) * TAU / 48.0, 4, 0)
	var chain: Array[Layout.Cluster] = layout.build(_positions, _kinds, [])
	var total: int = 0
	for group: Layout.Cluster in chain:
		total += group.count
		_check(
			group.upper - group.lower <= deg_to_rad(30.0) + 0.0001,
			"a transitive chain cannot exceed the geographical merge limit"
		)
	_check(
		chain.size() >= 12 and total == 192,
		"all populations survive bounded aggregation without duplication"
	)
	# Reversing actor traversal must not choose different occupied regions.
	_positions.reverse()
	_kinds.reverse()
	var reversed: Array[Layout.Cluster] = layout.build(_positions, _kinds, [])
	_check(reversed.size() == chain.size(), "cluster count is independent of actor traversal order")
	for index: int in range(mini(chain.size(), reversed.size())):
		_check(
			chain[index].sectors == reversed[index].sectors, "cluster membership is deterministic"
		)


func _check_geometry(demo: DemoScript) -> void:
	var overview: OverviewEcology = demo._overview
	var screen: Rect2 = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	for bubble: Bubble in overview.bubbles:
		_check(
			screen.encloses(overview._bubble_rect(bubble.position, bubble.radius)),
			"the circle remains in the viewport"
		)
		_check(
			(
				bubble.radius_ratio >= overview.minimum_radius_ratio - 0.001
				and bubble.radius_ratio <= overview.maximum_radius_ratio + 0.001
			),
			"density and collision never exceed the art size limits"
		)
		_check(
			absf(bubble.offset.y) <= overview.maximum_nudge_radii + 0.001,
			"avoidance cannot move to a different part of the planet"
		)
		_check(
			bubble.offset.length() <= overview.maximum_nudge_radii + 0.001,
			"all avoidance stays within a small radius"
		)
		_check(
			is_zero_approx(bubble._portrait.global_rotation),
			"portraits stay upright while pointers turn"
		)
		var pointer: Vector2 = Vector2.DOWN.rotated(bubble._background.global_rotation)
		_check(
			pointer.dot((bubble.anchor - bubble.position).normalized()) > 0.999,
			"the pointer faces the true surface anchor"
		)


func _clear_samples() -> void:
	_positions.clear()
	_kinds.clear()


func _patch(angle: float, count: int, species: int) -> void:
	for index: int in range(count):
		_positions.append(Vector2.from_angle(angle) * 256.0)
		_kinds.append(species)


func _present(demo: DemoScript) -> void:
	demo._overview.update_ecology(_positions, _kinds, true, root.get_visible_rect().size)
	demo._overview.set_process(false)
	demo._overview._process(2.0)


func _settle() -> void:
	for frame: int in range(4):
		await process_frame


func _capture(filename: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	_check(
		root.get_texture().get_image().save_png("res://artifacts/" + filename) == OK,
		"saved " + filename
	)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
