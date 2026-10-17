extends Node

signal ready_to_play

const Store = preload("res://scripts/game_save.gd")
const Play = preload("res://features/场景预览/游玩预览.gd")
const Story = preload("res://features/tutorial_intro/story_flow.gd")
const Restoration = preload("res://features/tutorial_intro/story_restoration.gd")
const Discovery = preload("res://scripts/nest_discovery_presentation.gd")

@export var game: Play
@export var story: Story
@export var restoration: Restoration
@export var discovery: Discovery
@export_range(5.0, 120.0, 1.0) var interval_seconds: float = 25.0

var active: bool = false
var _save_queued: bool = false
var _timer: Timer


func _ready() -> void:
	assert(game != null and story != null and restoration != null and discovery != null)
	_begin.call_deferred()


func _begin() -> void:
	if not Store.session_requested:
		return
	Store.session_requested = false
	var saved: Dictionary = Store.pending_snapshot
	Store.pending_snapshot = {}
	if not saved.is_empty():
		if not game.accepts_gameplay_save(saved.world):
			game._show_status("存档与当前版本不兼容，已保留原存档。")
			return
		story.cancel()
		discovery.cancel()
		restoration.reset()
		game.restore_gameplay_save(saved.world)
		restoration.restore_save(saved.restoration)
		story.restore_save(saved.story)
		discovery.restore_save(saved.discovery)
		if game.run.is_complete:
			if Story.Kind.RESCUE in story.seen:
				game._view.zoom_steps(-1.0, false)
				game._victory.play_meteors()
			elif story.kind != Story.Kind.RESCUE:
				game._on_goal_completed()
		else:
			game.run._check_completion()
	active = true
	game._layout.game_menu.progress_is_saved = true
	game._layout.save_before_menu = save_now
	GameLifecycle.save_before_quit = save_now
	game.run.progress_committed.connect(request_save)
	game.run.nest_added.connect(_nest_added)
	game.run.goal_completed.connect(request_save)
	game.run_restarted.connect(_new_run)
	story.story_finished.connect(_story_finished)
	restoration.presentation_finished.connect(request_save)
	restoration.progress_committed.connect(request_save)
	discovery.presentation_finished.connect(request_save)
	_timer = Timer.new()
	_timer.wait_time = interval_seconds
	_timer.ignore_time_scale = true
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.timeout.connect(save_now)
	add_child(_timer)
	_timer.start()
	if saved.is_empty():
		save_now()
	ready_to_play.emit()


func request_save() -> void:
	if not active or _save_queued:
		return
	_save_queued = true
	_flush.call_deferred()


func _flush() -> void:
	_save_queued = false
	if is_inside_tree():
		save_now()


func _nest_added(_nest: NestState) -> void:
	request_save()


func _story_finished(_kind: Story.Kind) -> void:
	request_save()


func _new_run() -> void:
	if not save_now(true):
		return
	# Re-enter through the movie after replacing both the old slot and its backup.
	# The next gameplay scene must start fresh and enable autosave again.
	Store.session_requested = true
	Store.pending_snapshot = {}
	var error: Error = get_tree().change_scene_to_file("res://scenes/开头动画/开头动画.tscn")
	if error != OK:
		Store.session_requested = false
		game._show_status("无法播放开头动画，请重新开始后重试。")
		push_error("Could not restart opening: %s" % error_string(error))


func save_now(new_run: bool = false) -> bool:
	if not active:
		return true
	var snapshot: Dictionary = {
		"world": game.capture_gameplay_save(),
		"story": story.capture_save(),
		"restoration": restoration.capture_save(),
		"discovery": discovery.capture_save(),
	}
	var error: Error = Store.write(snapshot, new_run)
	if error != OK:
		game._show_status("保存失败，请检查磁盘空间后重试。")
		push_warning("Could not save game: %s" % error_string(error))
		return false
	return true


func _exit_tree() -> void:
	if active:
		GameLifecycle.save_before_quit = Callable()
