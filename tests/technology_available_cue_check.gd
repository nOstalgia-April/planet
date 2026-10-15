extends Node

const PlayScene: PackedScene = preload("res://features/场景预览/近景游玩预览.tscn")
const PlayScript = preload("res://features/场景预览/游玩预览.gd")
const PageScript = preload("res://scripts/ui/interactive_technology_page.gd")
const NodeScript = preload("res://scripts/ui/technology_node.gd")
const OUTPUT: String = "res://artifacts/technology_available_cue_20261015"

var _failures: int = 0
var _game: PlayScript
var _page: PageScript


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_game = PlayScene.instantiate() as PlayScript
	add_child(_game)
	_game.set_process(false)
	_game._view.set_process(false)
	_page = _game._layout._technology as PageScript
	_game.run.candy = 400
	_game.run.economy_changed.emit()
	_check(not _page.visible, "game starts with the technology tree closed")
	_check_no_cues("closed resource refresh has no cue")
	for resolution: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		await _wait(0.1)
		_game._layout._show_technology()
		_check(get_tree().paused, "opening the tree pauses gameplay")
		_check_eligible_cues()
		await _wait(0.16)
		await _save("flash_%dx%d" % [resolution.x, resolution.y])
		var pipe: NodeScript = _page._nodes["pipe"]
		var progress: float = pipe._available_cue._progress
		_check(progress > 0.0, "cue animates while gameplay is paused")
		_page.refresh(_game.run)
		_page.select_node("pipe")
		_check(
			pipe._available_cue._progress == progress, "refresh and selection do not replay cues"
		)
		await _wait(0.29)
		await _save("ripple_%dx%d" % [resolution.x, resolution.y])
		await _wait(0.75)
		_check_no_cues("opening cue finishes once")
		await _save("settled_%dx%d" % [resolution.x, resolution.y])
		_page.refresh(_game.run)
		_check_no_cues("later economy refresh does not replay cues")
		_game._layout.close_panels()
		_check(not get_tree().paused, "closing resumes gameplay")
	# All four states coexist: one affordable, one unaffordable, locked branches and owned research.
	_game.run.candy = 10000
	_check(_game.run.purchase_technology("cultivation"), "prepare completed research")
	_game.run.candy = _game.run.get_technology_cost("pipe")
	_game.run.economy_changed.emit()
	_game._layout._show_technology()
	_check(
		_page._nodes["base_value"].state == NodeScript.State.UNAFFORDABLE,
		"prepare unaffordable node"
	)
	_check(
		_page._nodes["cultivation"].state == NodeScript.State.PURCHASED, "prepare completed node"
	)
	_check(_page._nodes["net_unlock"].state == NodeScript.State.LOCKED, "prepare locked node")
	_check_eligible_cues()
	_game.run.candy = 0
	_game.run.economy_changed.emit()
	await get_tree().process_frame
	_check_no_cues("losing affordability cancels the active cue")
	_game.run.candy = 400
	_game.run.economy_changed.emit()
	await get_tree().process_frame
	_check_no_cues("new affordability while open waits until next opening")
	_game._layout.close_panels()
	_game._layout._show_technology()
	_check_eligible_cues()
	_game._on_technology_upgrade("pipe")
	await get_tree().process_frame
	_check(
		not _page._nodes["net_unlock"]._available_cue.visible,
		"newly unlocked research does not replay opening cues"
	)
	_game._layout.close_panels()
	_check_no_cues("closing mid-animation cancels cues")
	_game._layout._show_technology()
	_check_eligible_cues()
	_check(
		_page._nodes["pipe"]._available_cue._progress == 0.0,
		"rapid reopening restarts from the beginning"
	)
	_game._layout.close_panels()
	_game.queue_free()
	_game = null
	_page = null
	await get_tree().process_frame
	print("Technology available cue: %d failures" % _failures)
	get_tree().quit.call_deferred(0 if _failures == 0 else 1)


func _check_eligible_cues() -> void:
	for node: NodeScript in _page._nodes.values():
		_check(
			node._available_cue.visible == (node.state == NodeScript.State.AVAILABLE),
			"only affordable unlocked research flashes: " + node.technology_id
		)


func _check_no_cues(message: String) -> void:
	for node: NodeScript in _page._nodes.values():
		_check(not node._available_cue.visible, message + ": " + node.technology_id)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	_check(
		get_tree().root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png") == OK,
		"fresh game capture: " + label
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
