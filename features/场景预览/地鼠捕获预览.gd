extends "res://features/场景预览/游玩预览.gd"

@export_range(0.2, 3.0, 0.1) var retry_seconds: float = 0.8

var _preview_actor: DrillMonster
var _preview_valuable: bool = false
var _retry_remaining: float = 0.0
var _caught_count: int = 0

@onready var _preview_result: Label = $PreviewControls/Controls/Result


func _ready() -> void:
	super._ready()
	_layout.hide()
	_layout.set_process(false)
	_layout.set_process_unhandled_key_input(false)
	_nests.hide()
	_net.hide()
	_view.zoom_steps(1.0, false)
	_view.focus_surface(-PI / 2.0, false)
	_set_preview_kind(false)


func _process(delta: float) -> void:
	var pointer: Vector2 = get_viewport().get_mouse_position()
	var holding: bool = update_pointer_release_state()
	_drive_drill_capture(delta, pointer, holding)
	_slime_root.set_focus(_hovered_drill)
	_drive_tool(delta, _world.to_local(get_global_mouse_position()), holding)
	_net.hide()
	if is_instance_valid(_preview_actor) and not _preview_actor.consumed:
		if _preview_actor.phase != DrillMonster.Phase.TRAVEL:
			return
		_remove_preview_actor()
	if _retry_remaining <= 0.0:
		_retry_remaining = retry_seconds
	_retry_remaining -= delta
	if _retry_remaining <= 0.0:
		_spawn_preview_actor()


func _set_preview_kind(valuable: bool) -> void:
	_preview_valuable = valuable
	$PreviewControls/Controls/Buttons/Ordinary.button_pressed = not valuable
	$PreviewControls/Controls/Buttons/Valuable.button_pressed = valuable
	_restart_preview_actor()


func _restart_preview_actor() -> void:
	_remove_preview_actor()
	_spawn_preview_actor()


func _remove_preview_actor() -> void:
	_clear_drill_hover()
	if is_instance_valid(_preview_actor):
		_slimes.erase(_preview_actor)
		_preview_actor.hide()
		_preview_actor.queue_free()
	_preview_actor = null
	run.get_nest(1).alive_slimes = 0


func _spawn_preview_actor() -> void:
	_retry_remaining = 0.0
	var nest: NestState = run.get_nest(1)
	nest.species = NestState.Species.DRILL
	nest.alive_slimes = 1
	_preview_actor = drill_scene.instantiate() as DrillMonster
	_slime_root.add_child(_preview_actor)
	var bounds: Vector2 = _planet.get_activity_radius_bounds(-PI / 2.0)
	var home: Vector2 = Vector2.UP * lerpf(bounds.x, bounds.y, 0.7)
	_preview_actor.setup(1, home, _planet, _get_roaming_screen_half_angle())
	_preview_actor.presentation_scale = _view.near_slime_scale
	_preview_actor.configure_species(PrototypeSlime.Species.DRILL, _preview_valuable, 0)
	_preview_actor._enter_phase(DrillMonster.Phase.EMERGE, 1.0, &"跳出")
	_slimes.append(_preview_actor)


func _finish_capture(actor: PrototypeSlime) -> void:
	super._finish_capture(actor)
	_caught_count += 1
	_preview_result.text = "捕获 %d  ·  糖果 %d" % [_caught_count, run.candy]


func _sync_view_projection() -> void:
	super._sync_view_projection()
	_nests.hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_R:
			_restart_preview_actor()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			super._input(event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			super._unhandled_input(event)
