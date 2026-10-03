extends Node2D

const PipeCursor = preload("res://scripts/pipe_cursor.gd")

enum ToolMode { PIPE, NET }
enum NetPhase { IDLE, CASTING, CLOSING, RESULT }

@export var slime_scene: PackedScene
@export var nest_scene: PackedScene
@export var collection_scene: PackedScene
@export_range(0.0, 120.0, 1.0) var capture_surface_inner_offset: float = 65.0
@export_range(0.0, 100.0, 1.0) var capture_surface_outer_offset: float = 35.0
@export_range(1, 8, 1) var attraction_visual_limit: int = 4
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
var _spawn_directions: Dictionary = {}
var _restore_tween: Tween
var _status_tween: Tween

@onready var run: PrototypeRun = $Run
@onready var _world: Node2D = $World
@onready var _planet: PlanetSurface = %PlanetSurface
@onready var _nests: Node2D = %Nests
@onready var _slime_root: Node2D = %Slimes
@onready var _effects: Node2D = %Effects
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
	run.economy_changed.connect(_refresh_hud)
	run.collection_changed.connect(_refresh_hud)
	run.net_cooldown_changed.connect(_refresh_hud)
	run.nest_added.connect(_on_nest_added)
	run.nest_changed.connect(_on_nest_changed)
	run.slime_requested.connect(_on_slime_requested)
	run.goal_completed.connect(_on_goal_completed)
	_tool_button.pressed.connect(_on_tool_upgrade)
	_pipe_button.pressed.connect(_select_tool.bind(ToolMode.PIPE))
	_net_button.pressed.connect(_select_tool.bind(ToolMode.NET))
	_nest_button.pressed.connect(_on_nest_upgrade)
	%RestartButton.pressed.connect(restart_run)
	%ReplayButton.pressed.connect(restart_run)
	%CloseVictoryButton.pressed.connect(_close_victory)
	RenderingServer.set_default_clear_color(Color("e9e8df"))
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()
	restart_run()


func _process(delta: float) -> void:
	if run.is_complete:
		_pipe.visible = false
		_net.visible = false
		return
	run.advance(delta)
	var world_position: Vector2 = _world.to_local(get_global_mouse_position())
	_drive_tool(delta, world_position, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))


func _drive_tool(delta: float, pointer: Vector2, holding: bool) -> void:
	if run.is_complete:
		return
	var just_pressed: bool = holding and not _was_holding
	_tool_pointer = pointer
	_pipe.visible = _active_tool == ToolMode.PIPE
	if _active_tool == ToolMode.PIPE:
		var tool_radius: float = run.get_pipe_radius()
		var capturing: bool = holding and _can_collect(pointer, tool_radius)
		_pipe.radius = tool_radius
		_pipe.attraction_radius = run.get_pipe_attraction_radius()
		_capture_at(delta, pointer, capturing)
		if not holding:
			_settle_collection()
		_pipe.set_tool_state(pointer, pointer, capturing, run.pending_slime_count)
	else:
		_capture_at(delta, pointer, false)
		if (
			just_pressed
			and _net_phase == NetPhase.IDLE
			and _can_collect(pointer, run.get_net_radius())
		):
			_start_net(pointer)
	_advance_net(delta)
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
	for index: int in range(caught_count):
		var slime: PrototypeSlime = candidates[index]
		source_ids.append(slime.nest_id)
		_slimes.erase(slime)
		_capture_targets.erase(slime)
		slime.consumed = true
		slime.hide()
		slime.set_process(false)
		slime.queue_free()
	var reward: int = run.collect_net_batch(source_ids)
	assert(
		reward == caught_count * run.settings.slime_reward,
		"Net actors must match their source stock."
	)
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
	return (
		not _layout.is_over_ui(_world.get_global_transform_with_canvas() * pointer)
		and pointer.length() + radius >= _planet.radius - capture_surface_inner_offset
		and pointer.length() - radius <= _planet.radius + capture_surface_outer_offset
	)


func _select_tool(tool: ToolMode) -> void:
	if run.is_complete:
		return
	_settle_collection()
	_capture_targets.clear()
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


func _apply_layout() -> void:
	var play_rect: Rect2 = _layout.apply_layout(get_viewport_rect().size)
	_world.position = play_rect.get_center()
	_world.scale = _layout.scale


func restart_run() -> void:
	if _restore_tween != null:
		_restore_tween.kill()
	if _status_tween != null:
		_status_tween.kill()
	for container: Node2D in [_nests, _slime_root, _effects]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_nest_views.clear()
	_slimes.clear()
	_capture_targets.clear()
	_was_holding = false
	_net_phase = NetPhase.IDLE
	_net_elapsed = 0.0
	_net_caught_count = 0
	_active_tool = ToolMode.PIPE
	_net.hide()
	_pipe.show()
	_spawn_directions.clear()
	selected_nest_id = -1
	_completion.hide()
	_planet.set_restored(0.0)
	_status_label.text = ""
	_status_label.modulate.a = 1.0
	var spawn_positions: Array[Vector2] = []
	var order: Array[int] = []
	if run.settings.nest_budget == 5:
		order.assign([0, 2, 4, 1, 3])
	for index: int in range(run.settings.nest_budget):
		var slot: int = order[index] if not order.is_empty() else index
		var angle: float = -PI / 2.0 + float(slot) * TAU / float(run.settings.nest_budget)
		spawn_positions.append(Vector2.from_angle(angle) * _planet.radius * 0.9375)
	run.start_run(spawn_positions)
	_tool_pointer = _world.to_local(get_global_mouse_position())
	_pipe.position = _tool_pointer
	_refresh_hud()


func _capture_at(delta: float, target: Vector2, active: bool) -> void:
	if run.is_complete:
		return
	var radius: float = run.get_pipe_radius()
	var radius_squared: float = radius * radius
	_capture_targets.clear()
	var nearest: PrototypeSlime = null
	var nearest_distance: float = radius_squared
	if active:
		for candidate: PrototypeSlime in _slimes:
			var distance: float = candidate.get_capture_point().distance_squared_to(target)
			if not candidate.consumed and distance <= nearest_distance:
				nearest = candidate
				nearest_distance = distance
	if nearest != null:
		_capture_targets.append(nearest)
	if active:
		_show_pipe_attraction(delta, target, nearest)
	var remaining: Array[PrototypeSlime] = []
	var collected: bool = false
	for slime: PrototypeSlime in _slimes:
		if slime == nearest:
			if slime.apply_capture(delta, run.get_pipe_capture_seconds(), target):
				var accepted: bool = run.collect_slime(slime.nest_id)
				assert(accepted, "Collected monster must belong to its source population.")
				collected = true
				_capture_targets.erase(slime)
				slime.hide()
				slime.set_process(false)
				slime.queue_free()
				continue
		else:
			slime.capture_progress = 0.0
			slime.release_capture(delta)
		remaining.append(slime)
	_slimes = remaining
	if collected:
		_collect_sound.pitch_scale = randf_range(0.92, 1.12)
		_collect_sound.play()


func _show_pipe_attraction(delta: float, target: Vector2, processing: PrototypeSlime) -> void:
	var nearby: Array[PrototypeSlime] = []
	var radius: float = run.get_pipe_attraction_radius()
	for slime: PrototypeSlime in _slimes:
		if slime != processing and slime.get_capture_point().distance_to(target) <= radius:
			nearby.append(slime)
	nearby.sort_custom(
		func(first: PrototypeSlime, second: PrototypeSlime) -> bool: return (
			first.get_capture_point().distance_squared_to(target)
			< second.get_capture_point().distance_squared_to(target)
		)
	)
	for index: int in range(mini(nearby.size(), attraction_visual_limit)):
		var slime: PrototypeSlime = nearby[index]
		var strength: float = 1.0 - slime.get_capture_point().distance_to(target) / radius
		slime.apply_attraction(delta, target, maxf(0.2, strength))


func _settle_collection() -> void:
	var reward: int = run.settle_collection()
	if reward > 0:
		_play_collection_reward(reward, _tool_pointer)


func _play_collection_reward(reward: int, source_position: Vector2) -> void:
	var effect: CollectionEffect = collection_scene.instantiate() as CollectionEffect
	_effects.add_child(effect)
	var feedback_position: Vector2 = source_position.limit_length(_planet.radius)
	var origin: Vector2 = _world.to_global(feedback_position)
	var destination: Vector2 = (
		_candy_label.get_global_transform_with_canvas() * (_candy_label.size * 0.5)
	)
	effect.play(origin, destination, reward)


func _on_nest_added(nest: NestState) -> void:
	var view: NestView = nest_scene.instantiate() as NestView
	_nests.add_child(view)
	view.position = nest.position
	view.setup(nest.nest_id)
	view.update_state(nest.level, nest.is_tamed, run.settings.nest_upgrade_costs.size())
	view.selected.connect(_select_nest)
	_nest_views.append(view)
	_refresh_hud()


func _on_nest_changed(nest: NestState) -> void:
	_nest_views[nest.nest_id - 1].update_state(
		nest.level, nest.is_tamed, run.settings.nest_upgrade_costs.size()
	)
	if nest.is_tamed:
		for slime: PrototypeSlime in _slimes:
			if slime.nest_id == nest.nest_id:
				slime.release_from_nest()
	_refresh_hud()


func _on_slime_requested(nest_id: int) -> void:
	var nest: NestState = run.get_nest(nest_id)
	var slime: PrototypeSlime = slime_scene.instantiate() as PrototypeSlime
	_slime_root.add_child(slime)
	slime.setup(nest_id, nest.position, _planet.radius)
	var direction_index: int = int(_spawn_directions.get(nest_id, 0))
	_spawn_directions[nest_id] = direction_index + 1
	var direction_angle: float = (
		float(direction_index) * 2.399963 + nest.position.angle() + randf_range(-0.14, 0.14)
	)
	slime.launch(Vector2.from_angle(direction_angle))
	_slimes.append(slime)


func _select_nest(nest_id: int) -> void:
	selected_nest_id = nest_id
	for view: NestView in _nest_views:
		view.set_selected(view.nest_id == nest_id)
	_refresh_hud()


func _refresh_hud() -> void:
	_candy_label.text = "%d 糖果" % run.candy
	_passive_label.text = "自动 +%.1f / 秒" % run.get_passive_income()
	_progress_label.text = "驯化 %d / %d" % [run.completed_nests, run.settings.nest_budget]
	_progress_bar.max_value = run.settings.nest_budget
	_progress_bar.value = run.completed_nests
	_tool_level_label.text = (
		"Lv. %d" % ((run.pipe_level if _active_tool == ToolMode.PIPE else run.net_level) + 1)
	)
	_pipe_button.button_pressed = _active_tool == ToolMode.PIPE
	_net_button.button_pressed = _active_tool == ToolMode.NET
	_pipe_button.disabled = run.is_complete
	_net_button.disabled = run.is_complete
	if _active_tool == ToolMode.PIPE:
		_tool_stats_label.text = (
			"处理 %.2f 秒 / 只\n本趟 +%d 糖果" % [run.get_pipe_capture_seconds(), run.pending_candy]
		)
	else:
		var cooldown_text: String = (
			"可施放" if run.can_cast_net() else "冷却 %.1f 秒" % run.net_cooldown_remaining
		)
		_tool_stats_label.text = "容量 %d 只\n%s" % [run.get_net_capacity(), cooldown_text]
	var tool_cost: int = (
		run.get_pipe_upgrade_cost() if _active_tool == ToolMode.PIPE else run.get_net_upgrade_cost()
	)
	_tool_button.disabled = tool_cost < 0 or run.candy < tool_cost or run.is_complete
	_tool_button.text = (
		"已满级"
		if tool_cost < 0
		else "%s升级 · %d 糖果" % ["速度" if _active_tool == ToolMode.PIPE else "容量", tool_cost]
	)
	if tool_cost >= 0:
		if _active_tool == ToolMode.PIPE:
			_tool_button.tooltip_text = (
				"每只处理 %.2f → %.2f 秒"
				% [
					run.get_pipe_capture_seconds(),
					run.settings.pipe_capture_seconds[run.pipe_level + 1]
				]
			)
		else:
			_tool_button.tooltip_text = (
				"一网容量 %d → %d 只"
				% [run.get_net_capacity(), run.settings.net_capacities[run.net_level + 1]]
			)
	else:
		_tool_button.tooltip_text = ""
	var nest: NestState = run.get_nest(selected_nest_id)
	if nest == null:
		_nest_title_label.text = "巢穴"
		_nest_level_label.text = "点选一个巢穴"
		_nest_benefit_label.text = ""
		_nest_button.text = "驯化"
		_nest_button.disabled = true
		return
	_nest_title_label.text = "史莱姆巢穴 %d" % nest.nest_id
	if nest.is_tamed:
		_nest_level_label.text = "已驯化"
		_nest_benefit_label.text = "自动 +%.1f 糖果 / 秒" % run.settings.passive_income_per_second
		_nest_button.text = "持续产糖中"
		_nest_button.disabled = true
		return
	_nest_level_label.text = (
		"Lv. %d · 小怪 %d / %d"
		% [nest.level + 1, nest.alive_slimes, run.get_nest_population_limit(nest.nest_id)]
	)
	var next_level: int = nest.level + 1
	if next_level == run.settings.nest_upgrade_costs.size():
		_nest_benefit_label.text = (
			"下一步：停止刷怪\n自动 +%.1f 糖果 / 秒" % run.settings.passive_income_per_second
		)
	else:
		_nest_benefit_label.text = (
			"下一步：刷怪 %.1f → %.1f / 秒\n上限 %d → %d 只"
			% [
				snappedf(1.0 / run.settings.spawn_intervals[nest.level], 0.1),
				snappedf(1.0 / run.settings.spawn_intervals[next_level], 0.1),
				run.get_nest_population_limit(nest.nest_id),
				run.settings.nest_population_limits[next_level]
			]
		)
	var nest_cost: int = run.get_nest_upgrade_cost(selected_nest_id)
	_nest_button.text = "驯化 · %d 糖果" % nest_cost
	_nest_button.disabled = run.candy < nest_cost or run.is_complete


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
			_show_status("巢穴开始自动产糖")
		else:
			_upgrade_sound.play()
			_show_status("更多史莱姆涌出来了")


func _show_status(message: String) -> void:
	if _status_tween != null:
		_status_tween.kill()
	_status_label.text = message
	_status_label.modulate.a = 1.0
	_status_tween = create_tween()
	_status_tween.tween_interval(1.7)
	_status_tween.tween_property(_status_label, "modulate:a", 0.0, 0.5)


func _on_goal_completed() -> void:
	for slime: PrototypeSlime in _slimes:
		slime.set_process(false)
	_pipe.hide()
	_net.hide()
	_refresh_hud()
	_restore_tween = create_tween()
	_restore_tween.tween_method(_planet.set_restored, 0.0, 1.0, 1.1)
	_restore_tween.tween_interval(0.4)
	_restore_tween.tween_callback(_show_completion)


func _show_completion() -> void:
	_finish_sound.play()
	_completion_title.text = "星球恢复了一种颜色"
	_completion_detail.text = "%d 个史莱姆巢穴，全部驯化完成。" % run.settings.nest_budget
	_completion.show()
	%ReplayButton.grab_focus()


func _close_victory() -> void:
	_completion.hide()
