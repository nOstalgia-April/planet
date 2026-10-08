extends Node2D

const PipeCursor = preload("res://scripts/pipe_cursor.gd")
const PlanetViewController = preload("res://scripts/planet_view_controller.gd")
const GovernedRegion = preload("res://scripts/governed_region.gd")
const REGION_SCENE: PackedScene = preload("res://scenes/world/governed_region.tscn")
const MucusField = preload("res://scripts/mucus_field.gd")
const MUCUS_SCENE: PackedScene = preload("res://scenes/effects/mucus_field.tscn")
const NestMucusArea = preload("res://scripts/nest_mucus_area.gd")
const NEST_MUCUS_SCENE: PackedScene = preload("res://scenes/effects/nest_mucus_area.tscn")

enum ToolMode { PIPE, NET }
enum NetPhase { IDLE, CASTING, CLOSING, RESULT }

@export var slime_scene: PackedScene
@export var nest_scene: PackedScene
@export var collection_scene: PackedScene
@export_range(0.1, 1.0, 0.05) var net_result_seconds: float = 0.30

var selected_nest_id: int = -1
var _active_tool: ToolMode = ToolMode.PIPE
var _net_phase: NetPhase = NetPhase.IDLE
var _net_elapsed: float = 0.0
var _net_origin: Vector2 = Vector2.ZERO
var _net_anchor: Vector2 = Vector2.ZERO
var _net_caught_count: int = 0
var _tool_pointer: Vector2 = Vector2.ZERO
var _nest_views: Array[NestView] = []
var _slimes: Array[PrototypeSlime] = []
var _capture_targets: Array[PrototypeSlime] = []
var _was_holding: bool = false
var _view_blocks_tool_until_release: bool = false
var _window_has_focus: bool = true
var _spawn_directions: Dictionary = {}
var _regions: Array[GovernedRegion] = []
var _automatic_attempts: Dictionary = {}
var _mucus_trails: Array[MucusField] = []
var _active_mucus_trails: Dictionary = {}
var _nest_mucus_areas: Array[NestMucusArea] = []
var _restore_tween: Tween
var _status_tween: Tween
var _hud_refresh_queued: bool = false
var _site_random: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var run: PrototypeRun = $Run
@onready var _world: Node2D = $World
@onready var _view: PlanetViewController = %PlanetViewController
@onready var _planet: PlanetSurface = %PlanetSurface
@onready var _nests: Node2D = %Nests
@onready var _region_root: Node2D = %Regions
@onready var _slime_root: Node2D = %Slimes
@onready var _effects: Node2D = %Effects
@onready var _mucus_root: Node2D = %GroundMucus
@onready var _overview: OverviewEcology = %OverviewEcology
@onready var _pipe: PipeCursor = %Pipe
@onready var _net: CaptureNet = %CaptureNet
@onready var _layout: DiskDemoLayout = %Interface
@onready var _candy_label: Label = %CandyLabel
@onready var _passive_label: Label = %PassiveLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _tool_level_label: Label = %ToolLevelLabel
@onready var _tool_stats_label: Label = %ToolStatsLabel
@onready var _tool_button: Button = %ToolButton
@onready var _pipe_button: Button = %PipeToolButton
@onready var _net_button: Button = %NetToolButton
@onready var _quick_pipe_button: Button = %QuickPipeButton
@onready var _quick_net_button: Button = %QuickNetButton
@onready var _nest_title_label: Label = %NestTitleLabel
@onready var _nest_level_label: Label = %NestLevelLabel
@onready var _nest_benefit_label: Label = %NestBenefitLabel
@onready var _nest_button: Button = %NestButton
@onready var _status_label: Label = %StatusLabel
@onready var _completion: Control = %Completion
@onready var _completion_title: Label = %CompletionTitle
@onready var _completion_detail: Label = %CompletionDetail
@onready var _collect_sound: AudioStreamPlayer = $Audio/CollectSound
@onready var _upgrade_sound: AudioStreamPlayer = $Audio/UpgradeSound
@onready var _tame_sound: AudioStreamPlayer = $Audio/TameSound
@onready var _finish_sound: AudioStreamPlayer = $Audio/FinishSound


func _ready() -> void:
	assert(slime_scene != null and nest_scene != null and collection_scene != null)
	get_viewport().physics_object_picking = true
	run.economy_changed.connect(_queue_hud_refresh)
	run.nest_added.connect(_on_nest_added)
	run.nest_spawn_requested.connect(_on_nest_spawn_requested)
	run.nest_changed.connect(_on_nest_changed)
	run.slime_requested.connect(_on_slime_requested)
	run.goal_completed.connect(_on_goal_completed)
	run.auto_collect_requested.connect(_on_auto_collect_requested)
	_layout.quick_upgrade_requested.connect(_on_quick_upgrade)
	_layout.technology_upgrade_requested.connect(_on_technology_upgrade)
	_layout.nest_technology_upgrade_requested.connect(_on_nest_technology_upgrade)
	_tool_button.pressed.connect(_on_tool_upgrade)
	_pipe_button.pressed.connect(_select_tool.bind(ToolMode.PIPE))
	_net_button.pressed.connect(_select_tool.bind(ToolMode.NET))
	_quick_pipe_button.pressed.connect(_select_tool.bind(ToolMode.PIPE))
	_quick_net_button.pressed.connect(_select_tool.bind(ToolMode.NET))
	_nest_button.pressed.connect(_on_nest_upgrade)
	_layout.interaction_panel_changed.connect(_cancel_view_drag)
	_view.view_changed.connect(_sync_view_presentation)
	_view.view_rotated.connect(_sync_view_rotation)
	%RestartButton.pressed.connect(restart_run)
	%ReplayButton.pressed.connect(restart_run)
	%CloseVictoryButton.pressed.connect(_close_victory)
	_overview.configure(_planet, _world)
	RenderingServer.set_default_clear_color(Color("e9e8df"))
	get_viewport().size_changed.connect(_apply_layout)
	get_window().focus_exited.connect(_on_window_focus_exited)
	get_window().focus_entered.connect(_on_window_focus_entered)
	_apply_layout()
	restart_run()


func _process(delta: float) -> void:
	_update_nest_hover(get_viewport().get_mouse_position())
	run.advance(delta)
	_layout.refresh_timers(run)
	_advance_ground_mucus(delta)
	var world_position: Vector2 = _world.to_local(get_global_mouse_position())
	var holding: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not holding and not _view.is_dragging():
		_view_blocks_tool_until_release = false
	holding = holding and not _view.is_dragging() and not _view_blocks_tool_until_release
	_drive_tool(delta, world_position, holding)


func _drive_tool(delta: float, pointer: Vector2, holding: bool) -> void:
	var just_pressed: bool = holding and not _was_holding
	_tool_pointer = pointer
	_pipe.visible = _active_tool == ToolMode.PIPE and _can_collect(pointer, run.get_pipe_radius())
	if _active_tool == ToolMode.PIPE:
		var tool_radius: float = run.get_pipe_radius()
		var capturing: bool = _can_collect(pointer, tool_radius)
		_pipe.radius = tool_radius
		_capture_at(delta, pointer, capturing)
		_pipe.set_tool_state(pointer, pointer, capturing)
	else:
		_capture_at(delta, pointer, false)
		if (
			just_pressed
			and _net_phase == NetPhase.IDLE
			and _can_collect(pointer, run.get_net_radius())
		):
			_start_net(pointer)
	_advance_net(delta)
	if _view.is_overview():
		_net.hide()
	if _net_phase == NetPhase.IDLE and not _can_collect(pointer, run.get_net_radius()):
		_net.hide()
	_was_holding = holding


func _start_net(pointer: Vector2) -> void:
	if not run.begin_net_cast():
		return
	_net_phase = NetPhase.CASTING
	_net_elapsed = 0.0
	_net_anchor = pointer
	_net_caught_count = 0
	var direction: Vector2 = pointer.normalized()
	if direction.is_zero_approx():
		direction = Vector2.UP
	_net_origin = direction * (_planet.radius + 80.0)
	_net.show_cast(_net_origin, run.get_net_radius(), 0.0)


func _advance_net(delta: float) -> void:
	var net_radius: float = run.get_net_radius()
	match _net_phase:
		NetPhase.CASTING:
			_net_elapsed += delta
			var progress: float = clampf(_net_elapsed / _net.cast_seconds, 0.0, 1.0)
			_net.show_cast(_net_origin.lerp(_net_anchor, progress), net_radius, progress)
			if progress >= 1.0:
				_net_phase = NetPhase.CLOSING
				_net_elapsed = 0.0
		NetPhase.CLOSING:
			_net_elapsed += delta
			for slime: PrototypeSlime in _slimes:
				if slime.get_capture_point().distance_to(_net_anchor) <= net_radius:
					slime.apply_attraction(delta, _net_anchor, _net_elapsed / _net.close_seconds)
			_net.show_open(_net_anchor, net_radius, _net_elapsed / _net.close_seconds)
			if _net_elapsed >= _net.close_seconds:
				_resolve_net()
				_net_phase = NetPhase.RESULT
				_net_elapsed = 0.0
				_net.show_result(_net_anchor, _net_caught_count)
		NetPhase.RESULT:
			_net_elapsed += delta
			_net.show_result(_net_anchor, _net_caught_count)
			if _net_elapsed >= net_result_seconds:
				_net_phase = NetPhase.IDLE
		NetPhase.IDLE:
			if _active_tool != ToolMode.NET:
				_net.hide()
			elif run.can_cast_net():
				_net.show_preview(_tool_pointer, net_radius)
			else:
				_net.show_cooldown(
					_tool_pointer,
					net_radius,
					run.net_cooldown_remaining,
					run.settings.net_cooldown_seconds
				)


func _resolve_net() -> void:
	var candidates: Array[PrototypeSlime] = []
	var radius_squared: float = run.get_net_radius() * run.get_net_radius()
	for slime: PrototypeSlime in _slimes:
		if slime.get_capture_point().distance_squared_to(_net_anchor) <= radius_squared:
			candidates.append(slime)
	candidates.sort_custom(_is_nearer_to_net)
	var caught_count: int = mini(candidates.size(), run.get_net_capacity())
	var source_ids: Array[int] = []
	var rewards: Array[int] = []
	for index: int in range(caught_count):
		var slime: PrototypeSlime = candidates[index]
		source_ids.append(slime.nest_id)
		rewards.append(slime.reward)
		_slimes.erase(slime)
		_capture_targets.erase(slime)
		slime.consumed = true
		slime.hide()
		slime.set_process(false)
		slime.queue_free()
	var reward: int = run.collect_net_batch(source_ids, rewards)
	_net_caught_count = caught_count
	if reward > 0:
		_play_collection_reward(reward, _net_anchor)
		_collect_sound.pitch_scale = 0.75
		_collect_sound.play()


func _is_nearer_to_net(first: PrototypeSlime, second: PrototypeSlime) -> bool:
	return (
		first.get_capture_point().distance_squared_to(_net_anchor)
		< second.get_capture_point().distance_squared_to(_net_anchor)
	)


func _can_collect(pointer: Vector2, radius: float) -> bool:
	var viewport_position: Vector2 = _world.get_global_transform_with_canvas() * pointer
	return (
		_window_has_focus
		and not _view.is_overview()
		and get_viewport_rect().has_point(viewport_position)
		and not _view.is_dragging()
		and not _layout.is_over_ui(viewport_position)
		and not _is_over_selected_nest(viewport_position)
		and pointer.length() + radius >= _planet.get_inner_radius(pointer.angle())
		and pointer.length() - radius <= _planet.get_outer_radius(pointer.angle())
	)


func _select_tool(tool: ToolMode) -> void:
	if tool == ToolMode.NET and not run.net_unlocked:
		_layout._show_quick_upgrade(1)
		return
	_capture_at(0.0, _tool_pointer, false)
	_was_holding = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_active_tool = tool
	_pipe.visible = tool == ToolMode.PIPE
	_net.visible = tool == ToolMode.NET or _net_phase != NetPhase.IDLE
	_refresh_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_1:
				_select_tool(ToolMode.PIPE)
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_2:
				_select_tool(ToolMode.NET)
				get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _view.is_dragging():
		return
	if event is InputEventMouseMotion:
		_view.drag_to((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT and not button.pressed:
			_view.end_drag()
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_view_blocks_tool_until_release = true
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if _layout.is_over_ui(button.position):
		return
	if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		var on_planet: bool = _view.contains_planet_body(button.position)
		var can_start_drag: bool = not on_planet if _view.is_overview() else on_planet
		if (
			not _window_has_focus
			or not get_viewport_rect().has_point(button.position)
			or not can_start_drag
			or _is_over_selected_nest(button.position)
		):
			return
		_view_blocks_tool_until_release = true
		_clear_nest_selection()
		_capture_at(0.0, _tool_pointer, false)
		_view.begin_drag(button.position)
		get_viewport().set_input_as_handled()
	elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var steps: float = 1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		if _view.is_overview() != (steps < 0.0):
			_view_blocks_tool_until_release = true
			_clear_nest_selection()
			_capture_at(0.0, _tool_pointer, false)
		_view.zoom_steps(steps * button.factor)
		get_viewport().set_input_as_handled()


func _cancel_view_drag() -> void:
	_view.end_drag()
	_view_blocks_tool_until_release = true
	_was_holding = false
	_clear_nest_selection()
	_capture_at(0.0, _tool_pointer, false)


func _on_window_focus_exited() -> void:
	_window_has_focus = false
	_cancel_view_drag()
	_capture_at(0.0, _tool_pointer, false)
	_pipe.hide()


func _on_window_focus_entered() -> void:
	_window_has_focus = true


func _apply_layout() -> void:
	var play_rect: Rect2 = _layout.apply_layout(get_viewport_rect().size)
	_view.configure(play_rect, _planet.radius)
	var screen_half_angle: float = _get_roaming_screen_half_angle()
	for slime: PrototypeSlime in _slimes:
		slime.configure_roaming(screen_half_angle)


func _get_roaming_screen_half_angle() -> float:
	return _view.get_near_screen_half_angle(_planet.radius)


func _sync_view_rotation() -> void:
	if _view.is_overview():
		return
	for nest: NestView in _nest_views:
		nest.rotation = -_world.rotation


func _sync_view_presentation() -> void:
	_clear_nest_selection()
	_capture_at(0.0, _tool_pointer, false)
	var near_view: bool = not _view.is_overview()
	%InputHint.text = ("悬停吸取 · 左键投网 · 右键拖动星球 · 滚轮切换视图" if near_view else "右键拖动空白处 · 滚轮返回近景")
	_slime_root.visible = near_view
	_nests.visible = near_view
	_mucus_root.visible = near_view
	_effects.visible = near_view
	_region_root.visible = near_view
	if not near_view:
		_pipe.hide()
		_net.hide()
	var crust_changed: bool = _planet.set_near_view(near_view)
	for slime: PrototypeSlime in _slimes:
		slime.presentation_scale = _view.near_slime_scale if near_view else 1.0
	for nest: NestView in _nest_views:
		nest.presentation_scale = _view.near_nest_scale if near_view else Vector2.ONE
		nest.rotation = -_world.rotation
	for region: GovernedRegion in _regions:
		if crust_changed:
			region.refresh_surface()
	for trail: MucusField in _mucus_trails:
		if crust_changed:
			trail.refresh_surface()
	for area: NestMucusArea in _nest_mucus_areas:
		if crust_changed:
			area.refresh_surface()
	_refresh_overview()


func restart_run() -> void:
	_layout.close_panels()
	if _restore_tween != null:
		_restore_tween.kill()
	if _status_tween != null:
		_status_tween.kill()
	for container: Node2D in [_nests, _region_root, _slime_root, _effects, _mucus_root]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_nest_views.clear()
	_regions.clear()
	_automatic_attempts.clear()
	_mucus_trails.clear()
	_active_mucus_trails.clear()
	_nest_mucus_areas.clear()
	_slimes.clear()
	_capture_targets.clear()
	selected_nest_id = -1
	_was_holding = false
	_view_blocks_tool_until_release = false
	_view.reset_view()
	_net_phase = NetPhase.IDLE
	_net_elapsed = 0.0
	_net_caught_count = 0
	_active_tool = ToolMode.PIPE
	_net.hide()
	_pipe.show()
	_spawn_directions.clear()
	_completion.hide()
	_planet.set_restored(0.0)
	_status_label.text = ""
	_status_label.modulate.a = 1.0
	var spawn_positions: Array[Vector2] = []
	for offset: float in [-0.22, 0.22, 0.78]:
		var angle: float = -PI / 2.0 + offset
		spawn_positions.append(_planet.get_nest_position(angle))
	_site_random.randomize()
	run.start_run(spawn_positions)
	_tool_pointer = _world.to_local(get_global_mouse_position())
	_pipe.position = _tool_pointer
	_refresh_hud()


func _capture_at(delta: float, target: Vector2, active: bool) -> void:
	var radius: float = run.get_pipe_radius()
	var radius_squared: float = radius * radius
	var nearest: PrototypeSlime = null
	var nearest_distance: float = radius_squared
	if active and not _capture_targets.is_empty():
		var previous: PrototypeSlime = _capture_targets[0]
		if (
			is_instance_valid(previous)
			and not previous.consumed
			and previous.get_capture_point().distance_squared_to(target) <= radius_squared
		):
			nearest = previous
	if active and nearest == null:
		for candidate: PrototypeSlime in _slimes:
			var distance: float = candidate.get_capture_point().distance_squared_to(target)
			if not candidate.consumed and distance <= nearest_distance:
				nearest = candidate
				nearest_distance = distance
	# Only a former target needs its partial capture cancelled. Unrelated actors
	# must not be redrawn or copied into a new population array every tool tick.
	for previous: PrototypeSlime in _capture_targets:
		if is_instance_valid(previous) and previous != nearest:
			previous.capture_progress = 0.0
			previous.release_capture(delta)
	_capture_targets.clear()
	if nearest == null:
		return
	_capture_targets.append(nearest)
	nearest.on_mucus = _is_on_ground_mucus(nearest.position)
	var capture_delta: float = delta
	var peel_seconds: float = run.get_pipe_capture_seconds()
	if nearest.is_anchored():
		capture_delta = maxf(0.0, delta - (1.0 - nearest.peel_progress) * peel_seconds)
	if not nearest.pull_off_mucus(delta, target, peel_seconds):
		return
	if not nearest.apply_capture(capture_delta, _capture_seconds_for(nearest), target):
		return
	var before: int = run.candy
	var accepted: bool = run.collect_slime(nearest.nest_id, nearest.reward)
	assert(accepted, "Collected monster must belong to its source population.")
	_play_collection_reward(run.candy - before, nearest.get_capture_point())
	_capture_targets.clear()
	_slimes.erase(nearest)
	nearest.hide()
	nearest.set_process(false)
	nearest.queue_free()
	_collect_sound.pitch_scale = randf_range(0.92, 1.12)
	_collect_sound.play()


func _capture_seconds_for(slime: PrototypeSlime) -> float:
	var seconds: float = run.get_pipe_capture_seconds()
	if slime.species == PrototypeSlime.Species.MUCUS:
		return seconds
	if _is_on_ground_mucus(slime.position):
		return seconds * run.settings.mucus_slow_multiplier
	return seconds


func _is_on_ground_mucus(point: Vector2) -> bool:
	for area: NestMucusArea in _nest_mucus_areas:
		if area.contains_ground_point(point):
			return true
	for patch: MucusField in _mucus_trails:
		if patch.contains_ground_point(point):
			return true
	return false


func _advance_ground_mucus(delta: float) -> void:
	for index: int in range(_mucus_trails.size() - 1, -1, -1):
		var trail: MucusField = _mucus_trails[index]
		if not trail.advance(delta, false):
			_retire_mucus_trail(trail)
	var emitting_ids: Dictionary = {}
	for slime: PrototypeSlime in _slimes:
		if slime.can_emit_ground_mucus():
			emitting_ids[slime.get_instance_id()] = true
	# Drop stale ownership before allocating: only inactive history may be evicted.
	for actor_id: int in _active_mucus_trails.keys():
		if not emitting_ids.has(actor_id):
			_active_mucus_trails.erase(actor_id)
	for slime: PrototypeSlime in _slimes:
		var actor_id: int = slime.get_instance_id()
		if emitting_ids.has(actor_id):
			var trail: MucusField = _active_mucus_trails.get(actor_id) as MucusField
			if (
				trail != null
				and (
					trail.get_ground_points()[-1].distance_to(slime.position)
					> run.settings.mucus_trail_max_length * 0.5
				)
			):
				_active_mucus_trails.erase(actor_id)
				trail = null
			if trail == null:
				trail = _start_mucus_trail(slime)
			trail.append_ground_point(slime.position, false)
	_trim_mucus_history()
	for trail: MucusField in _mucus_trails:
		trail.refresh_surface(false, trail.is_detail_on_screen())
	for slime: PrototypeSlime in _slimes:
		if slime.species == PrototypeSlime.Species.MUCUS:
			slime.on_mucus = _is_on_ground_mucus(slime.position)


func _start_mucus_trail(slime: PrototypeSlime) -> MucusField:
	_active_mucus_trails.erase(slime.get_instance_id())
	_trim_mucus_history(1)
	var trail: MucusField = MUCUS_SCENE.instantiate() as MucusField
	_mucus_root.add_child(trail)
	trail.source_actor_id = slime.get_instance_id()
	trail.configure(
		_planet,
		slime.position,
		slime.nest_id,
		run.settings.mucus_trail_half_width,
		run.settings.mucus_trail_lifetime,
		run.settings.mucus_trail_max_length,
		run.settings.mucus_trail_sample_spacing
	)
	_mucus_trails.append(trail)
	_active_mucus_trails[trail.source_actor_id] = trail
	return trail


func _trim_mucus_history(reserved: int = 0) -> void:
	# Live emitters each keep their ribbon. The history budget can grow to the
	# live-source count, then shrinks as sources stop; it never caps population.
	var retained_limit: int = maxi(
		run.settings.mucus_trail_limit, _active_mucus_trails.size() + reserved
	)
	if _mucus_trails.size() + reserved <= retained_limit:
		return
	for trail: MucusField in _mucus_trails.duplicate():
		if _active_mucus_trails.get(trail.source_actor_id) == trail:
			continue
		_retire_mucus_trail(trail)
		if _mucus_trails.size() + reserved <= retained_limit:
			break


func _retire_mucus_trail(trail: MucusField) -> void:
	_mucus_trails.erase(trail)
	if _active_mucus_trails.get(trail.source_actor_id) == trail:
		_active_mucus_trails.erase(trail.source_actor_id)
	trail.queue_free()


func _refresh_overview() -> void:
	_overview.update_nest_clusters(run.nests)
	_overview.update_ecology(
		run.get_species_population(NestState.Species.SLIME),
		run.get_species_population(NestState.Species.MUCUS),
		_view.is_overview(),
		get_viewport_rect().size
	)


func _play_collection_reward(reward: int, source_position: Vector2) -> void:
	if _view.is_overview():
		return
	var effect: CollectionEffect = collection_scene.instantiate() as CollectionEffect
	_effects.add_child(effect)
	effect.top_level = true
	effect.global_transform = Transform2D.IDENTITY
	var origin: Vector2 = _world.to_global(source_position)
	var destination: Vector2 = (
		_candy_label.get_global_transform_with_canvas() * (_candy_label.size * 0.5)
	)
	effect.play(origin, destination, reward)


func _on_nest_spawn_requested(species: NestState.Species) -> void:
	var points: Array[Vector2] = []
	var weights: Array[float] = []
	var total_weight: float = 0.0
	for _attempt: int in range(run.settings.nest_site_samples):
		var angle: float = _site_random.randf_range(0.0, TAU)
		var point: Vector2 = _planet.get_nest_position(angle)
		var legal: bool = true
		var weight: float = 1.0
		for nest: NestState in run.nests:
			var distance: float = nest.position.distance_to(point)
			if distance < run.settings.nest_min_distance:
				legal = false
				break
			if (
				nest.species == species
				and not nest.is_tamed
				and distance < run.settings.same_species_soft_distance
			):
				weight *= run.settings.same_species_near_weight
		if legal:
			points.append(point)
			weights.append(weight)
			total_weight += weight
	if points.is_empty():
		run.resolve_nest_spawn(Vector2.ZERO, false)
		return
	var roll: float = _site_random.randf() * total_weight
	var selected: Vector2 = points.back()
	for index: int in range(points.size()):
		roll -= weights[index]
		if roll <= 0.0:
			selected = points[index]
			break
	run.resolve_nest_spawn(selected)


func _on_nest_added(nest: NestState) -> void:
	var region: GovernedRegion = REGION_SCENE.instantiate() as GovernedRegion
	_region_root.add_child(region)
	region.configure(_planet, nest.position)
	region.species = nest.species
	_regions.append(region)
	if nest.species == NestState.Species.MUCUS:
		var area: NestMucusArea = NEST_MUCUS_SCENE.instantiate() as NestMucusArea
		_mucus_root.add_child(area)
		area.configure(
			_planet,
			nest.position,
			nest.nest_id,
			region.region_radius * run.settings.mucus_nest_coverage_multiplier
		)
		_nest_mucus_areas.append(area)
	var view: NestView = nest_scene.instantiate() as NestView
	_nests.add_child(view)
	view.position = nest.position
	view.setup(nest.nest_id)
	view.rotation = -_world.rotation
	view.configure_species(nest.species)
	view.presentation_scale = _view.near_nest_scale if not _view.is_overview() else Vector2.ONE
	view.update_state(nest.level, nest.is_tamed, run.settings.nest_upgrade_costs.size())
	_nest_views.append(view)
	_refresh_hud()


func _on_nest_changed(nest: NestState) -> void:
	_nest_views[nest.nest_id - 1].update_state(
		nest.level, nest.is_tamed, run.settings.nest_upgrade_costs.size()
	)
	_regions[nest.nest_id - 1].stage = nest.level
	_queue_hud_refresh()


func _on_slime_requested(nest_id: int) -> void:
	var nest: NestState = run.get_nest(nest_id)
	var slime: PrototypeSlime = slime_scene.instantiate() as PrototypeSlime
	_slime_root.add_child(slime)
	slime.setup(nest_id, nest.position, _planet, _get_roaming_screen_half_angle())
	slime.presentation_scale = _view.near_slime_scale if not _view.is_overview() else 1.0
	var direction_index: int = int(_spawn_directions.get(nest_id, 0))
	_spawn_directions[nest_id] = direction_index + 1
	var species: PrototypeSlime.Species = nest.species as PrototypeSlime.Species
	var valuable: bool = (
		nest.valuable_level > 0 and direction_index % run.settings.valuable_spawn_every == 0
	)
	var reward: int = (
		run.settings.slime_reward * (2 if species == PrototypeSlime.Species.MUCUS else 1)
	)
	if valuable:
		reward *= run.settings.valuable_reward_multiplier
	slime.configure_species(species, valuable, reward)
	var direction_angle: float = (
		float(direction_index) * 2.399963 + nest.position.angle() + randf_range(-0.14, 0.14)
	)
	slime.launch(Vector2.from_angle(direction_angle))
	_slimes.append(slime)


func _on_auto_collect_requested(nest_id: int) -> void:
	var nest: NestState = run.get_nest(nest_id)
	var candidate: PrototypeSlime = null
	var candidate_priority: int = -1
	var attempts: int = int(_automatic_attempts.get(nest_id, 0)) + 1
	_automatic_attempts[nest_id] = attempts
	for slime: PrototypeSlime in _slimes:
		if slime.nest_id != nest_id or slime.consumed or _capture_targets.has(slime):
			continue
		if slime._launch_elapsed < slime.launch_seconds:
			continue
		var priority: int = 0
		if slime.high_value:
			if not nest.is_tamed or attempts % 6 != 0:
				continue
			priority = 2
		elif slime.species == PrototypeSlime.Species.MUCUS:
			if attempts % 3 != 0:
				continue
			priority = 1
		if priority > candidate_priority:
			candidate = slime
			candidate_priority = priority
	if candidate == null:
		return
	candidate.consumed = true
	_slimes.erase(candidate)
	var collected: bool = run.collect_automatic(nest_id, candidate.reward)
	assert(collected, "Automatic collection must consume its reserved living actor.")
	if not collected:
		candidate.consumed = false
		_slimes.append(candidate)
		return
	if not _view.is_overview():
		var origin: Vector2 = _world.to_global(candidate.get_capture_point())
		var destination: Vector2 = _world.to_global(_nest_views[nest_id - 1].get_collection_point())
		var effect: CollectionEffect = collection_scene.instantiate() as CollectionEffect
		_effects.add_child(effect)
		effect.top_level = true
		effect.global_transform = Transform2D.IDENTITY
		effect.color = Color("98d2ad")
		effect.play(origin, destination, candidate.reward)
		_nest_views[nest_id - 1].pulse_automatic()
	candidate.hide()
	candidate.set_process(false)
	candidate.queue_free()


func _select_nest(nest_id: int) -> void:
	selected_nest_id = nest_id
	_layout.selected_technology_nest_id = nest_id
	for view: NestView in _nest_views:
		view.set_selected(view.nest_id == nest_id)
	_refresh_hud()
	_layout.show_nest_details(_nest_views[nest_id - 1].get_hover_rect())


func _update_nest_hover(viewport_position: Vector2) -> void:
	if _view.is_overview() or _view.is_dragging() or _layout.is_technology_open():
		_clear_nest_selection()
		return
	if selected_nest_id >= 0 and _layout.is_over_nest_details(viewport_position):
		_layout.show_nest_details(_nest_views[selected_nest_id - 1].get_hover_rect())
		return
	if _layout.is_over_ui(viewport_position):
		_clear_nest_selection()
		return
	for view: NestView in _nest_views:
		if view.contains_viewport_point(viewport_position):
			if selected_nest_id != view.nest_id:
				_select_nest(view.nest_id)
			else:
				_layout.show_nest_details(view.get_hover_rect())
			return
	if selected_nest_id >= 0:
		var selected_view: NestView = _nest_views[selected_nest_id - 1]
		if selected_view.get_hover_rect().has_point(viewport_position):
			_layout.show_nest_details(selected_view.get_hover_rect())
			return
	_clear_nest_selection()


func _is_over_selected_nest(viewport_position: Vector2) -> bool:
	return (
		selected_nest_id >= 0
		and _nest_views[selected_nest_id - 1].contains_viewport_point(viewport_position)
	)


func _clear_nest_selection() -> void:
	if selected_nest_id >= 0:
		_nest_views[selected_nest_id - 1].set_selected(false)
		selected_nest_id = -1
	_layout.hide_nest_details()


func _queue_hud_refresh() -> void:
	if _hud_refresh_queued:
		return
	_hud_refresh_queued = true
	_refresh_hud.call_deferred()


func _refresh_hud() -> void:
	_hud_refresh_queued = false
	_refresh_overview()
	_candy_label.text = "%d 糖果" % run.candy
	_passive_label.text = "治理版图  %d 区" % run.generated_nests
	_progress_label.text = "已自动化 %d / %d" % [run.completed_nests, run.generated_nests]
	_progress_bar.max_value = maxi(1, run.generated_nests)
	_progress_bar.value = run.completed_nests
	_tool_level_label.text = (
		"Lv. %d" % ((run.pipe_level if _active_tool == ToolMode.PIPE else run.net_level) + 1)
	)
	_pipe_button.button_pressed = _active_tool == ToolMode.PIPE
	_net_button.button_pressed = _active_tool == ToolMode.NET
	_quick_pipe_button.button_pressed = _active_tool == ToolMode.PIPE
	_quick_net_button.button_pressed = _active_tool == ToolMode.NET
	_pipe_button.disabled = false
	_net_button.disabled = not run.net_unlocked
	_quick_pipe_button.disabled = false
	_quick_net_button.disabled = false
	_layout.refresh_progression(run)
	var tool_cost: int = (
		run.get_pipe_upgrade_cost() if _active_tool == ToolMode.PIPE else run.get_net_upgrade_cost()
	)
	if _active_tool == ToolMode.PIPE:
		_tool_stats_label.text = "处理 %.2f 秒 / 只" % run.get_pipe_capture_seconds()
		if tool_cost >= 0:
			_tool_stats_label.text += (
				"\n升级后 %.2f 秒 / 只" % run.settings.pipe_capture_seconds[run.pipe_level + 1]
			)
	else:
		_tool_stats_label.text = "容量 %d 只" % run.get_net_capacity()
		if tool_cost >= 0:
			_tool_stats_label.text += (
				"\n升级后 %d 只" % run.settings.net_capacities[run.net_level + 1]
			)
	_tool_button.disabled = tool_cost < 0 or run.candy < tool_cost
	_tool_button.text = (
		"已满级"
		if tool_cost < 0
		else "%s升级 · %d 糖果" % ["速度" if _active_tool == ToolMode.PIPE else "容量", tool_cost]
	)
	_tool_button.tooltip_text = ""
	var nest: NestState = run.get_nest(selected_nest_id)
	if nest == null:
		_nest_title_label.text = "巢穴"
		_nest_level_label.text = "悬停巢穴查看升级"
		_nest_benefit_label.text = ""
		_nest_button.text = "驯化"
		_nest_button.disabled = true
		return
	_nest_title_label.text = (
		"%s巢穴 %02d" % ["黏液怪" if nest.species == NestState.Species.MUCUS else "史莱姆", nest.nest_id]
	)
	if nest.is_tamed:
		_nest_level_label.text = (
			"完全治理 · 生物 %d / %d" % [nest.alive_slimes, run.get_nest_population_limit(nest.nest_id)]
		)
		_nest_benefit_label.text = "持续繁衍 · 自动采集\n黏液与金色个体处理较慢"
		_nest_button.text = "生态运转中"
		_nest_button.disabled = true
		return
	var stage_names: Array[String] = ["野生", "培育中", "半治理"]
	_nest_level_label.text = (
		"%s · 生物 %d / %d"
		% [stage_names[nest.level], nest.alive_slimes, run.get_nest_population_limit(nest.nest_id)]
	)
	var next_level: int = nest.level + 1
	if next_level == run.settings.nest_upgrade_costs.size():
		_nest_benefit_label.text = "稳定核心 · 加速自动采集\n保留生态，扩展新区域"
	else:
		_nest_benefit_label.text = (
			"每 %.0f → %.0f 秒喷发一批\n上限 %d → %d 只"
			% [
				run.settings.spawn_intervals[nest.level],
				run.settings.spawn_intervals[next_level],
				run.get_nest_population_limit(nest.nest_id),
				run.settings.nest_population_limits[next_level]
			]
		)
		if next_level == 2:
			_nest_benefit_label.text = (
				"部署自动设施\n缓慢采集黏液，金色个体需手动"
				if nest.species == NestState.Species.MUCUS
				else "部署自动设施\n自动采集史莱姆，金色个体需手动"
			)
	var nest_cost: int = run.get_nest_upgrade_cost(selected_nest_id)
	var requirement: String = run.get_nest_upgrade_requirement(selected_nest_id)
	_nest_button.text = "治理 · %d 糖果" % nest_cost if requirement.is_empty() else requirement
	_nest_button.disabled = run.candy < nest_cost or not requirement.is_empty()


func _on_tool_upgrade() -> void:
	var upgraded: bool = run.upgrade_pipe() if _active_tool == ToolMode.PIPE else run.upgrade_net()
	if upgraded:
		_upgrade_sound.play()
		_show_status("管子处理更快了" if _active_tool == ToolMode.PIPE else "捕网容量增加了")


func _on_nest_upgrade() -> void:
	if run.upgrade_nest(selected_nest_id):
		var nest: NestState = run.get_nest(selected_nest_id)
		if nest.is_tamed:
			_tame_sound.play()
			_show_status("治理完成，生态继续运转")
		else:
			_upgrade_sound.play()
			_show_status("自动设施开始运转" if nest.level == 2 else "生态区开始繁荣")


func _on_quick_upgrade(tool: int) -> void:
	_on_technology_upgrade("pipe" if tool == 0 else "net")


func _on_technology_upgrade(technology_id: String) -> void:
	var unlocking_net: bool = technology_id == "net" and not run.net_unlocked
	if run.purchase_technology(technology_id):
		_refresh_hud()
		_upgrade_sound.play()
		if unlocking_net:
			_show_status("捕网已解锁" if run.is_complete else "捕网已解锁，邻近出现黏液巢穴")
		else:
			_show_status("科技升级完成")


func _on_nest_technology_upgrade(nest_id: int, technology_id: String) -> void:
	if run.purchase_nest_technology(nest_id, technology_id):
		_upgrade_sound.play()
		_show_status("生态区 %02d 开始孕育金色个体" % nest_id)


func _show_status(message: String) -> void:
	if _status_tween != null:
		_status_tween.kill()
	_status_label.text = message
	_status_label.modulate.a = 1.0
	_status_tween = create_tween()
	_status_tween.tween_interval(1.7)
	_status_tween.tween_property(_status_label, "modulate:a", 0.0, 0.5)


func _on_goal_completed() -> void:
	_refresh_hud()
	_restore_tween = create_tween()
	_restore_tween.tween_method(_planet.set_restored, 0.0, 1.0, 1.1)
	_restore_tween.tween_interval(0.4)
	_restore_tween.tween_callback(_show_completion)


func _show_completion() -> void:
	_layout.close_panels()
	_finish_sound.play()
	_completion_title.text = "整个星球，生生不息"
	_completion_detail.text = "全部 %d 座巢穴已自动化。\n设施持续工作，你仍可继续捕获与研究。" % run.generated_nests
	_completion.show()
	%ReplayButton.grab_focus()


func _close_victory() -> void:
	_completion.hide()
