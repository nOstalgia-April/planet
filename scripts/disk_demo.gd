extends Node2D

signal flower_appeared(nest_id: int, species: int)

const PipeCursor = preload("res://scripts/pipe_cursor.gd")
const PlanetViewController = preload("res://scripts/planet_view_controller.gd")
const GovernedRegion = preload("res://scripts/governed_region.gd")
const REGION_SCENE: PackedScene = preload("res://scenes/world/governed_region.tscn")
const MucusField = preload("res://scripts/mucus_field.gd")
const MUCUS_SCENE: PackedScene = preload("res://scenes/effects/mucus_field.tscn")
const DRILL_SCENE: PackedScene = preload("res://scenes/world/drill_monster.tscn")
const TREASURE_SCENE: PackedScene = preload("res://scenes/effects/drill_treasure.tscn")
const DrillTreasure = preload("res://scripts/drill_treasure.gd")
const NestMucusArea = preload("res://scripts/nest_mucus_area.gd")
const NEST_MUCUS_SCENE: PackedScene = preload("res://scenes/effects/nest_mucus_area.tscn")
const VacuumAudio = preload("res://scripts/vacuum_audio.gd")
const GiantFusion = preload("res://scripts/giant_slime_fusion.gd")
const GiantHarvestEffect = preload("res://scripts/giant_harvest_effect.gd")
const MonsterAudio = preload("res://scripts/monster_audio.gd")
const PlanetAudio = preload("res://scripts/planet_audio.gd")
const MonsterDepth = preload("res://scripts/monster_depth.gd")
const ViewGestureFilter = preload("res://scripts/view_gesture_filter.gd")

# Music stages drive the global FMOD parameter GameStage (0 / 1 / 2); its Seek
# modulator in FMOD turns each step into a crossfade between the music layers.
const MUSIC_STAGE_PARAMETER: String = "GameStage"
const GAMEPLAY_MUSIC: String = "event:/Mx/Mx_GamePlay"
# Gameplay music parameter: 0 in the near view (stems A + B), 1 in the
# overview (stems A + C). It follows the camera zoom continuously.
const MUSIC_DISTANT_VIEW_PARAMETER: String = "IsDistantView"
# Stage 2 starts with the third base value breakthrough (900 candy, 5 -> 10).
const MUSIC_MID_BASE_VALUE_LEVEL: int = 3
# Stage 3 starts once full automation is researched (4500 candy).
const MUSIC_LATE_GOVERNANCE_LEVEL: int = 3

enum ToolMode { PIPE, NET }
enum NetPhase { IDLE, CASTING, CLOSING, RESULT }

@export var slime_scene: PackedScene
@export var giant_slime_scene: PackedScene
@export var nest_scene: PackedScene
@export var collection_scene: PackedScene
@export var giant_harvest_scene: PackedScene
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
var _mucus_trails: Array[MucusField] = []
var _active_mucus_trails: Dictionary = {}
var _nest_mucus_areas: Array[NestMucusArea] = []
var _completion_tween: Tween
var _status_tween: Tween
var _hud_refresh_queued: bool = false
var _overview_sample_elapsed: float = 0.0
var _giant_check_elapsed: float = 0.0
var _giant_harvest: GiantHarvestEffect
var _site_random: RandomNumberGenerator = RandomNumberGenerator.new()
var _nest_site_angles: PackedFloat32Array = PackedFloat32Array()
var _nest_site_jitter: float = 0.0
var _nest_site_distance: float = 0.0
var _vacuum_audio: VacuumAudio
var _monster_audio: MonsterAudio
# Combo bonus paid during the current pipe capture; kept out of Candy_Value.
var _capture_combo_bonus: int = 0
var _planet_audio: PlanetAudio
var _opening_nests: bool = false
var _population_by_species: Dictionary = {}
var _music_stage: int = 0
var _view_gestures: ViewGestureFilter = ViewGestureFilter.new()

@onready var run: PrototypeRun = $Run
@onready var _world: Node2D = $World
@onready var _view: PlanetViewController = %PlanetViewController
@onready var _planet: PlanetSurface = %PlanetSurface
@onready var _nests: Node2D = %Nests
@onready var _region_root: Node2D = %Regions
@onready var _slime_root: MonsterDepth = %Slimes
@onready var _effects: Node2D = %Effects
@onready var _mucus_root: Node2D = %GroundMucus
@onready var _overview: OverviewEcology = %OverviewEcology
@onready var _pipe: PipeCursor = %Pipe
@onready var _net: CaptureNet = %CaptureNet
@onready var _layout: DiskDemoLayout = %Interface
@onready var _candy_label: Label = %CandyLabel
@onready var _passive_label: Label = %PassiveLabel
@onready var _quick_pipe_button: Button = $HUD/Interface/ToolDock/Pipe/Button
@onready var _quick_net_button: Button = $HUD/Interface/ToolDock/Net/Button
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
	assert(giant_slime_scene != null, "Fusion requires the reusable giant slime scene.")
	assert(giant_harvest_scene != null, "Giant capture requires its harvest effect scene.")
	GameAudio.play_music(GAMEPLAY_MUSIC)
	# Leaving the game in the overview must not leave near-view sounds muted.
	tree_exiting.connect(GameAudio.set_near_view_gain.bind(1.0))
	tree_exiting.connect(
		GameAudio.set_music_parameter.bind(GAMEPLAY_MUSIC, MUSIC_DISTANT_VIEW_PARAMETER, 0.0)
	)
	_vacuum_audio = VacuumAudio.new()
	_vacuum_audio.name = "VacuumAudio"
	$Audio.add_child(_vacuum_audio)
	_monster_audio = MonsterAudio.new()
	_monster_audio.name = "MonsterAudio"
	$Audio.add_child(_monster_audio)
	_planet_audio = PlanetAudio.new()
	_planet_audio.name = "PlanetAudio"
	$Audio.add_child(_planet_audio)
	get_viewport().physics_object_picking = true
	run.economy_changed.connect(_queue_hud_refresh)
	run.combo_stage_completed.connect(_on_combo_stage_completed)
	run.combo_progressed.connect(_layout.pulse_combo)
	run.combo_interrupted.connect(_layout.pulse_combo.bind(true))
	run.combo_interrupted.connect(_monster_audio.combo_broken)
	run.economy_changed.connect(_update_music_stage)
	run.base_value_changed.connect(_refresh_monster_rewards)
	run.nest_added.connect(_on_nest_added)
	run.nest_spawn_requested.connect(_on_nest_spawn_requested)
	run.nest_changed.connect(_on_nest_changed)
	run.slime_requested.connect(_on_slime_requested)
	run.goal_completed.connect(_on_goal_completed)
	run.automatic_income_received.connect(_on_automatic_income_received)
	_layout.quick_upgrade_requested.connect(_on_quick_upgrade)
	_layout.technology_upgrade_requested.connect(_on_technology_upgrade)
	_register_purchase_sounds()
	GameCursor.register_vacuum(_pipe)
	_quick_pipe_button.pressed.connect(_select_tool.bind(ToolMode.PIPE))
	_quick_net_button.pressed.connect(_select_tool.bind(ToolMode.NET))
	_nest_button.pressed.connect(_on_nest_upgrade)
	_layout.interaction_panel_changed.connect(_cancel_view_drag)
	_layout.restart_requested.connect(restart_run)
	_layout.view_switch_requested.connect(_toggle_view_shortcut)
	_view.view_changed.connect(_sync_view_presentation)
	_view.projection_changed.connect(_sync_view_projection)
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
	_layout.set_view_switch_enabled(_can_toggle_view())
	var pointer: Vector2 = get_viewport().get_mouse_position()
	_update_nest_hover(pointer)
	_update_overview_hover(pointer)
	run.advance(delta)
	_advance_giant_fusion(delta)
	if _view.is_overview():
		_overview_sample_elapsed += delta
		if _overview_sample_elapsed >= 0.4:
			_refresh_overview()
	_layout.refresh_timers(run)
	_advance_ground_mucus(delta)
	_advance_monster_chatter(delta)
	GameAudio.set_near_view_gain(_view.near_blend)
	GameAudio.set_music_parameter(
		GAMEPLAY_MUSIC, MUSIC_DISTANT_VIEW_PARAMETER, 1.0 - _view.near_blend
	)
	_planet_audio.update_zoom(_view.target_zoom, _view.is_transitioning())
	_planet_audio.update_rotation(delta, _view.is_dragging(), _world.rotation)
	var world_position: Vector2 = _world.to_local(get_global_mouse_position())
	var holding: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not holding and not _view.is_dragging():
		_view_blocks_tool_until_release = false
	holding = holding and not _view.is_dragging() and not _view_blocks_tool_until_release
	_drive_tool(delta, world_position, holding)


func _update_overview_hover(pointer: Vector2) -> void:
	_overview.update_hover(
		pointer,
		(
			_window_has_focus
			and _view.is_overview()
			and not _view.is_transitioning()
			and not _view.is_dragging()
			and get_viewport_rect().has_point(pointer)
			and not _layout.is_over_ui(pointer)
			and get_viewport().gui_get_hovered_control() == null
		)
	)


func _drive_tool(delta: float, pointer: Vector2, holding: bool) -> void:
	var just_pressed: bool = holding and not _was_holding
	_tool_pointer = pointer
	_pipe.visible = _active_tool == ToolMode.PIPE and _can_collect(pointer, run.get_pipe_radius())
	if _active_tool == ToolMode.PIPE:
		var tool_radius: float = run.get_pipe_radius()
		var capturing: bool = _can_collect(pointer, tool_radius)
		_pipe.radius = tool_radius
		_pipe.set_tool_state(pointer, pointer, capturing)
		_capture_at(delta, pointer, capturing)
	else:
		_capture_at(delta, pointer, false)
		if (
			just_pressed
			and _net_phase == NetPhase.IDLE
			and _can_collect(pointer, run.get_net_radius())
		):
			_start_net(pointer)
	_advance_net(delta)
	if _view.is_overview() or _view.is_transitioning():
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
	_monster_audio.net_cast()


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
				if (
					slime.can_net_capture()
					and slime.get_capture_point().distance_to(_net_anchor) <= net_radius
				):
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
		if (
			slime.can_net_capture()
			and slime.get_capture_point().distance_squared_to(_net_anchor) <= radius_squared
		):
			candidates.append(slime)
	candidates.sort_custom(_is_nearer_to_net)
	var caught_count: int = mini(candidates.size(), run.get_net_capacity())
	var source_ids: Array[int] = []
	var rewards: Array[int] = []
	var populations: Array[int] = []
	var caught_monsters: int = 0
	var caught_golden: bool = false
	for index: int in range(caught_count):
		var slime: PrototypeSlime = candidates[index]
		source_ids.append(slime.nest_id)
		rewards.append(slime.reward)
		populations.append(slime.population_units)
		caught_monsters += slime.population_units
		caught_golden = caught_golden or slime.high_value
		_slimes.erase(slime)
		_capture_targets.erase(slime)
		slime.consumed = true
		slime.hide()
		slime.set_process(false)
		slime.queue_free()
	var reward: int = run.collect_net_batch(source_ids, rewards, populations)
	_net_caught_count = caught_count
	if caught_count > 0:
		_monster_audio.net_captured()
	if caught_golden:
		_monster_audio.golden_collected()
	if reward > 0:
		_play_collection_reward(reward, _net_anchor)
		if _monster_audio.is_ready():
			_monster_audio.candy_from_net(reward, caught_monsters)
		else:
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
		and not _view.presentation_locked
		and not _view.is_overview()
		and not _view.is_transitioning()
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
	# Handle Tab before GUI focus traversal can consume it.
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.keycode == KEY_TAB and not key.get_modifiers_mask():
			if _can_change_view():
				if key.pressed and not key.echo:
					_toggle_view_shortcut()
				get_viewport().set_input_as_handled()
			return
	if event is InputEventPanGesture or event is InputEventMagnifyGesture:
		var gesture: InputEventGesture = event as InputEventGesture
		var allowed: bool = (
			_can_toggle_view()
			and get_viewport_rect().has_point(gesture.position)
			and not _layout.is_over_ui(gesture.position)
		)
		var steps: float = _view_gestures.feed(gesture, allowed)
		if not is_zero_approx(steps):
			_request_view_steps(steps)
		if allowed:
			get_viewport().set_input_as_handled()
		return
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
	if not _can_change_view():
		return
	if not event is InputEventMouseButton:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if _layout.is_over_ui(button.position):
		return
	if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		if (
			not _window_has_focus
			or not _view.is_overview()
			or _view.is_transitioning()
			or _view.is_dragging()
			or not get_viewport_rect().has_point(button.position)
		):
			return
		var bubble: OverviewEcology.Bubble = _overview.get_bubble_at(button.position)
		if bubble == null:
			return
		var surface_angle: float = bubble.cluster.angle
		_cancel_view_drag()
		_view.focus_surface(surface_angle)
		get_viewport().set_input_as_handled()
	elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		var on_planet: bool = _view.contains_planet_body(button.position)
		var can_start_drag: bool = not on_planet if _view.is_overview() else on_planet
		if (
			not _window_has_focus
			or not get_viewport_rect().has_point(button.position)
			or not can_start_drag
			or _view.is_transitioning()
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
		_view_gestures.suppress()
		_request_view_steps(steps * button.factor)
		get_viewport().set_input_as_handled()


func _can_change_view() -> bool:
	return (
		_window_has_focus and not _view.presentation_locked and not _layout.is_view_switch_blocked()
	)


func _can_toggle_view() -> bool:
	return _can_change_view() and not _view.is_transitioning() and not _view.is_dragging()


func _toggle_view_shortcut() -> void:
	if not _can_toggle_view():
		return
	_view_gestures.suppress()
	_request_view_steps(1.0 if _view.is_overview() else -1.0)


func _request_view_steps(steps: float) -> void:
	if is_zero_approx(steps):
		return
	if _view.is_overview() != (steps < 0.0):
		_view_blocks_tool_until_release = true
		_clear_nest_selection()
		_capture_at(0.0, _tool_pointer, false)
	_view.zoom_steps(steps)
	_layout.set_view_switch_enabled(_can_toggle_view())


func _cancel_view_drag() -> void:
	_view_gestures.suppress()
	_overview.update_hover(Vector2.ZERO, false)
	_view.end_drag()
	_planet_audio.update_rotation(0.0, false, _world.rotation)
	_view_blocks_tool_until_release = true
	_was_holding = false
	_clear_nest_selection()
	_capture_at(0.0, _tool_pointer, false)
	_vacuum_audio.stop_now()
	_pipe.hide()


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
	_fit_activity_hole()
	var screen_half_angle: float = _get_roaming_screen_half_angle()
	for slime: PrototypeSlime in _slimes:
		slime.configure_roaming(screen_half_angle)
		slime.refresh_surface_bounds()


func _fit_activity_hole() -> void:
	# Use the near endpoint even in overview: changing cameras must not change geography.
	var screen: Vector2 = get_viewport_rect().size
	var screen_radius: float = screen.x * _view.near_radius_ratio
	var center: Vector2 = Vector2(
		screen.x * (0.5 + _view.near_horizontal_offset_ratio),
		screen.y * _view.near_horizon_ratio + screen_radius
	)
	var clearance: Rect2 = _layout.get_tool_clearance_rect()
	var hole_radius: float = 0.0
	for corner: Vector2 in [
		clearance.position,
		clearance.end,
		Vector2(clearance.position.x, clearance.end.y),
		Vector2(clearance.end.x, clearance.position.y)
	]:
		hole_radius = maxf(hole_radius, center.distance_to(corner))
	var near_scale: float = screen_radius / (_planet.radius * _view.near_surface_radius_ratio)
	_planet.inner_radius_ratio = clampf(
		(hole_radius / near_scale + 1.0) / _planet.radius, 0.60, 0.95
	)


func _get_roaming_screen_half_angle() -> float:
	return _view.get_near_screen_half_angle(_planet.radius)


func _sync_view_presentation() -> void:
	_clear_nest_selection()
	_capture_at(0.0, _tool_pointer, false)
	var near_view: bool = not _view.is_overview()
	_layout.set_near_view(near_view, _view.is_transitioning())
	if not near_view or _view.is_transitioning():
		_pipe.hide()
		_net.hide()
	var crust_changed: bool = _planet.set_near_view(near_view)
	for slime: PrototypeSlime in _slimes:
		slime.presentation_scale = _view.near_slime_scale
	for nest: NestView in _nest_views:
		nest.presentation_scale = _view.near_nest_scale
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
	_sync_view_projection()


func _sync_view_projection() -> void:
	var blend: float = _view.near_blend
	for layer: Node2D in [_slime_root, _nests, _mucus_root, _effects]:
		layer.visible = blend > 0.0
		layer.modulate.a = blend
	_overview.set_view_opacity(1.0 - blend)


func restart_run() -> void:
	_layout.reset_pause()
	_layout.close_panels()
	_view_gestures.reset()
	_giant_harvest = null
	if _completion_tween != null:
		_completion_tween.kill()
	if _status_tween != null:
		_status_tween.kill()
	for container: Node2D in [_nests, _region_root, _slime_root, _effects, _mucus_root]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_nest_views.clear()
	_regions.clear()
	_mucus_trails.clear()
	_active_mucus_trails.clear()
	_nest_mucus_areas.clear()
	_slimes.clear()
	_giant_check_elapsed = 0.0
	_capture_targets.clear()
	_vacuum_audio.stop_now()
	_pipe.reset_transport()
	_pipe.reset_skin()
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
	_status_label.text = ""
	_status_label.modulate.a = 1.0
	_prepare_nest_sites()
	var spawn_positions: Array[Vector2] = []
	for index: int in range(run.settings.initial_nests):
		# Keep the opening pair as close to the near-view center as their full growth allows.
		var offset: float = _nest_site_jitter if index == 0 else -_nest_site_jitter
		var angle: float = _nest_site_angles[index] + offset
		spawn_positions.append(_planet.get_nest_position(angle))
	_site_random.randomize()
	# The opening nests are already there when play starts; only later nests "appear".
	_opening_nests = true
	run.start_run(spawn_positions, _nest_site_angles.size())
	_opening_nests = false
	_music_stage = 0
	GameAudio.set_global(MUSIC_STAGE_PARAMETER, 0.0)
	_tool_pointer = _world.to_local(get_global_mouse_position())
	_pipe.position = _tool_pointer
	_refresh_hud()


# Stages only move forward within a run; restart_run resets them.
func _update_music_stage() -> void:
	var stage: int = 0
	if run.base_value_level >= MUSIC_MID_BASE_VALUE_LEVEL:
		stage = 1
	if run.governance_level >= MUSIC_LATE_GOVERNANCE_LEVEL:
		stage = 2
	if stage > _music_stage:
		_music_stage = stage
		GameAudio.set_global(MUSIC_STAGE_PARAMETER, float(stage))


func _capture_at(delta: float, target: Vector2, active: bool) -> void:
	var radius: float = run.get_pipe_radius()
	var radius_squared: float = radius * radius
	var nearest: PrototypeSlime = null
	var nearest_distance: float = radius_squared
	if active and not _capture_targets.is_empty():
		var previous: PrototypeSlime = _capture_targets[0]
		if (
			is_instance_valid(previous)
			and previous.can_capture()
			and previous.get_capture_distance_squared(target) <= radius_squared
		):
			nearest = previous
	if active and nearest == null:
		for candidate: PrototypeSlime in _slimes:
			var distance: float = candidate.get_capture_distance_squared(target)
			if candidate.can_capture() and distance <= nearest_distance:
				nearest = candidate
				nearest_distance = distance
	# Only a former target needs its partial capture cancelled. Unrelated actors
	# must not be redrawn or copied into a new population array every tool tick.
	for previous: PrototypeSlime in _capture_targets:
		if is_instance_valid(previous) and previous != nearest:
			if previous.population_units == 1:
				previous.capture_progress = 0.0
			previous.release_capture(delta)
			_stop_giant_harvest()
	_capture_targets.clear()
	_slime_root.set_focus(nearest)
	_vacuum_audio.update(delta, nearest != null, active and _is_on_ground_mucus(target))
	_pipe.set_capture_engaged(nearest != null and nearest.species != PrototypeSlime.Species.DRILL)
	if nearest == null:
		_vacuum_audio.update_loading(null, 0.0)
		_vacuum_audio.update_peel(null, 0.0)
		_stop_giant_harvest()
		return
	_capture_targets.append(nearest)
	nearest.on_mucus = _is_on_ground_mucus(nearest.position)
	var capture_delta: float = delta
	var base_seconds: float = run.get_pipe_capture_seconds()
	var peel_seconds: float = nearest.get_capture_seconds(base_seconds)
	if nearest.is_anchored():
		capture_delta = maxf(0.0, delta - (1.0 - nearest.peel_progress) * peel_seconds)
	var was_anchored: bool = nearest.is_anchored()
	if not nearest.pull_off_mucus(delta, target, peel_seconds):
		_vacuum_audio.update_loading(null, 0.0)
		_vacuum_audio.update_peel(nearest, nearest.peel_progress)
		return
	if was_anchored:
		_vacuum_audio.peel_snapped()
	else:
		_vacuum_audio.update_peel(null, 0.0)
	var previous_capture_progress: float = nearest.capture_progress
	var completed: bool = nearest.apply_capture(capture_delta, base_seconds, target)
	_vacuum_audio.update_loading(null if completed else nearest, nearest.capture_progress)
	if nearest.population_units > 1:
		_update_giant_harvest(nearest, previous_capture_progress)
	if not completed:
		return
	_stop_giant_harvest()
	var before: int = run.candy
	var candy_combo: float = _combo_ladder_progress()
	_capture_combo_bonus = 0
	var accepted: bool = run.collect_slime(
		nearest.nest_id, nearest.reward, nearest.population_units, nearest.high_value
	)
	assert(accepted, "Collected monster must belong to its source population.")
	var candy_gained: int = run.candy - before
	if nearest.high_value:
		_monster_audio.golden_collected()
	if nearest.species == PrototypeSlime.Species.DRILL:
		_play_drill_treasure(candy_gained, nearest.get_capture_point())
	else:
		_pipe.show_capture_skin(nearest.species)
		_pipe.play_capture()
		_play_collection_reward(nearest.reward, nearest.get_capture_point(), nearest.body_color)
	_pipe.set_capture_engaged(false)
	_capture_targets.clear()
	_slimes.erase(nearest)
	nearest.hide()
	nearest.set_process(false)
	nearest.queue_free()
	if _monster_audio.is_ready():
		_monster_audio.monster_sucked(
			candy_combo,
			candy_gained - _capture_combo_bonus,
			nearest.population_units,
			nearest.species == PrototypeSlime.Species.DRILL
		)
	else:
		_collect_sound.pitch_scale = randf_range(0.92, 1.12)
		_collect_sound.play()


func _capture_seconds_for(slime: PrototypeSlime) -> float:
	var base_seconds: float = run.get_pipe_capture_seconds()
	var seconds: float = slime.get_capture_seconds(base_seconds)
	if slime.population_units > 1:
		seconds *= 1.0 - slime.capture_progress
	# Total time estimate; actual capture handles detachment and suction separately.
	slime.on_mucus = _is_on_ground_mucus(slime.position)
	if slime.is_anchored():
		return seconds + slime.get_capture_seconds(base_seconds) * (1.0 - slime.peel_progress)
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
	_overview_sample_elapsed = 0.0
	var positions: PackedVector2Array = PackedVector2Array()
	var kinds: PackedInt32Array = PackedInt32Array()
	var populations: PackedInt32Array = PackedInt32Array()
	for actor: PrototypeSlime in _slimes:
		if not actor.consumed and actor.species != PrototypeSlime.Species.DRILL:
			positions.append(actor.position)
			kinds.append(int(actor.species))
			populations.append(actor.population_units)
	_overview.update_ecology(
		positions,
		kinds,
		_view.is_overview() or _view.is_transitioning(),
		get_viewport_rect().size,
		populations
	)


func _on_combo_stage_completed(stage: int, bonus: int) -> void:
	_capture_combo_bonus += bonus
	# The sound marks the stage clear itself; the burst visual may still queue.
	_monster_audio.combo_stage_cleared(stage)
	_pipe.play_combo_burst(stage, bonus)


# Candy_Combo pitch: the whole combo ladder as 0-1, a quarter per stage. Read
# before the capture registers and counting it, so the capture that clears a
# stage sounds at that stage's top rather than after the reset.
func _combo_ladder_progress() -> float:
	if run.combo_level == 0:
		return 0.0
	var target: int = run.get_combo_target()
	var count: int = mini(run.combo_count + 1, target)
	var stages: float = float(run.settings.combo_stage_targets.size())
	return clampf((run.combo_stage + float(count) / target) / stages, 0.0, 1.0)


func _play_collection_reward(
	reward: int, source_position: Vector2, color: Color = Color("d7e8bb")
) -> void:
	if _view.is_overview():
		return
	var effect: CollectionEffect = collection_scene.instantiate() as CollectionEffect
	effect.color = color
	_effects.add_child(effect)
	effect.top_level = true
	effect.global_transform = Transform2D.IDENTITY
	var origin: Vector2 = _world.to_global(source_position)
	var destination: Vector2 = (
		_candy_label.get_global_transform_with_canvas() * (_candy_label.size * 0.5)
	)
	effect.play(origin, destination, reward)


func _update_giant_harvest(slime: PrototypeSlime, previous_progress: float) -> void:
	if _giant_harvest == null:
		_giant_harvest = giant_harvest_scene.instantiate() as GiantHarvestEffect
		_effects.add_child(_giant_harvest)
		_giant_harvest.top_level = true
		_giant_harvest.global_transform = Transform2D.IDENTITY
		_giant_harvest.begin_capture(previous_progress)
	_giant_harvest.color = slime.body_color
	var destination: Vector2 = (
		_candy_label.get_global_transform_with_canvas() * (_candy_label.size * 0.5)
	)
	_giant_harvest.update_capture(
		_world.to_global(slime.get_capture_point()), destination, slime.capture_progress
	)


func _play_drill_treasure(reward: int, source_position: Vector2) -> void:
	var effect: DrillTreasure = TREASURE_SCENE.instantiate() as DrillTreasure
	_effects.add_child(effect)
	effect.top_level = true
	effect.global_transform = Transform2D.IDENTITY
	var destination: Vector2 = (
		_candy_label.get_global_transform_with_canvas() * (_candy_label.size * 0.5)
	)
	effect.play(_world.to_global(source_position), destination, reward, run.get_base_value())


func _stop_giant_harvest() -> void:
	if _giant_harvest != null:
		_giant_harvest.finish()
		_giant_harvest = null


func _advance_monster_chatter(delta: float) -> void:
	_population_by_species.clear()
	for slime: PrototypeSlime in _slimes:
		if slime.can_capture():
			_population_by_species[slime.species] = (
				int(_population_by_species.get(slime.species, 0)) + 1
			)
	_monster_audio.update_chatter(delta, _population_by_species)


func _prepare_nest_sites() -> void:
	var measuring_view: NestView = nest_scene.instantiate() as NestView
	_nests.add_child(measuring_view)
	var maximum_width: float = (
		measuring_view.get_maximum_footprint_width() * _view.near_nest_scale.x
	)
	_nests.remove_child(measuring_view)
	measuring_view.free()
	_nest_site_distance = maxf(
		maximum_width + run.settings.nest_spacing_margin, run.settings.nest_min_distance
	)
	# Relief never exceeds its configured amplitude; use this lower radius bound for every heading.
	var minimum_radius: float = (
		_planet.radius * (PlanetSurface.SURFACE_RADIUS_RATIO - _planet.edge_relief_ratio)
		- _planet.nest_edge_inset
	)
	assert(_nest_site_distance < minimum_radius * 2.0, "The planet must fit two fully grown nests.")
	var minimum_angle: float = 2.0 * asin(_nest_site_distance / (minimum_radius * 2.0))
	var site_count: int = int(floor(TAU / minimum_angle))
	assert(site_count >= run.settings.initial_nests, "The planet must fit all opening nests.")
	var angle_step: float = TAU / float(site_count)
	_nest_site_jitter = (angle_step - minimum_angle) * 0.5
	_nest_site_angles.clear()
	for index: int in range(site_count):
		_nest_site_angles.append(-PI / 2.0 + (float(index) - 0.5) * angle_step)


func _on_nest_spawn_requested(species: NestState.Species) -> void:
	var points: Array[Vector2] = []
	var weights: Array[float] = []
	var total_weight: float = 0.0
	var angle_step: float = TAU / float(_nest_site_angles.size())
	for site_angle: float in _nest_site_angles:
		var angle: float = (
			site_angle + _site_random.randf_range(-_nest_site_jitter, _nest_site_jitter)
		)
		var point: Vector2 = _planet.get_nest_position(angle)
		var legal: bool = true
		var weight: float = 1.0
		for nest: NestState in run.nests:
			var distance: float = nest.position.distance_to(point)
			var site_offset: float = absf(wrapf(nest.position.angle() - site_angle, -PI, PI))
			if site_offset < angle_step * 0.5 or distance < _nest_site_distance:
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
	_present_discovered_nest(species, selected)


func _present_discovered_nest(_species: NestState.Species, nest_position: Vector2) -> void:
	run.resolve_nest_spawn(nest_position)


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
	view.surface = _planet
	_nests.add_child(view)
	view.position = nest.position
	view.setup(nest.nest_id)
	view.rotation = _planet.get_nest_rotation(nest.position.angle())
	view.configure_species(nest.species)
	view.flower_appeared.connect(_on_flower_appeared)
	view.production_released.connect(_on_flower_production_released)
	view.presentation_scale = _view.near_nest_scale
	view.update_state(nest.level, nest.is_tamed, run.settings.nest_upgrade_costs.size())
	_nest_views.append(view)
	if nest.is_discovering:
		view.begin_emergence()
	if not _opening_nests:
		_monster_audio.nest_appeared(nest.species)
	_refresh_hud()


func _on_flower_appeared(nest_id: int, species: int) -> void:
	run.record_flower(nest_id)
	flower_appeared.emit(nest_id, species)


func _on_nest_changed(nest: NestState) -> void:
	_nest_views[nest.nest_id - 1].update_state(
		nest.level, nest.is_tamed, run.settings.nest_upgrade_costs.size()
	)
	_regions[nest.nest_id - 1].stage = nest.level
	_queue_hud_refresh()


func _on_slime_requested(nest_id: int) -> void:
	var nest: NestState = run.get_nest(nest_id)
	_nest_views[nest_id - 1].pulse_spawn()
	_monster_audio.monster_spawned(nest.species)
	var actor_scene: PackedScene = (
		DRILL_SCENE if nest.species == NestState.Species.DRILL else slime_scene
	)
	var slime: PrototypeSlime = actor_scene.instantiate() as PrototypeSlime
	_slime_root.add_child(slime)
	slime.setup(nest_id, nest.position, _planet, _get_roaming_screen_half_angle())
	slime.presentation_scale = _view.near_slime_scale
	var direction_index: int = int(_spawn_directions.get(nest_id, 0))
	_spawn_directions[nest_id] = direction_index + 1
	var species: PrototypeSlime.Species = nest.species as PrototypeSlime.Species
	var valuable: bool = (
		run.valuable_level > 0
		and direction_index % run.settings.valuable_spawn_every == 0
	)
	var reward: int = run.get_capture_reward(nest.species, valuable)
	slime.configure_species(species, valuable, reward)
	var direction_angle: float = (
		float(direction_index) * 2.399963 + nest.position.angle() + randf_range(-0.14, 0.14)
	)
	slime.launch(Vector2.from_angle(direction_angle))
	_slimes.append(slime)


func _advance_giant_fusion(delta: float) -> void:
	if (
		not run.giant_unlocked
		or _view.is_overview()
		or _view.is_transitioning()
		or _view.is_dragging()
	):
		_giant_check_elapsed = 0.0
		return
	_giant_check_elapsed += delta
	if _giant_check_elapsed < run.settings.giant_check_interval:
		return
	_giant_check_elapsed = 0.0
	var viewport: Rect2 = get_viewport_rect()
	var offscreen_nests: Array[int] = []
	for nest_view: NestView in _nest_views:
		if not viewport.intersects(nest_view.get_hover_rect()):
			offscreen_nests.append(nest_view.nest_id)
	var candidates: Array[PrototypeSlime] = []
	for actor: PrototypeSlime in _slimes:
		if not actor.can_fuse() or not offscreen_nests.has(actor.nest_id):
			continue
		if viewport.intersects(actor.get_visual_rect()) or _capture_targets.has(actor):
			continue
		if (
			_net_phase in [NetPhase.CASTING, NetPhase.CLOSING]
			and actor.get_capture_point().distance_to(_net_anchor) <= run.get_net_radius()
		):
			continue
		candidates.append(actor)
	var activity_radius: float = (
		PrototypeSlime.get_activity_radius(_planet.radius, _get_roaming_screen_half_angle())
		* run.settings.giant_activity_radius_multiplier
	)
	for plan: GiantFusion.Plan in GiantFusion.plan_batches(run, candidates, activity_radius):
		_apply_giant_fusion(plan, viewport)


func _apply_giant_fusion(plan: GiantFusion.Plan, viewport: Rect2) -> void:
	var owner_nest: NestState = run.get_nest(plan.owner_id)
	var giant: PrototypeSlime = giant_slime_scene.instantiate() as PrototypeSlime
	_slime_root.add_child(giant)
	giant.setup(owner_nest.nest_id, owner_nest.position, _planet, _get_roaming_screen_half_angle())
	giant.presentation_scale = _view.near_slime_scale
	giant.configure_species(owner_nest.species as PrototypeSlime.Species, false, 0)
	giant.configure_fusion(
		plan.actors.size(), plan.value_units, run.get_base_value() * plan.value_units
	)
	var inward: Vector2 = -owner_nest.position.normalized()
	var tangent: Vector2 = inward.orthogonal()
	giant.restore_to_surface(
		owner_nest.position + inward * 35.0 + tangent * _site_random.randf_range(-28.0, 28.0)
	)
	# A large body can reach the screen while its nest is already outside it.
	# Defer that batch until it is safe to replace all of its participants.
	if viewport.intersects(giant.get_visual_rect()):
		giant.hide()
		giant.queue_free()
		return
	var accepted: bool = run.fuse_population(plan.contributions, plan.owner_id)
	assert(accepted, "A fusion plan must retain its exact source population until settlement.")
	for actor: PrototypeSlime in plan.actors:
		_slimes.erase(actor)
		actor.consumed = true
		actor.hide()
		actor.set_process(false)
		actor.queue_free()
	_slimes.append(giant)
	_refresh_overview()


func _refresh_monster_rewards() -> void:
	for slime: PrototypeSlime in _slimes:
		slime.reward = (
			run.get_base_value() * slime.fused_value_units
			if slime.population_units > 1
			else run.get_capture_reward(slime.species as NestState.Species, slime.high_value)
		)


func _on_automatic_income_received(nest_id: int, amount: int) -> void:
	if _view.is_overview():
		return
	var view: NestView = _nest_views[nest_id - 1]
	if get_viewport_rect().intersects(view.get_hover_rect()):
		view.pulse_automatic(amount)


func _on_flower_production_released(nest_id: int, amount: int) -> void:
	var view: NestView = _nest_views[nest_id - 1]
	if amount > 0 and get_viewport_rect().intersects(view.get_hover_rect()):
		_play_collection_reward(amount, view.get_production_point())


func _select_nest(nest_id: int) -> void:
	selected_nest_id = nest_id
	_refresh_hud()
	_layout.show_nest_details(_nest_views[nest_id - 1].get_hover_rect())


func _update_nest_hover(viewport_position: Vector2) -> void:
	if (
		_view.presentation_locked
		or _view.is_overview()
		or _view.is_transitioning()
		or _view.is_dragging()
		or _layout.is_technology_open()
	):
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
	_candy_label.text = str(run.candy)
	_passive_label.text = "%s DPS" % String.num(run.get_passive_income(), 1).trim_suffix(".0")
	_quick_pipe_button.button_pressed = _active_tool == ToolMode.PIPE
	_quick_net_button.button_pressed = _active_tool == ToolMode.NET
	_quick_pipe_button.disabled = false
	_quick_net_button.disabled = false
	_layout.refresh_progression(run)
	var nest: NestState = run.get_nest(selected_nest_id)
	if nest == null:
		_nest_title_label.text = "巢穴"
		_nest_level_label.text = "悬停巢穴查看升级"
		_nest_benefit_label.text = ""
		_nest_button.text = "驯化"
		_nest_button.disabled = true
		return
	_nest_title_label.text = ("%s巢穴 %02d" % [["史莱姆", "黏液怪", "钻头怪"][nest.species], nest.nest_id])
	if nest.is_tamed:
		_nest_level_label.text = "完全治理"
		_nest_benefit_label.text = "停止产怪 · 自动产糖"
		_nest_button.text = "自动产糖中"
		_nest_button.disabled = true
		return
	var stage_names: Array[String] = ["野生", "培育中", "强化培育"]
	_nest_level_label.text = stage_names[nest.level]
	var next_level: int = nest.level + 1
	if next_level == run.settings.nest_upgrade_costs.size():
		_nest_benefit_label.text = "下一阶段：完全治理\n停止产怪 · 自动产糖"
	else:
		_nest_benefit_label.text = "下一阶段：%s" % stage_names[next_level]
	var nest_cost: int = run.get_nest_upgrade_cost(selected_nest_id)
	var requirement: String = run.get_nest_upgrade_requirement(selected_nest_id)
	_nest_button.text = "升级 · %d 糖果" % nest_cost if requirement.is_empty() else requirement
	_nest_button.disabled = run.candy < nest_cost or not requirement.is_empty()


func _register_purchase_sounds() -> void:
	for index: int in range(2):
		var purchase: Button = _layout._tool_dock.upgrades[index]
		UiAudio.register_purchase(
			purchase,
			_is_technology_unaffordable.bind(DiskDemoLayout.BRANCH_IDS[index])
		)


# Technology purchases play Level Up; the original WAV remains the fallback.
func _play_level_up() -> void:
	if UiAudio.is_ready():
		UiAudio.level_up()
	else:
		_upgrade_sound.play()


func _is_technology_unaffordable(id: String) -> bool:
	var cost: int = run.get_technology_cost(id)
	return cost >= 0 and run.candy < cost and run.get_technology_requirement(id).is_empty()


func _is_tool_unaffordable() -> bool:
	return _is_technology_unaffordable("pipe" if _active_tool == ToolMode.PIPE else "net")


func _on_tool_upgrade() -> void:
	var upgraded: bool = run.upgrade_pipe() if _active_tool == ToolMode.PIPE else run.upgrade_net()
	if upgraded:
		_play_level_up()
		_show_status(
			(
				"吸取 %d 级" % (run.pipe_level + 1)
				if _active_tool == ToolMode.PIPE
				else "捕网 %d 级" % (run.net_level + 1)
			)
		)


func _on_nest_upgrade() -> void:
	if run.upgrade_nest(selected_nest_id):
		var nest: NestState = run.get_nest(selected_nest_id)
		var fmod_played: bool = _monster_audio.nest_leveled_up(nest.level)
		if nest.is_tamed:
			if not fmod_played:
				_tame_sound.play()
			_show_status("巢穴已自动产糖")
		else:
			if not fmod_played:
				_upgrade_sound.play()
			_show_status("巢穴 · %s" % ["野生", "培育中", "强化培育"][nest.level])


func _on_quick_upgrade(tool: int) -> void:
	_on_technology_upgrade("pipe" if tool == 0 else run.get_net_quick_upgrade_id())


func _on_technology_upgrade(technology_id: String) -> void:
	var unlocking_net: bool = technology_id in ["net", "net_unlock"] and not run.net_unlocked
	if run.purchase_technology(technology_id):
		_refresh_hud()
		_play_level_up()
		if unlocking_net:
			_show_status("捕网已解锁")
		elif technology_id == "pipe":
			_show_status("吸取 %d 级" % (run.pipe_level + 1))
		elif technology_id in ["net", "net_capacity"]:
			_show_status("捕网 %d 级" % (run.net_level + 1))
		elif technology_id == "net_size":
			_show_status("捕网大小 %d 级" % (run.net_size_level + 1))
		else:
			_show_status("科技升级完成")


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
	_completion_tween = create_tween()
	_completion_tween.tween_interval(1.5)
	_completion_tween.tween_callback(_show_completion)


func _show_completion() -> void:
	_layout.close_panels()
	if not _planet_audio.monsters_cleared():
		_finish_sound.play()
	_completion_title.text = "星球清扫完成"
	_completion_detail.text = "场上所有怪物已清除。"
	_completion.show()
	%ReplayButton.grab_focus()


func _close_victory() -> void:
	_completion.hide()
