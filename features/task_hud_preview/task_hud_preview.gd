extends Node

const Play = preload("res://features/场景预览/游玩预览.gd")

@export_range(0, 100000, 50) var preview_candy: int = 2850

@onready var _game: Play = $Game
@onready var _task: Control = $Game/HUD/Interface/TaskHud
@onready var _progress: ProgressBar = $Game/HUD/Interface/TaskHud/Progress
@onready var _amount: Label = $Game/HUD/Interface/TaskHud/Amount


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game.run.governance_level = 1
	_game.run.candy = preview_candy
	_game.run.economy_changed.emit()
	_game.run.advance(18.0)
	_game.run.economy_changed.connect(_update_preview)
	_update_preview()
	if "--capture-task-hud" in OS.get_cmdline_user_args():
		_capture_preview.call_deferred()


func _process(_delta: float) -> void:
	_task.visible = not _game._layout.is_technology_open() and not _game._layout.game_menu.is_open()


func _update_preview() -> void:
	var cost: int = _game.run.settings.governance_upgrade_costs[1]
	_progress.max_value = cost
	_progress.value = _game.run.candy
	_amount.text = "%s / %s" % [_group_digits(_game.run.candy), _group_digits(cost)]


func _group_digits(value: int) -> String:
	var digits: String = str(value)
	var result: String = ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits[index]
	return result


func _capture_preview() -> void:
	var output: String = "res://artifacts/task_hud_20261015"
	DirAccess.make_dir_recursive_absolute(output)
	get_window().mode = Window.MODE_WINDOWED
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	await get_tree().create_timer(2.0).timeout
	_game.set_process(false)
	_game.set_process_input(false)
	_game._clear_nest_selection()
	_game._layout.close_panels()
	_game.run.candy = preview_candy
	_game.run.economy_changed.emit()
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var filename: String = "task_hud_%dx%d.png" % [resolution.x, resolution.y]
		var result: Error = get_viewport().get_texture().get_image().save_png(
			output.path_join(filename)
		)
		assert(result == OK, "Task HUD capture must be saved")
		print("TASK_HUD_CAPTURE ", filename, " rect=", _task.get_global_rect())
	get_tree().quit()
