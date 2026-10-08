extends SceneTree

const DemoScript = preload("res://scripts/disk_demo.gd")
const MucusField = preload("res://scripts/mucus_field.gd")
const DemoScene: PackedScene = preload("res://scenes/disk_demo.tscn")
const CAPTURE_POINT: Vector2 = Vector2(0.0, -190.0)

var _failures: int = 0
var _capture: bool = false


func _initialize() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	_run_checks.call_deferred()


func _run_checks() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	var demo: DemoScript = DemoScene.instantiate() as DemoScript
	root.add_child(demo)
	current_scene = demo
	demo.set_process(false)
	demo._view.set_process(false)
	demo._layout.set_process(false)
	await _settle_layout()
	demo.restart_run()
	demo.run._random.seed = 41853
	demo._site_random.seed = 19481
	demo.run.advance(demo.run.settings.spawn_intervals[0])
	_freeze_actors(demo)
	_check(
		demo._regions.size() == 2 and demo._nest_views.size() == 2,
		"two basic slime regions start the demo"
	)
	_check(
		_species_count(demo, PrototypeSlime.Species.SLIME) > 0,
		"ordinary slimes spawn through the model"
	)
	_check(
		_species_count(demo, PrototypeSlime.Species.MUCUS) == 0 and not demo.run.net_unlocked,
		"mucus monsters and the net remain locked at the opening"
	)
	_check_ledger(demo)
	demo.run.candy = demo.run.settings.net_unlock_cost
	_check(demo.run.purchase_technology("net"), "purchasing the net unlocks its first mucus nest")
	demo.run.advance(demo.run.settings.spawn_intervals[0])
	_freeze_actors(demo)
	_check(
		demo.run.get_nest(3).species == NestState.Species.MUCUS,
		"the unlocked third region contains mucus"
	)
	await _check_research_and_future_spawns(demo)
	_check_manual_collection(demo)
	_check_automation_and_completion(demo)
	if _capture:
		await _capture_layouts(demo)
	demo.restart_run()
	await process_frame
	_check(
		demo.run.candy == 0 and demo.run.combo_level == 0 and demo.run.governance_level == 0,
		"restart clears wallet and research"
	)
	_check(
		(
			not demo.run.is_complete
			and demo._slimes.is_empty()
			and demo._regions.size() == 2
			and not demo.run.net_unlocked
		),
		"restart clears old ecology and restores the two basic regions"
	)
	_check(demo._mucus_trails.is_empty(), "restart clears every old ground mucus trail")
	_check(
		not demo._completion.visible and not demo._layout.is_technology_open(),
		"restart closes completion and technology"
	)
	for audio: Node in demo.get_node("Audio").get_children():
		(audio as AudioStreamPlayer).stop()
	current_scene = null
	demo.queue_free()
	await process_frame
	if _failures == 0:
		print(
			"PASS: two species, scoped research, live capture ledger, sustained pipe combo, persistent governance, responsive UI and reset"
		)
	quit(0 if _failures == 0 else 1)


func _check_research_and_future_spawns(demo: DemoScript) -> void:
	demo.run.candy = 10000
	demo.run.economy_changed.emit()
	var before: int = demo.run.candy
	_check(not demo.run.upgrade_nest(1), "local construction waits for its research unlock")
	_check(demo.run.candy == before, "locked construction never charges candy")
	await _check_quick_upgrade(demo)
	demo.get_node("%TechnologyButton").pressed.emit()
	_check(
		demo._layout.is_technology_open() and demo._layout.is_over_ui(Vector2.ONE),
		"technology modal blocks background tools and camera"
	)
	_branch_purchase(demo, "Combo").pressed.emit()
	_check(demo.run.combo_level == 1, "technology row purchases combo unlock")
	_branch_purchase(demo, "Governance").pressed.emit()
	_branch_purchase(demo, "Governance").pressed.emit()
	_check(demo.run.governance_level == 2, "technology row unlocks partial governance")
	var original_actors: Array[PrototypeSlime] = demo._slimes.duplicate()
	var valuable_branch: Control = demo.get_node("%ToolCard/Content/Branches/Valuable") as Control
	valuable_branch.get_node("Content/Progress/Scope/Next").pressed.emit()
	_check(
		demo._layout.selected_technology_nest_id == 2, "region selector changes the research target"
	)
	_branch_purchase(demo, "Valuable").pressed.emit()
	_check(
		demo.run.get_nest(1).valuable_level == 0 and demo.run.get_nest(2).valuable_level == 1,
		"other regions retain their independent research"
	)
	demo._layout.close_panels()
	for actor: PrototypeSlime in original_actors:
		_check(not actor.high_value, "research does not rewrite existing actors")
	demo.run.advance(demo.run.settings.spawn_intervals[0] * 4.0)
	_freeze_actors(demo)
	var valuable_count: int = 0
	for actor: PrototypeSlime in demo._slimes:
		if actor.high_value:
			valuable_count += 1
			_check(
				actor.nest_id == 2 and not original_actors.has(actor),
				"only future actors of the researched region become valuable"
			)
	_check(valuable_count > 0, "subsequent spawning visibly produces a valuable individual")
	_check_ledger(demo)


func _check_quick_upgrade(demo: DemoScript) -> void:
	var source: Button = demo.get_node("%QuickPipeButton") as Button
	var popup: Control = demo._layout.get_node("PipeUpgrade") as Control
	source.mouse_entered.emit()
	await _settle_layout()
	_check(popup.visible, "hovering the bottom tool opens its quick upgrade")
	_check(
		popup.get_global_rect().end.y <= source.get_global_rect().position.y,
		(
			"quick upgrade appears above its tool: popup %s, tool %s"
			% [popup.get_global_rect(), source.get_global_rect()]
		)
	)
	var bridge: Vector2 = Vector2(
		source.get_global_rect().get_center().x,
		(source.get_global_rect().position.y + popup.get_global_rect().end.y) * 0.5
	)
	_check(
		demo._layout._quick_hover_rect().has_point(bridge),
		"hover corridor reaches from the tool to the popup without a gap"
	)
	_check(demo._layout.is_over_ui(bridge), "the hover corridor prevents accidental world capture")
	demo._layout._update_quick_hover(0.2, bridge)
	_check(popup.visible, "moving through the bridge keeps the popup open past its close delay")
	var purchase: Button = popup.get_node("Content/Purchase") as Button
	demo._layout._update_quick_hover(0.2, purchase.get_global_rect().get_center())
	_check(popup.visible, "the pointer can reach the upgrade button without losing its popup")
	_check(not purchase.disabled, "quick upgrade exposes an affordable purchase")
	purchase.pressed.emit()
	_check(
		demo.run.pipe_level == 1 and demo.run.net_level == 0,
		"quick upgrade buys only the hovered tool"
	)
	demo._layout._update_quick_hover(0.2, Vector2.ZERO)
	_check(not popup.visible, "leaving the entire hover corridor closes the popup")
	demo._layout.close_panels()


func _branch_purchase(demo: DemoScript, branch: String) -> Button:
	return (
		demo.get_node("%ToolCard/Content/Branches/" + branch + "/Content/Action/Purchase") as Button
	)


func _check_manual_collection(demo: DemoScript) -> void:
	var mucus: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.MUCUS)
	var normal: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.SLIME)
	if mucus == null or normal == null:
		_check(false, "both actors are available for capture checks")
		return
	_isolate(demo, [mucus, normal])
	mucus.position = CAPTURE_POINT - Vector2(18.0, 0.0)
	var trail: MucusField = demo._start_mucus_trail(mucus)
	mucus.position = CAPTURE_POINT
	trail.append_ground_point(mucus.position)
	normal.position = trail.get_ground_points()[-1]
	_check(
		demo._capture_seconds_for(normal) > demo.run.get_pipe_capture_seconds(),
		"a visible mucus ribbon slows an ordinary actor standing on it"
	)
	normal.position = Vector2(700.0, 700.0)
	var before: int = demo.run.candy
	var mucus_reward: int = mucus.reward
	var capture_seconds: float = demo.run.get_pipe_capture_seconds()
	demo._capture_at(capture_seconds * 0.4, mucus.get_capture_point(), true)
	_check(
		mucus.is_anchored() and mucus.capture_progress == 0.0 and demo.run.candy == before,
		"the first part of detachment cannot advance normal capture"
	)
	demo._capture_at(capture_seconds * 0.6, mucus.get_capture_point(), true)
	_check(
		(
			not mucus.is_anchored()
			and demo._slimes.has(mucus)
			and is_zero_approx(mucus.capture_progress)
		),
		"one current pipe interval detaches the actor without reusing its time for suction"
	)
	_check(
		is_equal_approx(demo._capture_seconds_for(mucus), capture_seconds),
		"detached mucus uses normal pipe speed"
	)
	demo._capture_at(capture_seconds * 0.5, mucus.get_capture_point(), true)
	_check(
		demo._slimes.has(mucus) and is_equal_approx(mucus.capture_progress, 0.5),
		"half a suction interval advances only halfway"
	)
	demo._capture_at(capture_seconds * 0.5, mucus.get_capture_point(), true)
	_check(
		demo.run.candy == before + mucus_reward and demo.run.combo_count == 1,
		"successful mucus capture pays its own reward and one combo step"
	)
	var expected_reward: int = 0
	before = demo.run.candy
	for _index: int in range(4):
		var actor: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.SLIME)
		_isolate(demo, [actor])
		expected_reward += actor.reward
		demo._capture_at(demo._capture_seconds_for(actor), actor.get_capture_point(), true)
	_check(
		demo.run.candy == before + expected_reward and demo.run.combo_count == 5,
		"the first five consecutive pipe captures establish the streak without a bonus"
	)
	for streak: int in [6, 7]:
		var actor: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.SLIME)
		_isolate(demo, [actor])
		before = demo.run.candy
		var reward: int = actor.reward
		demo._capture_at(demo._capture_seconds_for(actor), actor.get_capture_point(), true)
		_check(
			demo.run.candy == before + reward + 1 and demo.run.combo_count == streak,
			"every pipe capture after five pays the sustained bonus"
		)
	var batch: Array[PrototypeSlime] = []
	expected_reward = 0
	for actor: PrototypeSlime in demo._slimes:
		if batch.size() < 7:
			batch.append(actor)
	_isolate(demo, batch)
	before = demo.run.candy
	demo._select_tool(DemoScript.ToolMode.NET)
	demo._start_net(CAPTURE_POINT)
	demo._advance_net(demo._net.cast_seconds)
	demo._advance_net(demo._net.close_seconds)
	for actor: PrototypeSlime in batch:
		if not demo._slimes.has(actor):
			expected_reward += actor.reward
	_check(
		demo._net_caught_count == 5 and demo.run.get_net_capacity() == 5,
		"the basic net captures five real targets and leaves its in-range overflow alive"
	)
	_check(
		demo.run.candy == before + expected_reward and demo.run.combo_count == 7,
		"net captures pay base rewards without advancing the pipe streak"
	)
	demo._select_tool(DemoScript.ToolMode.PIPE)
	_check(demo.run.combo_count == 7, "switching tools preserves the live combo")
	_check_ledger(demo)


func _check_automation_and_completion(demo: DemoScript) -> void:
	demo.run.advance(demo.run.settings.spawn_intervals[0])
	_freeze_actors(demo)
	_check(
		demo.run.upgrade_nest(1) and demo.run.upgrade_nest(1),
		"researched local construction reaches partial governance"
	)
	var population_before: int = demo.run.get_nest(1).alive_slimes
	var actor_count: int = demo._slimes.size()
	var candy_before: int = demo.run.candy
	var combo_before: int = demo.run.combo_count
	demo._capture_targets.assign(demo._slimes)
	demo._on_auto_collect_requested(1)
	_check(
		demo.run.candy == candy_before and demo._slimes.size() == actor_count,
		"automatic requests with no eligible actor never invent passive candy"
	)
	demo._capture_targets.clear()
	demo._on_auto_collect_requested(1)
	_check(
		(
			demo._slimes.size() == actor_count - 1
			and demo.run.get_nest(1).alive_slimes == population_before - 1
		),
		"automation consumes one real actor and frees one population slot"
	)
	_check(
		(
			demo.run.candy == candy_before + demo.run.settings.slime_reward
			and demo.run.combo_count == combo_before
		),
		"automatic reward is paid once without advancing combo"
	)
	_check(demo.run.upgrade_pipe(), "stronger pipe permits stable governance research")
	_check(
		demo.run.purchase_technology("governance"),
		"stable governance research unlocks the final construction step"
	)
	_check(demo.run.upgrade_nest(1), "the first region becomes fully governed")
	_check(
		demo.run.get_nest(1).is_tamed and demo._regions.size() == demo.run.generated_nests,
		"governed regions remain present without requiring an immediate replacement nest"
	)
	while demo.run.get_pipe_upgrade_cost() >= 0:
		var pipe_cost: int = demo.run.get_pipe_upgrade_cost()
		candy_before = demo.run.candy
		_branch_purchase(demo, "Pipe").pressed.emit()
		_check(
			demo.run.candy == candy_before - pipe_cost,
			"each additional pipe tier charges its displayed price"
		)
	_check(
		demo.run.pipe_level == 6 and is_equal_approx(demo.run.get_pipe_capture_seconds(), 0.11),
		"the technology row reaches the seventh pipe speed tier"
	)
	_check_stable_valuable_collection(demo)
	var spawn_count: int = int(demo._spawn_directions.get(1, 0))
	demo.run.advance(demo.run.get_nest_spawn_interval(1))
	_check(
		int(demo._spawn_directions.get(1, 0)) > spawn_count,
		"fully governed region keeps creating actual monsters"
	)
	_freeze_actors(demo)
	var nest_id: int = 1
	while nest_id <= demo.run.generated_nests:
		var nest: NestState = demo.run.get_nest(nest_id)
		for _level: int in range(nest.level, demo.run.settings.nest_upgrade_costs.size()):
			_check(demo.run.upgrade_nest(nest_id), "remaining region can complete governance")
		nest_id += 1
	_check(
		demo.run.is_complete and demo._regions.size() == demo.run.generated_nests,
		"completion retains every governed region"
	)
	var directions_before: int = _spawn_total(demo)
	var completed_nest_count: int = demo.run.generated_nests
	candy_before = demo.run.candy
	_warm_ecology(demo, 7.0)
	_check(
		_spawn_total(demo) > directions_before and demo.run.candy > candy_before,
		"completion keeps spawning and automatic collection running"
	)
	_check(
		demo.run.generated_nests == completed_nest_count,
		"completion keeps the existing ecology but stops new nest discovery"
	)
	candy_before = demo.run.candy
	demo._process(0.6)
	_check(
		demo.run.candy > candy_before,
		"the main scene still advances its living economy after completion"
	)
	_check_ledger(demo)
	demo._close_victory()
	var actor: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.SLIME)
	_isolate(demo, [actor])
	candy_before = demo.run.candy
	demo._capture_at(demo._capture_seconds_for(actor), actor.get_capture_point(), true)
	_check(
		demo.run.candy > candy_before,
		"manual capture remains available after all regions are governed"
	)
	_check_ledger(demo)


func _check_stable_valuable_collection(demo: DemoScript) -> void:
	var valuable_count: int = 0
	for actor: PrototypeSlime in demo._slimes:
		if actor.nest_id == 1:
			actor.configure_species(
				actor.species, true, actor.reward * demo.run.settings.valuable_reward_multiplier
			)
			valuable_count += 1
	_check(valuable_count > 0, "stable stress case contains valuable actors")
	demo._automatic_attempts[1] = 0
	var before: int = demo.run.candy
	var actor_count: int = demo._slimes.size()
	for _attempt: int in range(5):
		demo.run.auto_collect_requested.emit(1)
	_check(
		demo.run.candy == before and demo._slimes.size() == actor_count,
		"waiting for special automatic handling creates no synthetic income"
	)
	demo.run.auto_collect_requested.emit(1)
	_check(
		demo.run.candy > before and demo._slimes.size() == actor_count - 1,
		"stable automation eventually clears valuable stock instead of permanently saturating"
	)
	_check_ledger(demo)


func _capture_layouts(demo: DemoScript) -> void:
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		root.size = resolution
		await _settle_layout()
		demo.restart_run()
		_warm_ecology(demo, 6.0)
		await _settle_layout()
		var screen: Rect2 = Rect2(Vector2.ZERO, root.get_visible_rect().size)
		for button_name: String in [
			"QuickPipeButton", "QuickNetButton", "TechnologyButton", "RestartButton"
		]:
			var button: Button = demo.get_node("%" + button_name) as Button
			_check(
				screen.encloses(button.get_global_rect()),
				"%s fits at %s" % [button_name, resolution]
			)
		await _save_frame("governance_near_%dx%d.png" % [resolution.x, resolution.y])
		demo.run.candy = 1200
		demo.run.economy_changed.emit()
		demo._layout._show_quick_upgrade(0)
		await _settle_layout()
		_check(
			screen.encloses((demo._layout.get_node("PipeUpgrade") as Control).get_global_rect()),
			"quick popup stays within the viewport"
		)
		await _save_frame("governance_quick_upgrade_%dx%d.png" % [resolution.x, resolution.y])
		demo._layout.close_panels()
		demo.get_node("%TechnologyButton").pressed.emit()
		await _settle_layout()
		var tree_card: Control = demo.get_node("%ToolCard") as Control
		_check(screen.encloses(tree_card.get_global_rect()), "technology tree fits the viewport")
		for branch: String in ["Pipe", "Net", "Governance", "Combo", "Valuable"]:
			_check(
				tree_card.get_global_rect().encloses(
					_branch_purchase(demo, branch).get_global_rect()
				),
				"technology %s purchase stays visible" % branch
			)
		await _save_frame("governance_technology_%dx%d.png" % [resolution.x, resolution.y])
		demo._layout.close_panels()
		demo.run.upgrade_pipe()
		demo.run.upgrade_pipe()
		demo.run.purchase_technology("combo")
		for _level: int in range(3):
			demo.run.purchase_technology("governance")
		for _level: int in range(3):
			demo.run.upgrade_nest(1)
		demo.run.upgrade_nest(2)
		demo.run.upgrade_nest(2)
		demo.run.purchase_nest_technology(1, "valuable")
		_warm_ecology(demo, 8.0)
		await create_timer(0.75).timeout
		for _capture_index: int in range(2):
			var actor: PrototypeSlime = _first_species(demo, PrototypeSlime.Species.SLIME)
			demo._capture_at(demo._capture_seconds_for(actor), actor.get_capture_point(), true)
		demo._on_auto_collect_requested(1)
		await _settle_layout()
		await _save_frame("governance_stable_%dx%d.png" % [resolution.x, resolution.y])


func _freeze_actors(demo: DemoScript) -> void:
	for actor: PrototypeSlime in demo._slimes:
		actor._process(actor.launch_seconds)
		actor.set_process(false)


func _warm_ecology(demo: DemoScript, seconds: float) -> void:
	for _step: int in range(int(seconds * 10.0)):
		demo.run.advance(0.1)
		for actor: PrototypeSlime in demo._slimes:
			actor._process(0.1)
			actor.set_process(false)
		demo._advance_ground_mucus(0.1)


func _isolate(demo: DemoScript, selected: Array[PrototypeSlime]) -> void:
	for actor: PrototypeSlime in demo._slimes:
		actor.position = CAPTURE_POINT if selected.has(actor) else Vector2(700.0, 700.0)
		actor.capture_progress = 0.0
		actor.set_process(false)


func _species_count(demo: DemoScript, species: PrototypeSlime.Species) -> int:
	var count: int = 0
	for actor: PrototypeSlime in demo._slimes:
		if actor.species == species:
			count += 1
	return count


func _first_species(demo: DemoScript, species: PrototypeSlime.Species) -> PrototypeSlime:
	for actor: PrototypeSlime in demo._slimes:
		if actor.species == species:
			return actor
	return null


func _spawn_total(demo: DemoScript) -> int:
	var total: int = 0
	for nest: NestState in demo.run.nests:
		total += int(demo._spawn_directions.get(nest.nest_id, 0))
	return total


func _check_ledger(demo: DemoScript) -> void:
	for nest: NestState in demo.run.nests:
		var count: int = 0
		for actor: PrototypeSlime in demo._slimes:
			if actor.nest_id == nest.nest_id:
				count += 1
				_check(
					int(actor.species) == int(nest.species),
					"each actor retains the species of its own nest"
				)
		_check(
			count == nest.alive_slimes,
			"region %d actors agree with its population ledger" % nest.nest_id
		)
		_check(
			count <= demo.run.get_nest_population_limit(nest.nest_id),
			"region %d respects its population cap" % nest.nest_id
		)


func _settle_layout() -> void:
	for _frame: int in range(4):
		await process_frame


func _save_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var result: Error = root.get_texture().get_image().save_png("res://artifacts/" + filename)
	_check(result == OK, "saved " + filename)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
