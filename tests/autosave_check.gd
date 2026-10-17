extends Node

const Store = preload("res://scripts/game_save.gd")
const Game = preload("res://features/tutorial_intro/story_game.gd")
const Flow = preload("res://features/tutorial_intro/story_flow.gd")
const Session = preload("res://scripts/save_session.gd")
const Menu = preload("res://scenes/主菜单/主菜单.gd")
const GAME: PackedScene = preload("res://scenes/game.tscn")
const MENU: PackedScene = preload("res://scenes/主菜单/主菜单.tscn")

var _game: Game
var _session: Session
var _failures: int = 0
var _captures: bool = false


func _ready() -> void:
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error("AUTOSAVE: " + label)
	else:
		print("PASS: " + label)


func _run() -> void:
	Store.save_path = "res://artifacts/autosave_check/slot.save"
	if "--notes" in OS.get_cmdline_user_args():
		Store.save_path = "res://artifacts/mission_note_20261017/slot.save"
	_captures = "--capture" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(Store.save_path.get_base_dir())
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(Store.save_path + suffix):
			DirAccess.remove_absolute(Store.save_path + suffix)
	get_tree().create_timer(180.0, true, false, true).timeout.connect(_timeout)
	if "--notes" in OS.get_cmdline_user_args():
		await _notes()
		return
	if "--boundaries" in OS.get_cmdline_user_args():
		await _boundaries()
		return
	var menu: Menu = MENU.instantiate() as Menu
	get_tree().root.add_child(menu)
	_check(menu._start_button.text == "开始游戏", "empty slot starts a new game")
	_check(menu._entry_scene_path() == Menu.OPENING_SCENE, "new game uses opening")
	if _captures:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"res://artifacts/autosave_check/new_menu.png"
		)
	menu.queue_free()
	await get_tree().process_frame
	await _create_game({})
	_check(_session.active, "formal menu session enables autosave")
	_check(not Store.load_latest().is_empty(), "initial progress saved")
	_game.story.cancel()
	_game.story.seen.assign([Flow.Kind.OPENING, Flow.Kind.CULTIVATION, Flow.Kind.AUTOMATION])
	_game.run.candy = 12345
	_check(_game.run.purchase_technology("pipe"), "buy pipe")
	await get_tree().process_frame
	_check(
		Store.load_latest().world.run.pipe_level == 1, "purchase saves without waiting for timer"
	)
	_check(Store.load_latest().world.run.candy == _game.run.candy, "deduction saved once")
	_game.run.net_unlocked = true
	_game.run.governance_level = 3
	_game.run.valuable_level = 1
	_game.run.giant_unlocked = true
	_game.run.combo_level = 1
	_game.run.combo_count = 2
	_game.run.combo_remaining = 1.4
	_game.run.net_cooldown_remaining = 2.3
	_game.run._pending_nest_species = NestState.Species.MUCUS
	_game.run.resolve_nest_spawn(_game._planet.get_nest_position(0.7))
	_game.run._pending_nest_species = NestState.Species.DRILL
	_game.run.resolve_nest_spawn(_game._planet.get_nest_position(2.0))
	for nest: NestState in _game.run.nests:
		nest.alive_slimes += 1
		_game._on_slime_requested(nest.nest_id)
	# Give the first actor a stable giant identity and population accounting.
	var giant: PrototypeSlime = _game._slimes[0]
	giant.configure_fusion(5, 7, _game.run.get_base_value() * 7)
	_game.run.get_nest(giant.nest_id).alive_slimes += 4
	_game._view.restore_save(1.25, 1.0)
	_game._select_tool(_game.ToolMode.NET)
	_game.run.nests[0].income_remainder = 0.75
	# Freeze the world so snapshot comparisons are not affected by a simulation frame.
	get_tree().paused = true
	_check(_session.save_now(), "mixed world saved")
	var saved: Dictionary = Store.load_latest()
	var candy: int = _game.run.candy
	var actors: int = _game._slimes.size()
	await _dispose_game()
	await _create_game(saved)
	get_tree().paused = true
	_check(_game.run.candy == candy, "candy restored")
	_check(
		_game.run.nests.size() == 4 and _game._slimes.size() == actors,
		"nests and live actors restored"
	)
	_check(
		_game._slimes[0].population_units == 5 and _game._slimes[0].fused_value_units == 7,
		"giant value restored"
	)
	_check(
		_game._slimes[-1] is Game.DrillMonster and _game._slimes[-1].high_value,
		"valuable drill restored"
	)
	_check(
		_game._active_tool == _game.ToolMode.NET and is_equal_approx(_game._world.rotation, 1.25),
		"tool and camera restored"
	)
	_check(is_equal_approx(_game.run.combo_remaining, 1.4), "combo time frozen offline")
	_check(is_equal_approx(_game.run.net_cooldown_remaining, 2.3), "cooldown frozen offline")
	_check(_game.story.kind == Flow.Kind.NONE, "completed opening is not replayed")
	_game.run.candy += 7
	_session._timer.start(0.1)
	await get_tree().create_timer(0.2, true, false, true).timeout
	_check(Store.load_latest().world.run.candy == candy + 7, "periodic timer saves while paused")
	_session._timer.stop()
	# A paid flower whose animation has not finished must survive with its color queued.
	_game.run.nests[0].level = 3
	_game.run.nests[0].is_tamed = true
	_game.run.completed_nests = 1
	_check(_session.save_now(), "save during unfinished flower upgrade")
	saved = Store.load_latest()
	await _dispose_game()
	await _create_game(saved)
	get_tree().paused = true
	_check(
		_game.run.nests[0].is_tamed and _game._nest_views[0]._tamed,
		"flower restored without repurchase"
	)
	_check(NestState.Species.SLIME in _game._restoration.unlocked_species, "earned color restored")
	_check(
		_game.run.unlocked_colors.has(NestState.Species.SLIME), "flower completion fact retained"
	)
	# Two writes establish a valid backup, then simulate interrupted/corrupted primary.
	_check(_session.save_now(), "backup checkpoint")
	var backup_candy: int = _game.run.candy
	_game.run.candy += 11
	_check(_session.save_now(), "second checkpoint")
	var corrupt: FileAccess = FileAccess.open(Store.save_path, FileAccess.WRITE)
	corrupt.store_string("broken")
	corrupt.close()
	_check(
		Store.load_latest().world.run.candy == backup_candy,
		"corrupt primary falls back to valid backup"
	)
	_check(_session.save_now(), "save repairs corrupted primary")
	# Leaving through the real menu callback saves before the scene disappears.
	_game.run.candy = 54321
	_game._layout._return_to_menu()
	for index: int in range(10):
		await get_tree().process_frame
		if get_tree().current_scene is Menu:
			break
	menu = get_tree().current_scene as Menu
	_check(menu != null and menu._start_button.text == "继续游戏", "returning to menu shows continue")
	_check(Store.load_latest().world.run.candy == 54321, "menu exit saves final state")
	_check(menu._entry_scene_path() == Menu.DEFAULT_START_SCENE, "continue bypasses opening movie")
	if _captures:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"res://artifacts/autosave_check/continue_menu.png"
		)
	# Exercise the real continue button and asynchronous loading path.
	menu._start()
	for index: int in range(1800):
		await get_tree().process_frame
		if get_tree().current_scene is Game:
			break
	_game = get_tree().current_scene as Game
	await get_tree().process_frame
	_session = _game.get_node("SaveSession") as Session
	_check(_game.run.candy >= 54321 and _session.active, "continue button restores saved session")
	_game.restart_run()
	await get_tree().process_frame
	_check(Store.load_latest().world.run.candy == 0, "restart replaces old progress")
	_check(
		Store._read(Store.save_path + ".bak").world.run.candy == 0,
		"restart also replaces old backup"
	)
	_game.run.candy = 9876
	GameLifecycle.save_before_quit = func() -> bool:
		var success: bool = _session.save_now()
		_check(Store.load_latest().world.run.candy == 9876, "window quit saves final progress")
		print("AUTOSAVE CHECK: %d failures" % _failures)
		return success
	GameLifecycle.request_quit()


func _create_game(snapshot: Dictionary) -> void:
	Store.session_requested = true
	Store.pending_snapshot = snapshot
	_game = GAME.instantiate() as Game
	if not snapshot.is_empty() and "--notes" not in OS.get_cmdline_user_args():
		(_game.get_node("SaveSession") as Session).ready_to_play.connect(
			func() -> void: get_tree().paused = true
		)
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	await get_tree().process_frame
	_session = _game.get_node("SaveSession") as Session


func _dispose_game() -> void:
	_game.story.cancel()
	get_tree().current_scene = null
	_game.queue_free()
	await get_tree().process_frame


func _timeout() -> void:
	push_error("AUTOSAVE CHECK TIMEOUT")
	get_tree().paused = false
	get_tree().quit(1)


func _reload_checkpoint() -> void:
	_check(_session.save_now(), "boundary checkpoint written")
	var snapshot: Dictionary = Store.load_latest()
	await _dispose_game()
	await _create_game(snapshot)


func _boundaries() -> void:
	await _create_game({})
	_game.story.cancel()
	_game.story.seen.assign([Flow.Kind.OPENING])
	_game.run.candy = 10000
	_check(_game.run.purchase_technology("cultivation"), "unlock teaching")
	_game.story._try_teaching()
	_game.story._play_lines()
	get_tree().paused = true
	await _reload_checkpoint()
	_check(_game.story.kind == Flow.Kind.CULTIVATION, "unfinished teaching resumes")
	_check(_game.run.governance_level == 1, "teaching resumes without duplicate purchase")
	_game.story._on_dialogue_finished()
	_game.story._finish_story()
	_check(
		not _game._view.presentation_locked and _game.is_processing(), "teaching releases gameplay"
	)
	# Resume dialogue after its color fill already reached the final frame.
	_game.run.nests[0].level = 3
	_game.run.nests[0].is_tamed = true
	_game.run.completed_nests = 1
	_game.run.unlocked_colors.assign([NestState.Species.SLIME])
	_game._restoration.restore_save({"completed": [NestState.Species.SLIME], "background": false})
	_game.story.kind = Flow.Kind.COLOR_ONE
	_game.story.current_form = 1
	_game.story.active_dialogue = _game.story.color_dialogue
	_game.story._acquire_controls()
	_game.story._play_lines()
	await _reload_checkpoint()
	_check(
		_game.story.kind == Flow.Kind.COLOR_ONE and _game.story._resumed_color_only,
		"completed fill resumes its unfinished dialogue"
	)
	_game.story._on_dialogue_finished()
	_check(
		_game.story.phase == Flow.Phase.RESUMING,
		"resumed color dialogue does not wait for an already finished fill"
	)
	_game.story._finish_story()
	_check(not _game._view.presentation_locked, "resumed color releases controls")
	# A finished dialogue should not replay if the fill had not finished at exit.
	_game._restoration.completed_species.clear()
	_game.story.kind = Flow.Kind.COLOR_ONE
	_game.story.phase = Flow.Phase.WAIT_COLOR
	await _reload_checkpoint()
	_game._restoration.dialogue_pending = true
	_game.story._on_color_started(1)
	_check(
		_game.story.kind == Flow.Kind.NONE and not _game._restoration.dialogue_pending,
		"finished color dialogue is not replayed or left waiting"
	)
	# Finish this presentation before testing independent discovery ownership.
	_game._restoration.restore_save({"completed": [NestState.Species.SLIME], "background": false})
	_game.run.net_unlocked = true
	_game.run._pending_nest_species = NestState.Species.MUCUS
	var pending_position: Vector2 = _game._planet.get_nest_position(1.2)
	_game._nest_discovery.request_discovery(NestState.Species.MUCUS, pending_position)
	await _reload_checkpoint()
	_check(
		_game.run.nests.size() == 2 and _game.run._pending_nest_species == NestState.Species.MUCUS,
		"unrevealed discovery survives reload"
	)
	_check(
		_game._nest_discovery._position.is_equal_approx(pending_position),
		"discovery retains selected site"
	)
	_game._nest_discovery._reveal()
	await _reload_checkpoint()
	_check(
		_game.run.nests.size() == 3 and not _game.run.nests[2].is_discovering,
		"revealed nest settles without duplication"
	)
	_check(_game.run._pending_nest_species == -1, "revealed discovery is not rerolled")
	# F6/preview instantiation must not take over the saved slot.
	await _dispose_game()
	Store.session_requested = false
	_game = GAME.instantiate() as Game
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	await get_tree().process_frame
	_session = _game.get_node("SaveSession") as Session
	_check(not _session.active, "preview scene cannot overwrite player save")
	_check(Store.load_latest().world.run.nests.size() == 3, "preview leaves saved progress intact")
	print("AUTOSAVE BOUNDARIES: %d failures" % _failures)
	GameLifecycle.request_quit()


func _notes() -> void:
	await _create_game({})
	_check(_game.story.briefing.playing, "new game opens the briefing")
	await _reload_checkpoint()
	_check(_game.story.briefing.playing, "unread briefing survives reload")
	_check(
		not _game._overview_background.get_node("星星").visible, "loaded note hides the sky symbols"
	)
	_game.story.briefing.reveal_all()
	_game.story.briefing.close()
	await _game.story.briefing.finished
	await _reload_checkpoint()
	_check(not _game.story.briefing.visible, "read briefing is not repeated")
	_game.story.cancel()
	_game.story.play_receipt()
	await _reload_checkpoint()
	_check(
		_game.story.receipt.playing and _game._view.is_overview(),
		"unread receipt resumes in overview"
	)
	_check(not _game._restoration.core.is_processing(), "loaded receipt holds the core still")
	_game.story.receipt.reveal_all()
	_game.story.receipt.close()
	await _game.story.receipt.finished
	await get_tree().create_timer(0.9).timeout
	await _reload_checkpoint()
	_check(
		_game.story.kind == Flow.Kind.RESCUE and not _game.story.receipt.visible,
		"rescue resumes without repeating receipt"
	)
	_check(not _game._restoration.core.is_processing(), "resumed rescue still holds the core")
	_game.story._on_dialogue_finished()
	_game.story._finish_story()
	_check(
		_game._victory.meteors.visible and _game._completion.playing,
		"resumed rescue starts meteors and credits together"
	)
	print("NOTE SAVE BOUNDARIES: %d failures" % _failures)
	await _dispose_game()
	get_tree().quit(0 if _failures == 0 else 1)
