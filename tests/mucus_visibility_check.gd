extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const MucusField = preload("res://scripts/mucus_field.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const TrailScene: PackedScene = preload("res://scenes/effects/mucus_field.tscn")

var _failures: Array[String] = []
var _surface: PlanetSurface


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	_surface = PlanetSurface.new()
	root.add_child(_surface)
	_surface.set_near_view(true)
	var reference: MucusField = _make_trail()
	var hidden: MucusField = _make_trail()
	_check_visibility_bounds(hidden)
	_check_hidden_updates(reference, hidden)
	_check_fade_and_expiry(reference, hidden)
	reference.free()
	hidden.free()
	_surface.free()
	await _check_overview_expiry()
	for failure: String in _failures:
		push_error("FAIL: " + failure)
	if _failures.is_empty():
		print(
			"PASS: offscreen mucus keeps exact contact and fading, leaves renderer arrays unchanged, restores all layers immediately on reentry, and expires in overview."
		)
	quit(0 if _failures.is_empty() else 1)


func _make_trail() -> MucusField:
	var trail: MucusField = TrailScene.instantiate() as MucusField
	root.add_child(trail)
	trail.configure(_surface, _path_point(0.0), 1, 7.0, 3.0, 72.0, 2.5)
	for sample: int in range(1, 13):
		trail.advance(0.06, false)
		trail.append_ground_point(_path_point(float(sample)), false)
	trail.refresh_surface()
	return trail


func _check_visibility_bounds(trail: MucusField) -> void:
	var original: Transform2D = trail.transform
	_check(trail.is_detail_on_screen(), "a ribbon inside the viewport requests full detail")
	trail.position = Vector2(-10000.0, 0.0)
	_check(not trail.is_detail_on_screen(), "a translated offscreen ribbon skips full detail")
	trail.transform = original
	trail.rotation = 0.8
	trail.scale = Vector2(1.7, 0.65)
	trail.position = Vector2(450.0, 180.0)
	_check(trail.is_detail_on_screen(), "visibility follows rotated and scaled canvas geometry")
	trail.hide()
	_check(not trail.is_detail_on_screen(), "hidden ribbons skip full detail regardless of bounds")
	trail.show()
	trail.transform = original


func _check_hidden_updates(reference: MucusField, hidden: MucusField) -> void:
	var old_meshes: Array[Dictionary] = _snapshot_meshes(hidden)
	for sample: int in range(13, 37):
		for trail: MucusField in [reference, hidden]:
			trail.advance(0.06, false)
			trail.append_ground_point(_path_point(float(sample)), false)
		reference.refresh_surface(false, true)
		hidden.refresh_surface(false, false)
	_check(
		_snapshot_meshes(hidden) == old_meshes,
		"offscreen movement updates no Polygon2D vertices, colors, triangles or visibility"
	)
	_check(
		_snapshot_meshes(reference) != old_meshes,
		"the reference visibly changes along the same traveled path"
	)
	_check(
		hidden.get_ground_points() == reference.get_ground_points()
		and hidden.get_ground_points()[0] != _path_point(0.0),
		"offscreen movement preserves the same path sampling and old-tail trimming"
	)
	var probes: PackedVector2Array = _contact_probes(reference)
	var contact_count: int = _check_contacts(reference, hidden, probes, "moving offscreen")
	_check(contact_count > 0 and contact_count < probes.size(), "contact probes cover painted and clear ground")
	# Request re-entry during the usual 20 Hz update holdoff. The current visible
	# reference is rebuilt at exactly the same clock and path without reprojecting.
	for trail: MucusField in [reference, hidden]:
		trail.advance(0.001, false)
		trail.append_ground_point(_path_point(36.15), false)
	_check(hidden._mesh_elapsed < 0.05, "the re-entry fixture is below the regular rebuild interval")
	reference._rebuild_surface()
	hidden.refresh_surface(false, true)
	_check(
		_snapshot_meshes(hidden) == _snapshot_meshes(reference),
		"re-entry immediately restores exact vertices, triangles and faded colors in all three layers"
	)
	_check_contacts(reference, hidden, _contact_probes(reference), "immediate re-entry")


func _check_fade_and_expiry(reference: MucusField, hidden: MucusField) -> void:
	var old_meshes: Array[Dictionary] = _snapshot_meshes(hidden)
	var probes: PackedVector2Array = _contact_probes(reference)
	var fresh_contacts: int = _check_contacts(reference, hidden, probes, "fresh stopped history")
	hidden.hide()
	var faded_contacts: int = fresh_contacts
	for step: int in range(4):
		var reference_alive: bool = reference.advance(0.6, false)
		var hidden_alive: bool = hidden.advance(0.6, false)
		_check(reference_alive and hidden_alive, "both stopped histories remain alive before expiry")
		reference.refresh_surface(false, true)
		hidden.refresh_surface(false, hidden.is_detail_on_screen())
		faded_contacts = _check_contacts(reference, hidden, probes, "hidden fade stage %d" % step)
		_check(
			is_equal_approx(reference.remaining, hidden.remaining),
			"hidden histories lose lifetime at the same rate as visible histories"
		)
	_check(faded_contacts < fresh_contacts, "fading removes real ground contacts while the trail is hidden")
	_check(_snapshot_meshes(hidden) == old_meshes, "hidden fading also avoids every renderer array write")
	hidden.show()
	hidden.refresh_surface(false, true)
	_check(
		_snapshot_meshes(hidden) == _snapshot_meshes(reference),
		"a fading history returns with exactly the visible reference's current appearance"
	)
	hidden.hide()
	_check(not reference.advance(0.7, false), "the reference expires after its final sample lifetime")
	_check(not hidden.advance(0.7, false), "hidden history expires at the same time")
	_check(
		_check_contacts(reference, hidden, probes, "expired hidden history") == 0,
		"expired hidden geometry cannot retain stale ground contact"
	)


func _check_overview_expiry() -> void:
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	demo.run.candy = demo.run.settings.net_unlock_cost + demo.run.get_pipe_upgrade_cost()
	_check(demo.run.upgrade_pipe(), "speed level two enables net research")
	_check(demo.run.purchase_technology("net"), "the overview fixture unlocks the net")
	demo.run._pending_nest_species = NestState.Species.MUCUS
	_check(
		demo.run.resolve_nest_spawn(demo._planet.get_nest_position(-PI / 2.0 + 0.78)),
		"a resolved discovery prepares the mucus nest for overview checks"
	)
	var nest: NestState = demo.run.get_nest(3)
	demo.run._advance_nest_population(nest, demo.run.get_nest_spawn_interval(3))
	for actor: PrototypeSlime in demo._slimes:
		actor._process(actor.launch_seconds)
		actor.set_process(false)
	demo._advance_ground_mucus(0.0)
	for actor: PrototypeSlime in demo._slimes:
		actor.position = actor.position.rotated(0.025)
	demo._advance_ground_mucus(0.1)
	_check(not demo._mucus_trails.is_empty(), "the overview fixture contains real moving ribbons")
	demo._view.zoom_steps(-1.0)
	_check(not demo._mucus_root.visible, "overview hides the detailed mucus ancestor")
	for actor: PrototypeSlime in demo._slimes:
		actor.detached_remaining = 100.0
	demo._advance_ground_mucus(0.1)
	for trail: MucusField in demo._mucus_trails:
		_check(not trail._render_detail, "the demo disables decorative updates in overview")
	demo._advance_ground_mucus(demo.run.settings.mucus_trail_lifetime + 0.1)
	await process_frame
	_check(
		demo._mucus_trails.is_empty()
		and demo._active_mucus_trails.is_empty()
		and demo._mucus_root.get_child_count() == demo._nest_mucus_areas.size(),
		"overview still expires stopped history and frees ribbon scenes while preserving nest pools"
	)
	for audio: Node in demo.get_node("Audio").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
	current_scene = null
	demo.queue_free()
	await process_frame


func _path_point(sample: float) -> Vector2:
	var angle: float = 0.4 + sample * 0.014
	var bounds: Vector2 = _surface.get_activity_radius_bounds(angle)
	var depth: float = clampf(0.94 + sin(sample * 0.31) * 0.08, 0.0, 1.0)
	return Vector2.from_angle(angle) * lerpf(bounds.x, bounds.y, depth)


func _snapshot_meshes(trail: MucusField) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for layer: Polygon2D in [trail._edge, trail._ground, trail._highlight]:
		snapshots.append(
			{
				"vertices": layer.polygon.duplicate(),
				"colors": layer.vertex_colors.duplicate(),
				"triangles": layer.polygons.duplicate(true),
				"visible": layer.visible,
			}
		)
	return snapshots


func _contact_probes(trail: MucusField) -> PackedVector2Array:
	var bounds: Rect2 = trail._hit_bounds.grow(12.0)
	var probes: PackedVector2Array = PackedVector2Array()
	for row: int in range(25):
		for column: int in range(33):
			probes.append(bounds.position + bounds.size * Vector2(float(column) / 32.0, float(row) / 24.0))
	probes.append_array(trail.get_ground_points())
	return probes


func _check_contacts(
	reference: MucusField, hidden: MucusField, probes: PackedVector2Array, stage: String
) -> int:
	var matching: bool = true
	var contacts: int = 0
	for point: Vector2 in probes:
		var expected: bool = reference.contains_ground_point(point)
		if expected:
			contacts += 1
		if hidden.contains_ground_point(point) != expected:
			matching = false
	_check(matching, stage + ": every painted/clear/edge sample matches full rendering")
	return contacts


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
